import SwiftUI

@main
struct SpuleApp: App {
    @State private var recorder = Recorder()
    @State private var tilt = Tilt()
    @Environment(\.scenePhase) private var phase

    init() {
        Typo.registerFonts()
    }

    var body: some Scene {
        WindowGroup {
            FaceplateView()
                .environment(recorder)
                .environment(tilt)
                .onChange(of: phase, initial: true) { _, now in
                    if now == .active { tilt.start() } else { tilt.stop() }
                }
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
