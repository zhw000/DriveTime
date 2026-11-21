import SwiftUI
import MapKit

@main
struct DriveTimeApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

/// Temporary validation screen for the first CI milestone.
/// Replaced by the real DriveTime experience in the next phase.
struct ContentView: View {
    @State private var camera: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 28.58, longitude: 121.37),
            span: MKCoordinateSpan(latitudeDelta: 0.45, longitudeDelta: 0.45)
        )
    )

    var body: some View {
        ZStack(alignment: .top) {
            Map(position: $camera)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 6) {
                Text("DriveTime")
                    .font(.largeTitle.weight(.bold))
                    .foregroundStyle(.primary)
                Text("真实路线，真实时间")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(24)
            .background(.regularMaterial)
        }
    }
}

#Preview {
    ContentView()
}
