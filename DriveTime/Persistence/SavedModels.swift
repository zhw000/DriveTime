import Foundation
import SwiftData

@Model
final class SavedRoute {
    @Attribute(.unique) var id: UUID
    var originName: String
    var originCity: String?
    var originDistrict: String?
    var originAddress: String?
    var originLatitude: Double
    var originLongitude: Double
    var originDatumRaw: String
    var originProviderRaw: String
    var originPlaceID: String?
    var destinationName: String
    var destinationCity: String?
    var destinationDistrict: String?
    var destinationAddress: String?
    var destinationLatitude: Double
    var destinationLongitude: Double
    var destinationDatumRaw: String
    var destinationProviderRaw: String
    var destinationPlaceID: String?
    var providerRaw: String
    var strategyRaw: String
    var distanceMeters: Double
    var durationSeconds: Double
    var tollYuan: Double?
    var departureAt: Date
    var queriedAt: Date
    var arrivalAt: Date
    var isFavorite: Bool
    var routeTitle: String
    var note: String?

    init(
        id: UUID = UUID(),
        origin: LocationResult,
        destination: LocationResult,
        provider: RouteProviderID,
        strategy: RouteStrategy,
        distanceMeters: Double,
        durationSeconds: Double,
        tollYuan: Double?,
        departureAt: Date,
        queriedAt: Date,
        arrivalAt: Date,
        isFavorite: Bool = false,
        routeTitle: String,
        note: String? = nil
    ) {
        self.id = id
        self.originName = origin.name
        self.originCity = origin.city
        self.originDistrict = origin.district
        self.originAddress = origin.address
        self.originLatitude = origin.coordinate.latitude
        self.originLongitude = origin.coordinate.longitude
        self.originDatumRaw = origin.coordinate.datum.rawValue
        self.originProviderRaw = origin.provider.rawValue
        self.originPlaceID = origin.providerPlaceID
        self.destinationName = destination.name
        self.destinationCity = destination.city
        self.destinationDistrict = destination.district
        self.destinationAddress = destination.address
        self.destinationLatitude = destination.coordinate.latitude
        self.destinationLongitude = destination.coordinate.longitude
        self.destinationDatumRaw = destination.coordinate.datum.rawValue
        self.destinationProviderRaw = destination.provider.rawValue
        self.destinationPlaceID = destination.providerPlaceID
        self.providerRaw = provider.rawValue
        self.strategyRaw = strategy.rawValue
        self.distanceMeters = distanceMeters
        self.durationSeconds = durationSeconds
        self.tollYuan = tollYuan
        self.departureAt = departureAt
        self.queriedAt = queriedAt
        self.arrivalAt = arrivalAt
        self.isFavorite = isFavorite
        self.routeTitle = routeTitle
        self.note = note
    }

    init(plan: RoutePlan, isFavorite: Bool = false) {
        let selected = plan.selectedAlternative
        self.init(
            origin: plan.origin,
            destination: plan.destination,
            provider: plan.provider,
            strategy: plan.strategy,
            distanceMeters: selected.distanceMeters,
            durationSeconds: selected.expectedTravelTime,
            tollYuan: selected.tollAmountYuan,
            departureAt: plan.requestedDepartureAt,
            queriedAt: plan.fetchedAt,
            arrivalAt: plan.arrivalDate,
            isFavorite: isFavorite,
            routeTitle: selected.title,
            note: selected.notes.first
        )
    }

    var provider: RouteProviderID {
        RouteProviderID(rawValue: providerRaw) ?? .appleMaps
    }

    var strategy: RouteStrategy {
        RouteStrategy(rawValue: strategyRaw) ?? .recommended
    }

    var originLocation: LocationResult {
        makeLocation(
            name: originName,
            city: originCity,
            district: originDistrict,
            address: originAddress,
            latitude: originLatitude,
            longitude: originLongitude,
            datumRaw: originDatumRaw,
            providerRaw: originProviderRaw,
            placeID: originPlaceID
        )
    }

    var destinationLocation: LocationResult {
        makeLocation(
            name: destinationName,
            city: destinationCity,
            district: destinationDistrict,
            address: destinationAddress,
            latitude: destinationLatitude,
            longitude: destinationLongitude,
            datumRaw: destinationDatumRaw,
            providerRaw: destinationProviderRaw,
            placeID: destinationPlaceID
        )
    }

    private func makeLocation(
        name: String,
        city: String?,
        district: String?,
        address: String?,
        latitude: Double,
        longitude: Double,
        datumRaw: String,
        providerRaw: String,
        placeID: String?
    ) -> LocationResult {
        LocationResult(
            name: name,
            city: city,
            district: district,
            address: address,
            category: nil,
            coordinate: GeoCoordinate(
                latitude: latitude,
                longitude: longitude,
                datum: GeoCoordinate.Datum(rawValue: datumRaw) ?? .wgs84
            ),
            provider: RouteProviderID(rawValue: providerRaw) ?? .appleMaps,
            providerPlaceID: placeID,
            source: .savedPlace
        )
    }
}

@Model
final class SavedPlace {
    @Attribute(.unique) var id: UUID
    var name: String
    var city: String?
    var district: String?
    var address: String?
    var category: String?
    var latitude: Double
    var longitude: Double
    var datumRaw: String
    var providerRaw: String
    var placeID: String?
    var sourceRaw: String
    var createdAt: Date
    var lastUsedAt: Date

    init(location: LocationResult, createdAt: Date = Date()) {
        self.id = UUID()
        self.name = location.name
        self.city = location.city
        self.district = location.district
        self.address = location.address
        self.category = location.category
        self.latitude = location.coordinate.latitude
        self.longitude = location.coordinate.longitude
        self.datumRaw = location.coordinate.datum.rawValue
        self.providerRaw = location.provider.rawValue
        self.placeID = location.providerPlaceID
        self.sourceRaw = location.source.rawValue
        self.createdAt = createdAt
        self.lastUsedAt = createdAt
    }

    var location: LocationResult {
        LocationResult(
            name: name,
            city: city,
            district: district,
            address: address,
            category: category,
            coordinate: GeoCoordinate(
                latitude: latitude,
                longitude: longitude,
                datum: GeoCoordinate.Datum(rawValue: datumRaw) ?? .wgs84
            ),
            provider: RouteProviderID(rawValue: providerRaw) ?? .appleMaps,
            providerPlaceID: placeID,
            source: .savedPlace
        )
    }

    func markUsed(at date: Date = Date()) {
        lastUsedAt = date
    }
}
