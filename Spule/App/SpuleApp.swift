import SwiftUI

@main
struct SpuleApp: App {
    @State private var recorder = Recorder()

    init() {
        Typo.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            FaceplateView()
                .environment(recorder)
                .persistentSystemOverlays(.hidden)
                #if DEBUG
                .task {
                    // `-landscape`: turn the window on its side, for checking the layout in a simulator.
                    guard ProcessInfo.processInfo.arguments.contains("-landscape") else { return }
                    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                    scene?.requestGeometryUpdate(.iOS(interfaceOrientations: .landscapeRight))
                }
                #endif
        }
    }
}
