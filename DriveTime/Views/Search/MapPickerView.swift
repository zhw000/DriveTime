import MapKit
import SwiftUI

struct MapPickerView: View {
    let initialCoordinate: GeoCoordinate?
    let initialName: String
    let onConfirm: (LocationResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var camera: MapCameraPosition
    @State private var center: CLLocationCoordinate2D
    @State private var name: String
    @FocusState private var nameFocused: Bool

    init(
        initialCoordinate: GeoCoordinate?,
        initialName: String,
        onConfirm: @escaping (LocationResult) -> Void
    ) {
        self.initialCoordinate = initialCoordinate
        self.initialName = initialName
        self.onConfirm = onConfirm
        let center = initialCoordinate?.appleMapCoordinate
            ?? CLLocationCoordinate2D(latitude: 30.2741, longitude: 120.1551)
        self._center = State(initialValue: center)
        self._camera = State(initialValue: .region(MKCoordinateRegion(
            center: center,
            latitudinalMeters: 2_400,
            longitudinalMeters: 2_400
        )))
        self._name = State(initialValue: initialName)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Map(position: $camera)
                    .mapStyle(.standard(
                        elevation: .flat,
                        emphasis: .muted,
                        pointsOfInterest: .excludingAll,
                        showsTraffic: false
                    ))
                    .onMapCameraChange(frequency: .continuous) { context in
                        center = context.region.center
                    }
                    .ignoresSafeArea(edges: .bottom)

                centerIndicator
                    .allowsHitTesting(false)
                    .offset(y: -18)

                VStack {
                    Spacer()
                    confirmPanel
                }
            }
            .navigationTitle("地图选点")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
            .toolbarBackground(.ultraThinMaterial, for: .navigationBar)
        }
    }

    private var centerIndicator: some View {
        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(DriveTimeTheme.accent)
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .strokeBorder(.white, lineWidth: 3)
                    )
                    .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
                Image(systemName: "mappin")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
            }
            Rectangle()
                .fill(DriveTimeTheme.accent)
                .frame(width: 2.5, height: 18)
            Ellipse()
                .fill(.black.opacity(0.18))
                .frame(width: 12, height: 4)
                .blur(radius: 1)
        }
    }

    private var confirmPanel: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("放置地图中心点")
                    .font(.headline)
                    .foregroundStyle(DriveTimeTheme.ink)
                Spacer()
                Text(String(format: "%.5f, %.5f", center.latitude, center.longitude))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
            }

            TextField("地点名称（可选）", text: $name)
                .focused($nameFocused)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .padding(.horizontal, 12)
                .frame(height: 42)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(DriveTimeTheme.canvas)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(DriveTimeTheme.hairline.opacity(0.8), lineWidth: 0.5)
                )

            HStack(spacing: 10) {
                Image(systemName: "info.circle")
                    .font(.caption)
                    .foregroundStyle(DriveTimeTheme.tertiaryInk)
                Text("在中国大陆，地图中心点使用 GCJ-02 坐标，并会按地图服务要求转换后查询。")
                    .font(.caption2)
                    .foregroundStyle(DriveTimeTheme.secondaryInk)
                Spacer(minLength: 0)
            }

            PrimaryButton(title: "设为\(initialName)", systemImage: "checkmark") {
                let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                let location = AppleMapItemMapper.location(
                    forMapSelection: center,
                    name: trimmed.isEmpty ? initialName : trimmed
                )
                onConfirm(location)
                dismiss()
            }
            .accessibilityIdentifier("confirmMapSelection")
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(.regularMaterial)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(DriveTimeTheme.hairline.opacity(0.5), lineWidth: 0.5)
        )
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}
