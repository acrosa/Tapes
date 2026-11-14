import SwiftUI

@main
struct TapesApp: App {
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
                // Not at launch: only when the app really goes away and comes back.
                .onChange(of: phase) { _, now in
                    if now == .background { recorder.enteredBackground() } else if now == .active { recorder.becameActive() }
                }
                .persistentSystemOverlays(.hidden)
                #if DEBUG
                .task {
                    // `-landscape` and `-portrait`: turn the window, for checking a layout in a simulator.
                    let arguments = ProcessInfo.processInfo.arguments
                    let turn: UIInterfaceOrientationMask? = arguments.contains("-landscape") ? .landscapeRight
                        : arguments.contains("-portrait") ? .portrait : nil
                    guard let turn else { return }
                    let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
                    scene?.requestGeometryUpdate(.iOS(interfaceOrientations: turn))
                }
                #endif
        }
    }
}
