import AppKit
import CoreText

/// The Snowpine Code fonts, shipped inside the app so the strip looks the same on every Mac.
/// If one is ever missing the strip falls back to the system font rather than failing.
enum BrandFonts {
    static let regularName = "Inter-Regular"
    static let bodyName = "Inter-Medium"
    static let headingName = "PlusJakartaSans-SemiBold"

    static func register() {
        for url in fontFiles() {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }

    /// True when every brand font loaded. The smoke test and the launch check fail without it.
    static var allLoaded: Bool {
        [regularName, bodyName, headingName].allSatisfy { NSFont(name: $0, size: 12) != nil }
    }

    private static func fontFiles() -> [URL] {
        // Inside the app bundle fonts come only from the bundle. A plain `swift build` has no
        // bundle, so development runs read them from the repo's Resources folder.
        let folder: URL
        if Bundle.main.bundleURL.pathExtension == "app" {
            folder = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/Fonts")
        } else {
            folder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("Resources/Fonts")
        }
        let files = (try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.pathExtension == "ttf" }
    }
}
