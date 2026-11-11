import SwiftUI

@main
struct TidyrollApp: App {
    init() {
        #if DEBUG
        // The walkthrough's fresh scan, for the live-scan screenshot and recording.
        if CleanerDemo.has("FreshScan") { try? FileManager.default.removeItem(at: URL.applicationSupportDirectory.appending(path: "Tidyroll/library.plist")) }
        #endif
        CleanerBackground.registerOvernightScan() // must happen before launch finishes
    }

    var body: some Scene {
        WindowGroup {
            #if DEBUG
            CleanerRootView().preferredColorScheme(CleanerDemo.has("Dark") ? .dark : CleanerDemo.has("Light") ? .light : nil)
            #else
            CleanerRootView()
            #endif
        }
    }
}
