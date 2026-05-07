import SwiftUI

// MARK: - Colors
enum AppColors {
    // Primary teal palette
    static let boltGreen      = Color(hex: 0x00C9A7)
    static let boltGreenDark  = Color(hex: 0x009E85)
    static let boltGreenDeep  = Color(hex: 0x00251F)
    static let boltGreenLight = Color(hex: 0xD0F5F0)

    // Neutral grays
    static let gray900 = Color(hex: 0x111827)
    static let gray700 = Color(hex: 0x374151)
    static let gray500 = Color(hex: 0x6B7280)
    static let gray400 = Color(hex: 0x9CA3AF)
    static let gray300 = Color(hex: 0xD1D5DB)
    static let gray100 = Color(hex: 0xF3F4F6)
    static let gray50  = Color(hex: 0xF7F8F9)

    // Semantic
    static let successGreen  = Color(hex: 0x22C55E)
    static let warningAmber  = Color(hex: 0xF59E0B)
    static let errorRed      = Color(hex: 0xEF4444)

    // Extended
    static let backgroundLight = Color(hex: 0xF7F8F9)
    static let backgroundCard  = Color(hex: 0xF3F4F6)
    static let accentBlue      = Color(hex: 0x3B82F6)
    static let starYellow      = Color(hex: 0xFACC15)
    static let darkSurface     = Color(hex: 0x1A1A2E)
    static let whatsAppGreen   = Color(hex: 0x25D366)
    static let badgeRed        = Color(hex: 0xEF4444)
    static let routeGreen      = Color(hex: 0x00B894)
    static let driverBannerMint = Color(hex: 0xD0F5F0)

    // Legacy
    static let background  = backgroundLight
    static let primary     = boltGreen
    static let textPrimary = gray900
}

// MARK: - Typography
enum AppFont {
    private static let family = "Plus Jakarta Sans"

    static func displayLarge(_ size: CGFloat = 57) -> Font {
        .custom(family, size: size).weight(.bold)
    }
    static func displayMedium(_ size: CGFloat = 45) -> Font {
        .custom(family, size: size).weight(.bold)
    }
    static func displaySmall(_ size: CGFloat = 36) -> Font {
        .custom(family, size: size).weight(.bold)
    }
    static func headlineLarge(_ size: CGFloat = 32) -> Font {
        .custom(family, size: size).weight(.bold)
    }
    static func headlineMedium(_ size: CGFloat = 28) -> Font {
        .custom(family, size: size).weight(.bold)
    }
    static func headlineSmall(_ size: CGFloat = 24) -> Font {
        .custom(family, size: size).weight(.semibold)
    }
    static func titleLarge(_ size: CGFloat = 22) -> Font {
        .custom(family, size: size).weight(.semibold)
    }
    static func titleMedium(_ size: CGFloat = 16) -> Font {
        .custom(family, size: size).weight(.semibold)
    }
    static func titleSmall(_ size: CGFloat = 14) -> Font {
        .custom(family, size: size).weight(.semibold)
    }
    static func bodyLarge(_ size: CGFloat = 16) -> Font {
        .custom(family, size: size).weight(.regular)
    }
    static func bodyMedium(_ size: CGFloat = 14) -> Font {
        .custom(family, size: size).weight(.regular)
    }
    static func bodySmall(_ size: CGFloat = 12) -> Font {
        .custom(family, size: size).weight(.regular)
    }
    static func labelLarge(_ size: CGFloat = 14) -> Font {
        .custom(family, size: size).weight(.semibold)
    }
    static func labelMedium(_ size: CGFloat = 12) -> Font {
        .custom(family, size: size).weight(.medium)
    }
    static func labelSmall(_ size: CGFloat = 11) -> Font {
        .custom(family, size: size).weight(.medium)
    }

    // Convenience aliases
    static func title(_ size: CGFloat = 22) -> Font { titleLarge(size) }
    static func body(_ size: CGFloat = 16) -> Font  { bodyLarge(size) }
}

// MARK: - Radius
enum AppRadius {
    static let r8:  CGFloat = 8
    static let r10: CGFloat = 10
    static let r12: CGFloat = 12
    static let r16: CGFloat = 16
    static let r20: CGFloat = 20
    static let r24: CGFloat = 24
    static let r28: CGFloat = 28
    static let r32: CGFloat = 32
}

// MARK: - Color hex initialiser
extension Color {
    init(hex: UInt32, alpha: Double = 1.0) {
        let red   = Double((hex >> 16) & 0xFF) / 255.0
        let green = Double((hex >> 8)  & 0xFF) / 255.0
        let blue  = Double( hex        & 0xFF) / 255.0
        self.init(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
