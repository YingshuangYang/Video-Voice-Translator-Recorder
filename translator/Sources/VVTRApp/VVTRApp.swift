import AppKit
import SwiftUI
import VVTRCore

@main
struct VVTRApp: App {
  @StateObject private var appModel = AppModel()
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

  var body: some Scene {
    WindowGroup {
      RootView()
        .environmentObject(appModel)
        .frame(minWidth: 980, minHeight: 640)
        .onAppear {
          // When launched via `swift run`, the app may not become active/key.
          NSApp.setActivationPolicy(.regular)
          NSApp.activate(ignoringOtherApps: true)
        }
    }
    .windowStyle(.automatic)
  }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.regular)
    NSApp.activate(ignoringOtherApps: true)
  }
}

