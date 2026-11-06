import AppKit
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    var model: AppModel?

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
                        .credits: NSAttributedString(string: "Turn recordings into searchable transcripts, right on your Mac. Nothing leaves this computer.\n\nMade by Snowpine Code. Free and open source under the MIT License. snowpinecode.com"),
                    ])
                }
            }
        }
    }
}
