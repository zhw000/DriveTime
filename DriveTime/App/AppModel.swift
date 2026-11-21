import Foundation
import Observation
import SwiftData
import SwiftUI

@MainActor
@Observable
final class AppModel {
    let settings: AppSettings
    let history: HistoryStore
    let locationService: LocationService
    let planner: RoutePlannerViewModel

    init(modelContainer: ModelContainer) {
        let settings = AppSettings()
        let history = HistoryStore(context: modelContainer.mainContext)
        let locationService = LocationService()
        self.settings = settings
        self.history = history
        self.locationService = locationService
        self.planner = RoutePlannerViewModel(settings: settings, history: history)
    }

    func makePlaceSearchViewModel(for endpoint: TripEndpoint) -> PlaceSearchViewModel {
        PlaceSearchViewModel(
            endpoint: endpoint,
            engine: PlaceSearchEngineFactory.make(for: settings),
            locationService: locationService
        )
    }

    func handleSelectedPlace(_ location: LocationResult, endpoint: TripEndpoint) {
        planner.setEndpoint(location, for: endpoint)
    }

    func clearHistory() {
        history.clearHistory(keepingFavorites: true)
    }
}

enum AppContainer {
    static func make() -> ModelContainer {
        do {
            return try ModelContainer(for: SavedRoute.self, SavedPlace.self)
        } catch {
            AppLog.persistence.error(
                "Persistent store unavailable; using in-memory store: \(String(describing: error), privacy: .public)"
            )
            do {
                return try ModelContainer(
                    for: SavedRoute.self,
                    SavedPlace.self,
                    configurations: ModelConfiguration(isStoredInMemoryOnly: true)
                )
            } catch {
                fatalError("Unable to create an in-memory SwiftData store: \(error)")
            }
        }
    }
}
