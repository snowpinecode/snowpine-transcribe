import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

    /// In-app updates start here, with a check on launch when automatic checks are on.
    @MainActor func applicationDidFinishLaunching(_ notification: Notification) {
        Updater.shared.start(checkNow: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }

    @MainActor func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        (model?.confirmQuit() ?? true) ? .terminateNow : .terminateCancel
    }

    /// Open With, or a file dropped on the app's icon.
    @MainActor func application(_ application: NSApplication, open urls: [URL]) {
        model?.add(urls)
    }
}

struct SnowpineTranscribeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = AppModel()
    @StateObject private var updater = Updater.shared

    var body: some Scene {
        WindowGroup("Snowpine Transcribe") {
            RootView(model: model)
                .onAppear { delegate.model = model }
        }
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("Transcribe a File\u{2026}") { model.chooseFiles() }.keyboardShortcut("o")
            }
            CommandGroup(replacing: .appInfo) {
                Button("About Snowpine Transcribe") {
                    NSApp.orderFrontStandardAboutPanel(options: [
                        .credits: NSAttributedString(string: "Turn recordings into searchable transcripts, right on your Mac. Recordings and transcripts never leave this computer. The only network use is checking GitHub for updates.\n\nMade by Snowpine Code. Free and open source under the MIT License. snowpinecode.com"),
                    ])
                }
            }
            CommandGroup(after: .appInfo) {
                UpdateCommands(updater: updater)
            }
        }
    }
}

/// App menu, after About: Check for Updates and Check for Updates Automatically.
/// Shown only in the packaged app, where Sparkle is running.
struct UpdateCommands: View {
    @ObservedObject var updater: Updater

    var body: some View {
        if updater.isAvailable {
            Button("Check for Updates\u{2026}") { updater.checkForUpdates() }
                .disabled(!updater.canCheckForUpdates)
            Toggle("Check for Updates Automatically", isOn: $updater.automaticallyChecks)
        }
    }
}
