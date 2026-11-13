import SwiftUI

@main
struct PocketHeadApp: App {
    @UIApplicationDelegateAdaptor(PreviewOrientationDelegate.self) private var appDelegate
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var model = HeadTrackingViewModel()

    var body: some Scene {
        WindowGroup {
            ContentView(model: model)
                .onAppear { model.becameActive() }
                .onChange(of: scenePhase) { _, phase in
                    switch phase {
                    case .active: model.becameActive()
                    case .background: model.suspend()
                    case .inactive:
                        model.endCameraZoom()
                        model.touchGuard.setSceneActive(false)
                    @unknown default: break
                    }
                }
        }
    }
}
