import CoreLocation
import Foundation

/// Well-known public coordinate conversion used only to place coordinates on
/// the correct map datum. This is not a proprietary implementation.
enum ChinaCoordinateTransform {
    private static let a = 6_378_245.0
    private static let ee = 0.006_693_421_622_965_943
    private static let pi = Double.pi

    /// A conservative bounding box for mainland China. Hong Kong, Macau and
    /// Taiwan are deliberately outside this box; AMap mainland routing is not
    /// used automatically there.
    static func isInChina(latitude: Double, longitude: Double) -> Bool {
        guard latitude.isFinite, longitude.isFinite else { return false }
        let inBroadChina = longitude > 73.66 && longitude < 135.05
            && latitude > 3.86 && latitude < 53.55
        guard inBroadChina else { return false }
        return !isExcludedRegion(latitude: latitude, longitude: longitude)
    }

    private static func isExcludedRegion(latitude: Double, longitude: Double) -> Bool {
        // Taiwan
        if longitude >= 119.18, longitude <= 122.01, latitude >= 21.89, latitude <= 25.31 {
            return true
        }
        // Hong Kong
        if longitude >= 113.82, longitude <= 114.51, latitude >= 22.13, latitude <= 22.58 {
            return true
        }
        // Macau
        if longitude >= 113.52, longitude <= 113.60, latitude >= 22.10, latitude <= 22.23 {
            return true
        }
        return false
    }

    static func wgs84ToGcj02(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard coordinate.isValidMapCoordinate else { return coordinate }
        guard isInChina(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
            return coordinate
        }
        let dLat = transformLat(x: coordinate.longitude - 105.0, y: coordinate.latitude - 35.0)
        let dLng = transformLng(x: coordinate.longitude - 105.0, y: coordinate.latitude - 35.0)
        let radLat = coordinate.latitude / 180.0 * pi
        var magic = sin(radLat)
        magic = 1 - ee * magic * magic
        let sqrtMagic = sqrt(magic)
        let latitudeDelta = (dLat * 180.0) / ((a * (1 - ee)) / (magic * sqrtMagic) * pi)
        let longitudeDelta = (dLng * 180.0) / (a / sqrtMagic * cos(radLat) * pi)
        return CLLocationCoordinate2D(
            latitude: coordinate.latitude + latitudeDelta,
            longitude: coordinate.longitude + longitudeDelta
        )
    }

    /// Iterative inverse. GCJ-02 has no closed form; iterating the forward
    /// transform converges to sub-centimetre accuracy after a few passes.
    static func gcj02ToWgs84(_ coordinate: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard coordinate.isValidMapCoordinate else { return coordinate }
        guard isInChina(latitude: coordinate.latitude, longitude: coordinate.longitude) else {
            return coordinate
        }
        var result = coordinate
        for _ in 0..<8 {
            let forward = wgs84ToGcj02(result)
            result.latitude -= forward.latitude - coordinate.latitude
            result.longitude -= forward.longitude - coordinate.longitude
        }
        return result
    }

    private static func transformLat(x: Double, y: Double) -> Double {
        var ret = -100.0 + 2.0 * x + 3.0 * y + 0.2 * y * y + 0.1 * x * y
            + 0.2 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(y * pi) + 40.0 * sin(y / 3.0 * pi)) * 2.0 / 3.0
        ret += (160.0 * sin(y / 12.0 * pi) + 320.0 * sin(y * pi / 30.0)) * 2.0 / 3.0
        return ret
    }

    private static func transformLng(x: Double, y: Double) -> Double {
        var ret = 300.0 + x + 2.0 * y + 0.1 * x * x + 0.1 * x * y
            + 0.1 * sqrt(abs(x))
        ret += (20.0 * sin(6.0 * x * pi) + 20.0 * sin(2.0 * x * pi)) * 2.0 / 3.0
        ret += (20.0 * sin(x * pi) + 40.0 * sin(x / 3.0 * pi)) * 2.0 / 3.0
        ret += (150.0 * sin(x / 12.0 * pi) + 300.0 * sin(x / 30.0 * pi)) * 2.0 / 3.0
        return ret
    }
}
