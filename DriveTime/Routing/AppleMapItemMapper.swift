import CoreLocation
import Foundation
import MapKit

enum AppleMapItemMapper {
    static func location(from mapItem: MKMapItem) -> LocationResult? {
        let placemark = mapItem.placemark
        let coordinate = placemark.coordinate
        guard coordinate.isValidMapCoordinate else { return nil }
        let datum: GeoCoordinate.Datum = ChinaCoordinateTransform.isInChina(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        ) ? .gcj02 : .wgs84
        let name = mapItem.name
            ?? placemark.name
            ?? placemark.title
            ?? "未命名地点"
        let addressPieces = [placemark.thoroughfare, placemark.subThoroughfare]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let address = addressPieces.isEmpty ? placemark.title : addressPieces.joined()
        return LocationResult(
            name: name,
            city: placemark.locality ?? placemark.administrativeArea,
            district: placemark.subLocality ?? placemark.subAdministrativeArea,
            address: address,
            category: mapItem.pointOfInterestCategory?.rawValue,
            coordinate: GeoCoordinate(coordinate, datum: datum),
            provider: .appleMaps,
            providerPlaceID: nil,
            source: .appleMapKit
        )
    }

    static func location(
        forMapSelection coordinate: CLLocationCoordinate2D,
        name: String
    ) -> LocationResult {
        let isChina = ChinaCoordinateTransform.isInChina(
            latitude: coordinate.latitude,
            longitude: coordinate.longitude
        )
        return LocationResult(
            name: name,
            city: nil,
            district: nil,
            address: "地图坐标 \(String(format: "%.5f, %.5f", coordinate.latitude, coordinate.longitude))",
            category: nil,
            coordinate: GeoCoordinate(coordinate, datum: isChina ? .gcj02 : .wgs84),
            provider: .appleMaps,
            providerPlaceID: nil,
            source: .mapSelection
        )
    }
}
