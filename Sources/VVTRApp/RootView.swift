import SwiftUI

struct RootView: View {
  var body: some View {
    NavigationSplitView {
      SidebarView()
    } detail: {
      TabView {
        LiveView()
          .tabItem { Label("实时", systemImage: "waveform") }

        HistoryView()
          .tabItem { Label("历史", systemImage: "clock") }

        SettingsView()
          .tabItem { Label("设置", systemImage: "gearshape") }
      }
      .padding()
    }
  }
}

