import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HistoryStore {
    private let context: ModelContext

    private(set) var recentRoutes: [SavedRoute] = []
    private(set) var favoriteRoutes: [SavedRoute] = []
    private(set) var favoritePlaces: [SavedPlace] = []
    private(set) var lastError: String?

    init(context: ModelContext) {
        self.context = context
        refresh()
    }

    func refresh() {
        do {
            let routeDescriptor = FetchDescriptor<SavedRoute>(
                sortBy: [SortDescriptor(\.queriedAt, order: .reverse)]
            )
            let routes = try context.fetch(routeDescriptor)
            recentRoutes = Array(routes.prefix(50))
            favoriteRoutes = routes.filter(\.isFavorite)
            let placeDescriptor = FetchDescriptor<SavedPlace>(
                sortBy: [SortDescriptor(\.lastUsedAt, order: .reverse)]
            )
            favoritePlaces = try context.fetch(placeDescriptor)
            lastError = nil
        } catch {
            lastError = "读取历史记录失败。"
            AppLog.persistence.error("History fetch failed: \(String(describing: error), privacy: .public)")
        }
    }

    @discardableResult
    func record(plan: RoutePlan) -> SavedRoute {
        let existingFavorite = favoriteRoutes.first {
            $0.originName == plan.origin.name
                && $0.destinationName == plan.destination.name
                && $0.providerRaw == plan.provider.rawValue
        }
        let saved = SavedRoute(plan: plan, isFavorite: existingFavorite != nil)
        context.insert(saved)
        trimIfNeeded()
        save()
        refresh()
        return saved
    }

    func toggleFavorite(route: SavedRoute) {
        route.isFavorite.toggle()
        save()
        refresh()
    }

    func route(withID id: UUID) -> SavedRoute? {
        recentRoutes.first { $0.id == id }
    }

    func toggleFavoritePlace(_ location: LocationResult) {
        if let existing = favoritePlaces.first(where: { matches($0, location) }) {
            context.delete(existing)
            save()
            refresh()
            return
        }
        context.insert(SavedPlace(location: location))
        save()
        refresh()
    }

    func isFavoritePlace(_ location: LocationResult) -> Bool {
        favoritePlaces.contains { matches($0, location) }
    }

    func delete(route: SavedRoute) {
        context.delete(route)
        save()
        refresh()
    }

    func delete(place: SavedPlace) {
        context.delete(place)
        save()
        refresh()
    }

    func clearHistory(keepingFavorites: Bool = true) {
        for route in recentRoutes where !(keepingFavorites && route.isFavorite) {
            context.delete(route)
        }
        save()
        refresh()
    }

    func clearFavorites() {
        for route in favoriteRoutes {
            route.isFavorite = false
        }
        for place in favoritePlaces {
            context.delete(place)
        }
        save()
        refresh()
    }

    func touch(place: SavedPlace) {
        place.markUsed()
        save()
        refresh()
    }

    private func matches(_ saved: SavedPlace, _ location: LocationResult) -> Bool {
        if let lhs = saved.placeID, let rhs = location.providerPlaceID,
           lhs == rhs, saved.providerRaw == location.provider.rawValue {
            return true
        }
        let savedCoordinate = GeoCoordinate(
            latitude: saved.latitude,
            longitude: saved.longitude,
            datum: GeoCoordinate.Datum(rawValue: saved.datumRaw) ?? .wgs84
        )
        return saved.name == location.name
            && savedCoordinate.groundDistance(to: location.coordinate) < 50
    }

    private func trimIfNeeded() {
        // Keep the local SwiftData store bounded. Favorites are never removed
        // automatically.
        guard recentRoutes.count > 80 else { return }
        let nonFavorites = recentRoutes.filter { !$0.isFavorite }
        for route in nonFavorites.prefix(max(0, nonFavorites.count - 60)) {
            context.delete(route)
        }
    }

    private func save() {
        do {
            try context.save()
            lastError = nil
        } catch {
            lastError = "保存历史记录失败。"
            AppLog.persistence.error("History save failed: \(String(describing: error), privacy: .public)")
        }
    }
}
