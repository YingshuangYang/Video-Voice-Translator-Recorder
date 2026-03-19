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

                Button {
                    model.answerSelectedQuestions()
                } label: {
                    Label("回答已选问题", systemImage: "checklist")
                }
                .disabled(model.selectedQuestionSegmentIDs.isEmpty)

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
                    if let status = model.systemAudioStatusMessage {
                        Text(status)
                            .font(.caption)
                    }
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
                .frame(minWidth: 380)

                VStack(alignment: .leading, spacing: 8) {
                    Text("中文内容")
                        .font(.headline)
                    ContentListView(outputs: model.outputs.filter { $0.kind == .translation })
                }
                .frame(minWidth: 320)

                VStack(alignment: .leading, spacing: 8) {
                    Text("回答")
                        .font(.headline)
                    AnswerListView(outputs: model.outputs.filter { $0.kind == .answer })
                }
                .frame(minWidth: 320)
            }
        }
        .sheet(isPresented: $model.isSummaryEditorPresented) {
            SummaryEditorView()
                .environmentObject(model)
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}

private struct TranscriptListView: View {
    @EnvironmentObject private var model: AppModel
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
                            if model.isQuestionSegment(seg) {
                                Button {
                                    model.toggleQuestionSelection(seg.id)
                                } label: {
                                    Label(
                                        model.isQuestionSelected(seg.id) ? "已选问题" : "选为问题",
                                        systemImage: model.isQuestionSelected(seg.id) ? "checkmark.circle.fill" : "circle"
                                    )
                                }
                                .buttonStyle(.borderless)
                            }
                            Spacer()
                            Text(seg.createdAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TypewriterText(seg.text)
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

private struct ContentListView: View {
    let outputs: [VVTROutput]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(outputs) { out in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            if let sourceLanguage = out.sourceLanguage, !sourceLanguage.isEmpty {
                                Text(sourceLanguage.uppercased())
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(out.createdAt, style: .time)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        TypewriterText(out.outputText)
                            .textSelection(.enabled)
                    }
                    .padding(10)
                    .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 10))
                }
                if outputs.isEmpty {
                    Text("还没有中文内容。中文原文和翻译结果都会显示在这里。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
        }
    }
}

private struct AnswerListView: View {
    let outputs: [VVTROutput]

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(outputs) { out in
                    VStack(alignment: .leading, spacing: 8) {
                        Text("回答结果")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TypewriterText(out.outputText)
                            .textSelection(.enabled)
                    }
                    .padding(12)
                    .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
                    )
                }
                if outputs.isEmpty {
                    Text("勾选左侧问题后，点击“回答已选问题”，答案会单独显示在这里。")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 24)
                }
            }
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

private struct TypewriterText: View {
    let text: String
    @State private var visibleCount: Int = 0

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(String(text.prefix(visibleCount)))
            .task(id: text) {
                await animateText()
            }
    }

    private func animateText() async {
        let characters = Array(text)
        guard !characters.isEmpty else {
            visibleCount = 0
            return
        }

        visibleCount = 0
        let delay = UInt64(text.count > 120 ? 800_000 : 1_500_000)
        for index in characters.indices {
            if Task.isCancelled { return }
            visibleCount = index + 1
            try? await Task.sleep(nanoseconds: delay)
        }
    }
}
