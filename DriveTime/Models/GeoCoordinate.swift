import CoreLocation
import Foundation

/// A coordinate whose datum is explicit. DriveTime never crosses a provider
/// boundary without converting through the correct datum.
struct GeoCoordinate: Hashable, Codable, Sendable {
    enum Datum: String, Codable, Sendable {
        /// GPS / CLLocationManager coordinates.
        case wgs84
        /// Chinese statutory map coordinates used by AMap, Apple Maps in
        /// mainland China, Tencent Maps and most Chinese POI services.
        case gcj02

        var displayName: String {
            switch self {
            case .wgs84: "WGS-84"
            case .gcj02: "GCJ-02"
            }
        }
    }

    var latitude: Double
    var longitude: Double
    var datum: Datum

    init(latitude: Double, longitude: Double, datum: Datum) {
        self.latitude = latitude
        self.longitude = longitude
        self.datum = datum
    }

    init(_ coordinate: CLLocationCoordinate2D, datum: Datum) {
        self.init(latitude: coordinate.latitude, longitude: coordinate.longitude, datum: datum)
    }

    var isValid: Bool {
        latitude.isFinite && longitude.isFinite
            && latitude >= -90 && latitude <= 90
            && longitude >= -180 && longitude <= 180
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var isInMainlandChina: Bool {
        ChinaCoordinateTransform.isInChina(latitude: latitude, longitude: longitude)
    }

    /// Coordinates suitable for MapKit / Apple Maps in mainland China.
    /// MapKit's China basemap and MKLocalSearch use GCJ-02; GPS coordinates
    /// from CoreLocation are WGS-84 and need conversion before display.
    var appleMapCoordinate: CLLocationCoordinate2D {
        switch datum {
        case .gcj02:
            clCoordinate
        case .wgs84:
            if isInMainlandChina {
                ChinaCoordinateTransform.wgs84ToGcj02(clCoordinate)
            } else {
                clCoordinate
            }
        }
    }

    /// Coordinates suitable for the AMap Web Service API (always GCJ-02 in
    /// mainland China).
    var amapCoordinate: CLLocationCoordinate2D {
        switch datum {
        case .gcj02:
            clCoordinate
        case .wgs84:
            if isInMainlandChina {
                ChinaCoordinateTransform.wgs84ToGcj02(clCoordinate)
            } else {
                clCoordinate
            }
        }
    }

    /// GPS coordinates, useful for distance calculations independent of datum.
    var wgs84Coordinate: CLLocationCoordinate2D {
        switch datum {
        case .wgs84:
            clCoordinate
        case .gcj02:
            if isInMainlandChina {
                ChinaCoordinateTransform.gcj02ToWgs84(clCoordinate)
            } else {
                clCoordinate
            }
        }
    }

    func converted(to datum: Datum) -> GeoCoordinate {
        switch (self.datum, datum) {
        case (.wgs84, .wgs84), (.gcj02, .gcj02):
            return self
        case (.wgs84, .gcj02):
            return GeoCoordinate(ChinaCoordinateTransform.wgs84ToGcj02(clCoordinate), datum: .gcj02)
        case (.gcj02, .wgs84):
            return GeoCoordinate(ChinaCoordinateTransform.gcj02ToWgs84(clCoordinate), datum: .wgs84)
        }
    }

    func distance(to other: GeoCoordinate) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    /// Distance using WGS-84 on both sides so mixed datum inputs compare
    /// correctly.
    func groundDistance(to other: GeoCoordinate) -> CLLocationDistance {
        CLLocation(latitude: wgs84Coordinate.latitude, longitude: wgs84Coordinate.longitude)
            .distance(from: CLLocation(
                latitude: other.wgs84Coordinate.latitude,
                longitude: other.wgs84Coordinate.longitude
            ))
    }

    var shortCoordinateText: String {
        String(format: "%.5f, %.5f", latitude, longitude)
    }
}

extension CLLocationCoordinate2D {
    var isValidMapCoordinate: Bool {
        CLLocationCoordinate2DIsValid(self)
            && abs(latitude) <= 90 && abs(longitude) <= 180
    }
}
