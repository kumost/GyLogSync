import SwiftUI

@main
struct GyLogSyncApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 700, minHeight: 650)
                .navigationTitle("GyLog Sync")
        }
        .windowStyle(.hiddenTitleBar)
    }
}
