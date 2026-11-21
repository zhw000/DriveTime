import AppIntents

/// Registers DriveTime's voice/Shortcuts entry point without a separate Siri
/// Intents extension. Every phrase must contain the applicationName token.
///
/// App Shortcut phrases use at most one dynamic parameter; these phrases omit
/// parameters entirely and let Siri prompt for the required origin/destination
/// with the intent's requestValueDialog strings.
struct DriveTimeAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: DriveTimeRouteIntent(),
            phrases: [
                "用 \(.applicationName) 查询驾车时间",
                "让 \(.applicationName) 计算车程",
                "问 \(.applicationName) 这段路要开多久"
            ],
            shortTitle: "查询车程",
            systemImageName: "car.fill"
        )
    }
}
