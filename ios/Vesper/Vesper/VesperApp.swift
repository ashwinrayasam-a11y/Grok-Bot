import SwiftUI

@main
struct VesperApp: App {
    @StateObject private var model = ChatViewModel()

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(VesperTheme.ember)
        }
    }
}
