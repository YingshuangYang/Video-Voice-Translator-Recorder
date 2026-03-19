import SwiftUI

struct RootView: View {
  @EnvironmentObject private var model: AppModel

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
    .sheet(isPresented: $model.isSummaryEditorPresented) {
      SummaryEditorView()
        .environmentObject(model)
        .frame(minWidth: 760, minHeight: 560)
    }
  }
}

private struct SummaryEditorView: View {
  @EnvironmentObject private var model: AppModel
  @Environment(\.dismiss) private var dismiss

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      HStack {
        Text("会议总结")
          .font(.title2)
          .fontWeight(.semibold)
        Spacer()
      }

      Text("总结已生成。你可以先修改内容，再保存 PDF。")
        .foregroundStyle(.secondary)

      TextEditor(text: $model.summaryDraft)
        .font(.body)
        .padding(8)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12))

      HStack {
        Button("关闭") {
          dismiss()
        }

        Spacer()

        Button("保存修改") {
          model.saveEditedSummary()
        }

        Button("保存 PDF") {
          model.saveEditedSummary()
          model.exportCurrentSessionSummaryPDF()
        }
        .buttonStyle(.borderedProminent)
      }
    }
    .padding(20)
  }
}
