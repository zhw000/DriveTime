import Foundation
import OSLog

enum AppLog {
    private static let subsystem = Bundle.main.bundleIdentifier ?? "com.example.drivetime"

    static let routing = Logger(subsystem: subsystem, category: "routing")
    static let search = Logger(subsystem: subsystem, category: "search")
    static let location = Logger(subsystem: subsystem, category: "location")
    static let persistence = Logger(subsystem: subsystem, category: "persistence")
    static let settings = Logger(subsystem: subsystem, category: "settings")
    static let network = Logger(subsystem: subsystem, category: "network")
}
