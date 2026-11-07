import AppKit
import Combine
import Sparkle

/// In-app updates with Sparkle. The app itself has no network access: Sparkle's separate Downloader
/// service fetches the update feed and the new version from GitHub, and its Installer service swaps
/// the app in place. Every update is checked against the EdDSA public key in Info.plist before it
/// is installed. Recordings and transcripts are never part of this. This is the only file that
/// imports Sparkle (scripts/check-no-network.sh enforces it).
@MainActor
final class Updater: NSObject, ObservableObject, SPUUpdaterDelegate {
    static let shared = Updater()

    private var controller: SPUStandardUpdaterController?
    /// True once Sparkle is running (the packaged app only). The menu items appear then.
    @Published private(set) var isAvailable = false
    /// Sparkle turns this off while a check is already in progress.
    @Published private(set) var canCheckForUpdates = false

    /// Starts Sparkle only in the packaged app (it needs the feed URL and key from Info.plist). The
    /// command line modes return before the app starts, so this never runs during the checks.
    func start(checkNow: Bool) {
        guard controller == nil,
              Bundle.main.bundleURL.pathExtension == "app",
              Bundle.main.object(forInfoDictionaryKey: "SUFeedURL") != nil,
              Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") != nil else { return }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: self, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates)
            .receive(on: DispatchQueue.main)
            .assign(to: &$canCheckForUpdates)
        isAvailable = true
        // Tell people about a new version when they open the app, not only once a day.
        if checkNow, controller.updater.automaticallyChecksForUpdates {
            controller.updater.checkForUpdatesInBackground()
        }
    }

    /// The off switch is absolute: with automatic checks off, no check starts unless the person chose
    /// Check for Updates, even one Sparkle had already scheduled.
    nonisolated func updater(_ updater: SPUUpdater, mayPerform updateCheck: SPUUpdateCheck) throws {
        let automatic = MainActor.assumeIsolated { updater.automaticallyChecksForUpdates }  // called on the main thread
        if updateCheck == .updatesInBackground && !automatic {
            throw NSError(domain: "SnowpineTranscribe.Updater", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Automatic update checks are off."])
        }
    }

    /// Menu: Check for Updates...
    func checkForUpdates() {
        NSApp.activate()
        controller?.checkForUpdates(nil)
    }

    /// Menu: Check for Updates Automatically. Off means no update traffic at all unless asked.
    var automaticallyChecks: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }
}

/// `SnowpineTranscribe --update-check` (packaged app only): asks Sparkle's Downloader helper to read the update
/// feed and reports what it found, with no window, no Dock icon and no menu bar. Proves the update path
/// works inside the sandbox.
@MainActor
final class UpdateCheck: NSObject, SPUUpdaterDelegate {
    private var updater: SPUUpdater?

    /// Runs until Sparkle answers (or 30 seconds pass), then exits the process with the result.
    static func run() -> Int32 {
        _ = NSApplication.shared
        NSApp.setActivationPolicy(.prohibited)  // nothing on screen
        let check = UpdateCheck()
        check.start()
        NSApp.run()
        return 1  // not reached: finish() exits
    }

    private func start() {
        let driver = SPUStandardUserDriver(hostBundle: .main, delegate: nil)
        let updater = SPUUpdater(hostBundle: .main, applicationBundle: .main, userDriver: driver, delegate: self)
        self.updater = updater
        do {
            try updater.start()
        } catch {
            finish("UPDATE-CHECK FAIL start: \(error.localizedDescription)", code: 1)
            return
        }
        updater.checkForUpdateInformation()
        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { self.finish("UPDATE-CHECK FAIL timed out", code: 1) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        let version = item.displayVersionString
        MainActor.assumeIsolated { finish("UPDATE-CHECK OK update available: \(version)", code: 0) }
    }

    nonisolated func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) {
        MainActor.assumeIsolated { finish("UPDATE-CHECK OK feed read, no newer version", code: 0) }
    }

    nonisolated func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        var parts: [String] = []
        var current: NSError? = error as NSError
        while let e = current {
            parts.append("\(e.domain) \(e.code): \(e.localizedDescription)")
            current = e.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        let text = parts.joined(separator: " <- ")
        MainActor.assumeIsolated { finish("UPDATE-CHECK RESULT \(text)", code: 2) }
    }

    private func finish(_ line: String, code: Int32) {
        print(line)
        fflush(stdout)
        exit(code)
    }
}
