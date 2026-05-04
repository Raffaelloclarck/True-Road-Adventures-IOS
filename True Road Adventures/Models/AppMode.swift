import Foundation

enum AppMode {
    case customer
    case driver

    var bundleIdOverrideKey: String {
        switch self {
        case .customer: return "CUSTOMER_BUNDLE_ID"
        case .driver: return "DRIVER_BUNDLE_ID"
        }
    }
}
