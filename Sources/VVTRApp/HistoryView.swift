import SwiftUI
import VVTRCore
import VVTRStorage

struct HistoryView: View {
  @EnvironmentObject private var model: AppModel
  @State private var query: String = ""
  @State private var dbOutputs: [VVTROutput] = []

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        TextField("按关键词筛选（SQLite 检索）", text: $query)
          .textFieldStyle(.roundedBorder)
          .onChange(of: query) { newValue in
            refresh(keyword: newValue)
          }
        Spacer()
      }

      Divider()

      List {
        Section("数据库输出（最近）") {
          ForEach(dbFilteredOutputs) { out in
            VStack(alignment: .leading, spacing: 6) {
              Text(out.outputText)
                .lineLimit(3)
              Text(out.createdAt, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
          }
        }
      }
      .onAppear { refresh(keyword: query) }
    }
  }

  private var dbFilteredOutputs: [VVTROutput] {
    dbOutputs
  }

  private func refresh(keyword: String) {
    let q = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    if q.isEmpty {
      dbOutputs = VVTRDatabase.shared.listOutputs(limit: 200)
    } else {
      dbOutputs = VVTRDatabase.shared.searchOutputs(keyword: q, limit: 200)
    }
  }
}

