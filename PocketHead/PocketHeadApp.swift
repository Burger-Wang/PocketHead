import SwiftUI

@main
struct PocketHeadApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = HeadTrackingViewModel()

    init() {
        if #available(iOS 26.0, *) {
            ContinuedTrackingSession.shared.register()
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { model.becameActive() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: model.becameActive()
                    case .background: model.enteredBackground()
                    case .inactive: break
                    @unknown default: break
                    }
                }
        }
    }
}
