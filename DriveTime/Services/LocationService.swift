import CoreLocation
import Foundation
import Observation

enum LocationServiceError: Error, Equatable {
    case permissionDenied
    case unavailable
    case timeout
    case accuracyInsufficient
    case cancelled
}

@MainActor
@Observable
final class LocationService: NSObject, CLLocationManagerDelegate {
    private let manager: CLLocationManager
    private var continuation: CheckedContinuation<CLLocation, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var waitingForAuthorization = false

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var isRequesting = false

    override init() {
        let manager = CLLocationManager()
        self.manager = manager
        self.authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = kCLDistanceFilterNone
    }

    var isAuthorized: Bool {
        authorizationStatus == .authorizedWhenInUse || authorizationStatus == .authorizedAlways
    }

    var permissionExplanation: String {
        switch authorizationStatus {
        case .notDetermined:
            return "允许定位后，可以直接把当前位置设为起点。"
        case .authorizedAlways, .authorizedWhenInUse:
            return "定位权限已开启。位置只在本机用于路线查询。"
        case .denied:
            return "定位权限已关闭。你可以在系统设置中开启，或手动搜索起点。"
        case .restricted:
            return "此设备限制了定位功能。"
        @unknown default:
            return "定位权限状态未知。"
        }
    }

    func refreshAuthorizationStatus() {
        authorizationStatus = manager.authorizationStatus
    }

    func requestCurrentLocation() async throws -> CLLocation {
        guard continuation == nil else {
            throw LocationServiceError.unavailable
        }
        refreshAuthorizationStatus()
        switch authorizationStatus {
        case .notDetermined:
            waitingForAuthorization = true
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                isRequesting = true
                scheduleTimeout()
                manager.requestWhenInUseAuthorization()
            }
        case .denied, .restricted:
            throw LocationServiceError.permissionDenied
        case .authorizedAlways, .authorizedWhenInUse:
            return try await withCheckedThrowingContinuation { continuation in
                self.continuation = continuation
                isRequesting = true
                scheduleTimeout()
                manager.requestLocation()
            }
        @unknown default:
            throw LocationServiceError.unavailable
        }
    }

    private func scheduleTimeout() {
        timeoutWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.finish(.failure(LocationServiceError.timeout))
        }
        timeoutWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 18, execute: item)
    }

    private func finish(_ result: Result<CLLocation, Error>) {
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        waitingForAuthorization = false
        isRequesting = false
        guard let continuation else { return }
        self.continuation = nil
        switch result {
        case .success(let location):
            continuation.resume(returning: location)
        case .failure(let error):
            continuation.resume(throwing: error)
        }
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        authorizationStatus = manager.authorizationStatus
        if waitingForAuthorization, isAuthorized, continuation != nil {
            waitingForAuthorization = false
            manager.requestLocation()
            return
        }
        if waitingForAuthorization,
           authorizationStatus == .denied || authorizationStatus == .restricted,
           continuation != nil {
            finish(.failure(LocationServiceError.permissionDenied))
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            finish(.failure(LocationServiceError.unavailable))
            return
        }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy <= 1_500 else {
            finish(.failure(LocationServiceError.accuracyInsufficient))
            return
        }
        finish(.success(location))
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        if let clError = error as? CLError {
            switch clError.code {
            case .denied:
                finish(.failure(LocationServiceError.permissionDenied))
            case .locationUnknown:
                finish(.failure(LocationServiceError.unavailable))
            default:
                finish(.failure(LocationServiceError.unavailable))
            }
        } else {
            finish(.failure(LocationServiceError.unavailable))
        }
    }
}

extension LocationServiceError {
    var providerError: RouteProviderError {
        switch self {
        case .permissionDenied:
            return .locationPermissionDenied
        case .unavailable:
            return .locationUnavailable
        case .timeout:
            return .timedOut
        case .accuracyInsufficient:
            return .locationAccuracyInsufficient
        case .cancelled:
            return .cancelled
        }
    }
}
