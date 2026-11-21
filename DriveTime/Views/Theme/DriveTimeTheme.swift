import SwiftUI
import UIKit

enum DriveTimeTheme {
    static let accent = Color(red: 0.925, green: 0.333, blue: 0.196)
    static let accentDeep = Color(red: 0.745, green: 0.216, blue: 0.102)
    static let ink = dynamic(light: UIColor(hex: 0x18201D), dark: UIColor(hex: 0xF3F1E9))
    static let secondaryInk = dynamic(light: UIColor(hex: 0x69716D), dark: UIColor(hex: 0x9AA39E))
    static let tertiaryInk = dynamic(light: UIColor(hex: 0x8D948F), dark: UIColor(hex: 0x727B76))
    static let canvas = dynamic(light: UIColor(hex: 0xF3F2ED), dark: UIColor(hex: 0x0D1210))
    static let surface = dynamic(light: UIColor(hex: 0xFEFDF9), dark: UIColor(hex: 0x1A201D))
    static let surfaceElevated = dynamic(light: UIColor(hex: 0xFFFFFF), dark: UIColor(hex: 0x222925))
    static let hairline = dynamic(light: UIColor(hex: 0xE3E1D9), dark: UIColor(hex: 0x313934))
    static let routeAlternative = dynamic(light: UIColor(hex: 0x9AA39E), dark: UIColor(hex: 0x6E7B74))
    static let origin = dynamic(light: UIColor(hex: 0x1D6A55), dark: UIColor(hex: 0x6CC3A8))
    static let destination = accent
    static let warning = dynamic(light: UIColor(hex: 0xB85C12), dark: UIColor(hex: 0xF4A85C))
    static let success = dynamic(light: UIColor(hex: 0x2B7A4B), dark: UIColor(hex: 0x7CCB9B))
    static let danger = dynamic(light: UIColor(hex: 0xB33A2E), dark: UIColor(hex: 0xFF8E82))
    static let smooth = dynamic(light: UIColor(hex: 0x2E9D62), dark: UIColor(hex: 0x5BD393))
    static let slow = dynamic(light: UIColor(hex: 0xE3A61C), dark: UIColor(hex: 0xF4C34C))
    static let congested = dynamic(light: UIColor(hex: 0xE8652B), dark: UIColor(hex: 0xFF9157))
    static let severelyCongested = dynamic(light: UIColor(hex: 0xB32E2E), dark: UIColor(hex: 0xFF6D67))
    static let unknownTraffic = dynamic(light: UIColor(hex: 0xAAB0AC), dark: UIColor(hex: 0x5D6862))

    static let cardRadius: CGFloat = 20
    static let controlRadius: CGFloat = 14
    static let contentPadding: CGFloat = 18
    static let maxContentWidth: CGFloat = 620

    static func dynamic(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: alpha
        )
    }
}

extension TrafficInformation.Level {
    var color: Color {
        switch self {
        case .smooth: DriveTimeTheme.smooth
        case .slow: DriveTimeTheme.slow
        case .congested: DriveTimeTheme.congested
        case .severelyCongested: DriveTimeTheme.severelyCongested
        case .unknown: DriveTimeTheme.unknownTraffic
        }
    }
}

extension View {
    func driveTimeCard(background: Color = DriveTimeTheme.surface) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: DriveTimeTheme.cardRadius, style: .continuous)
                    .fill(background)
            )
            .overlay(
                RoundedRectangle(cornerRadius: DriveTimeTheme.cardRadius, style: .continuous)
                    .strokeBorder(DriveTimeTheme.hairline.opacity(0.7), lineWidth: 0.5)
            )
    }
}
