import SwiftUI

@main
struct NotabilityCloneApp: App {
    var body: some Scene {
        WindowGroup {
            NotebookListView()
                .environment(AppStore.shared)
        }
    }
}