import SwiftUI
import VVTRCore

@main
struct VVTRApp: App {
  @StateObject private var appModel = AppModel()

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(appModel)
        .frame(minWidth: 980, minHeight: 640)
    }
    .windowStyle(.automatic)
  }
}

