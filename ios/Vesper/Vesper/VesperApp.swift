import SwiftUI

@main
struct VesperApp: App {
    @StateObject private var model = ChatViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ChatView()
                .environmentObject(model)
                .preferredColorScheme(.dark)
                .tint(VesperTheme.ember)
                .onChange(of: scenePhase) {
                    model.scenePhaseChanged(scenePhase)
                }
        }
    }
}
