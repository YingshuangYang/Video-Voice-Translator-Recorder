import SwiftUI
import VVTRCore

struct SidebarView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    List(selection: Binding(get: { model.currentSession?.id }, set: { newId in
      guard let newId else { return }
      model.loadSession(newId)
    })) {
      Section("会话") {
        ForEach(model.sessions) { s in
          Text(s.title)
            .tag(s.id)
        }
        .onDelete(perform: model.deleteSessions)
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
      ToolbarItem(placement: .secondaryAction) {
        Button(role: .destructive) {
          if let currentID = model.currentSession?.id,
             let index = model.sessions.firstIndex(where: { $0.id == currentID }) {
            model.deleteSessions(at: IndexSet(integer: index))
          }
        } label: {
          Label("删除当前会话", systemImage: "trash")
        }
        .disabled(model.currentSession == nil)
      }
    }
    .onAppear {
      if model.sessions.isEmpty {
        model.startNewSession()
      }
    }
  }
}

