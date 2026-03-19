import SwiftUI
import VVTRCore

struct SidebarView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    List(selection: Binding(get: { model.currentSession?.id }, set: { newId in
      guard let newId else { return }
      model.currentSession = model.sessions.first(where: { $0.id == newId })
    })) {
      Section("会话") {
        ForEach(model.sessions) { s in
          Text(s.title)
            .tag(s.id)
        }
      }
    }
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button {
          model.startNewSession()
        } label: {
          Label("新会话", systemImage: "plus")
        }
      }
    }
    .onAppear {
      if model.sessions.isEmpty {
        model.startNewSession()
      }
    }
  }
}

