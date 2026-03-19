import SwiftUI
import VVTRCore

struct LiveView: View {
  @EnvironmentObject private var model: AppModel

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        if model.isCapturing {
          Button(role: .destructive) {
            model.stopCapture()
          } label: {
            Label("停止采集", systemImage: "stop.fill")
          }
        } else {
          Button {
            model.startCapture()
          } label: {
            Label("开始采集（系统音频+麦克风）", systemImage: "record.circle")
          }
        }

        Button {
          if model.currentSession == nil { model.startNewSession() }
          model.appendMockData()
        } label: {
          Label("追加演示数据", systemImage: "sparkles")
        }

        Spacer()

        if let s = model.currentSession {
          Text(s.title)
            .font(.headline)
            .foregroundStyle(.secondary)
        }
      }

      HStack(spacing: 12) {
        Group {
          Text("系统音频：")
          Text(model.lastSystemAudioAt.map { "\($0.formatted(date: .omitted, time: .standard))" } ?? "—")
            .monospaced()
        }
        .foregroundStyle(.secondary)

        Group {
          Text("麦克风：")
          Text(model.lastMicAudioAt.map { "\($0.formatted(date: .omitted, time: .standard))" } ?? "—")
            .monospaced()
        }
        .foregroundStyle(.secondary)
      }

      Divider()

      HSplitView {
        VStack(alignment: .leading, spacing: 8) {
          Text("转写（原文）")
            .font(.headline)
          TranscriptListView(segments: model.segments)
        }
        .frame(minWidth: 420)

        VStack(alignment: .leading, spacing: 8) {
          Text("中文输出（总结/翻译/回答）")
            .font(.headline)
          OutputListView(outputs: model.outputs)
        }
        .frame(minWidth: 420)
      }
    }
  }
}

private struct TranscriptListView: View {
  let segments: [VVTRTranscriptSegment]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 10) {
        ForEach(segments) { seg in
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
              Text(seg.source.rawValue.uppercased())
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
              if let lang = seg.language, !lang.isEmpty {
                Text(lang.uppercased())
                  .font(.caption)
                  .foregroundStyle(.secondary)
              }
              Spacer()
              Text(seg.createdAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(seg.text)
              .textSelection(.enabled)
          }
          .padding(10)
          .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        if segments.isEmpty {
          Text("还没有转写内容。点击“开始/追加演示数据”，或稍后接入真实采集后会实时出现。")
            .foregroundStyle(.secondary)
            .padding(.vertical, 24)
        }
      }
    }
  }
}

private struct OutputListView: View {
  let outputs: [VVTROutput]

  var body: some View {
    ScrollView {
      LazyVStack(alignment: .leading, spacing: 10) {
        ForEach(outputs) { out in
          VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
              Text(out.kind.rawValue.uppercased())
                .font(.caption)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.quaternary, in: Capsule())
              Text(out.intent == .question ? "QUESTION" : "STATEMENT")
                .font(.caption)
                .foregroundStyle(.secondary)
              Spacer()
              Text(out.createdAt, style: .time)
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Text(out.outputText)
              .textSelection(.enabled)
          }
          .padding(10)
          .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
        }
        if outputs.isEmpty {
          Text("还没有输出结果。接入 LLM 处理后会在这里显示总结/翻译/回答。")
            .foregroundStyle(.secondary)
            .padding(.vertical, 24)
        }
      }
    }
  }
}

