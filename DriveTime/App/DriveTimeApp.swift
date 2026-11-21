import SwiftUI
import SwiftData
import MapKit

@main
struct DriveTimeApp: App {
    @State private var appModel: AppModel
    private let container: ModelContainer

    init() {
        let container = AppContainer.make()
        self.container = container
        _appModel = State(initialValue: AppModel(modelContainer: container))
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .modelContainer(container)
                .tint(DriveTimeTheme.accent)
        }
    }
}
