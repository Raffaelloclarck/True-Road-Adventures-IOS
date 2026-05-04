import Foundation
import CoreText

enum FontRegistrar {
    static func registerFonts() {
        _once
    }

    // Static let is initialised at most once (lazy + thread-safe by Swift runtime),
    // preventing "file already registered" warnings when SwiftUI re-creates the App struct.
    private static let _once: Void = {
        let fontNames = ["PlusJakartaSans"]
        for name in fontNames {
            guard let url = Bundle.main.url(forResource: name, withExtension: "ttf") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }()
}
