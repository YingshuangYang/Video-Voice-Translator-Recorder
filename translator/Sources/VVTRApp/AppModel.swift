import AppKit
import Foundation
import SwiftUI
import VVTRCore
import VVTRCapture
import VVTRCloud
import VVTRStorage

@MainActor
final class AppModel: ObservableObject {
  @Published var settings: VVTRSettings = .init()
  @Published var currentSession: VVTRSession?
  @Published var sessions: [VVTRSession] = []
  @Published var segments: [VVTRTranscriptSegment] = []
  @Published var outputs: [VVTROutput] = []
  @Published var selectedQuestionSegmentIDs: Set<UUID> = []
  @Published var summaryDraft: String = ""
  @Published var isSummaryEditorPresented: Bool = false
  @Published var isCapturing: Bool = false
  @Published var lastSystemAudioAt: Date?
  @Published var lastMicAudioAt: Date?
  @Published var systemAudioStatusMessage: String?

  private let settingsStore: VVTRSettingsStore
  private var capture: VVTRAudioCaptureManager?
  private var systemChunker: VVTRChunker?
  private var micChunker: VVTRChunker?
  private var asr: VVTRASRPipeline?
  private var llm: (any VVTRLLMHandling)?

  private static let asrErrorPrefix = "ASR_ERROR: "

  init() {
    self.settingsStore = (try? VVTRSettingsStore()) ?? {
      // fallback: put settings in temp dir (should never happen)
      try! VVTRSettingsStore(appName: "VVTR-fallback")
    }()

    Task { [weak self] in
      guard let self else { return }
      let loaded = await settingsStore.load()
      self.settings = loaded
      let savedSessions = VVTRDatabase.shared.listSessions(limit: 500)
      self.sessions = savedSessions
      if let first = savedSessions.first {
        self.loadSession(first.id)
      }
    }
  }

  func saveSettings() {
    let s = settings
    Task {
      try? await settingsStore.save(s)
    }
  }

  func startNewSession() {
    let session = VVTRSession(title: defaultTitle())
    currentSession = session
    sessions.insert(session, at: 0)
    segments.removeAll()
    outputs.removeAll()
    selectedQuestionSegmentIDs.removeAll()
    VVTRDatabase.shared.upsertSession(session)
  }

  func loadSession(_ sessionID: UUID) {
    guard let session = sessions.first(where: { $0.id == sessionID }) else { return }
    currentSession = session
    segments = VVTRDatabase.shared.listSegments(sessionId: sessionID)
    outputs = VVTRDatabase.shared.listOutputs(sessionId: sessionID)
    selectedQuestionSegmentIDs.removeAll()
    summaryDraft = outputs.last(where: { $0.kind == .summary })?.outputText ?? ""
    isSummaryEditorPresented = false
  }

  func deleteSessions(at offsets: IndexSet) {
    let deleting = offsets.map { sessions[$0] }
    let deletingIDs = Set(deleting.map(\.id))

    if deletingIDs.contains(currentSession?.id ?? UUID()) {
      stopCaptureIfNeeded()
    }

    for session in deleting {
      VVTRDatabase.shared.deleteSession(id: session.id)
    }

    sessions.remove(atOffsets: offsets)

    if let current = currentSession, deletingIDs.contains(current.id) {
      if let replacement = sessions.first {
        loadSession(replacement.id)
      } else {
        currentSession = nil
        segments.removeAll()
        outputs.removeAll()
        selectedQuestionSegmentIDs.removeAll()
      }
    }
  }

  func startCapture() {
    guard capture == nil else { return }
    if currentSession == nil { startNewSession() }
    isCapturing = true
    systemAudioStatusMessage = nil

    if #available(macOS 13.0, *) {
      let sessionId = currentSession?.id ?? UUID()
      let chunkConfig = VVTRChunker.Config(
        chunkSeconds: max(settings.chunkSeconds, 20),
        overlapSeconds: settings.overlapSeconds
      )

      switch settings.provider {
      case .openai:
        guard !settings.openAIAPIKey.isEmpty else { break }
        let baseURL = URL(string: settings.openAIBaseURL) ?? URL(string: "https://api.openai.com/v1")!
        let client = VVTROpenAIClient(config: .init(apiKey: settings.openAIAPIKey, model: settings.openAIModel, baseURL: baseURL))
        llm = VVTRLLMPipeline(client: client, onResult: { [weak self] kind, intent, outputText, json in
          Task { @MainActor in
            guard let self else { return }
            let out = VVTROutput(
              sessionId: sessionId,
              kind: kind,
              intent: intent,
              sourceText: "",
              outputText: outputText,
              jsonPayload: self.settings.privacyMode == .storeNoRawJSON ? nil : json
            )
            self.outputs.append(out)
            VVTRDatabase.shared.insertOutput(out)
            if kind == .summary {
              self.summaryDraft = outputText
              self.isSummaryEditorPresented = true
            }
          }
        })

        let llmPipeline = llm
        asr = VVTRASRPipeline(provider: .openai(client), onTranscript: { [weak self] lang, text, raw in
          Task { @MainActor in
            guard let self else { return }
            if let raw, self.handleASRErrorIfNeeded(raw: raw, sessionId: sessionId) { return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let isZh = VVTRTextHeuristics.isLikelyChinese(text, detectedLanguage: lang)
            let isQ = VVTRTextHeuristics.looksLikeQuestion(text)
            let intent: VVTRIntent = isQ ? .question : .statement

            let seg = VVTRTranscriptSegment(
              sessionId: sessionId,
              source: .mixed,
              language: lang,
              text: self.settings.privacyMode == .storeNoAudioText ? "" : text
            )
            self.segments.append(seg)
            VVTRDatabase.shared.insertSegment(seg)

            if isZh {
              let out = VVTROutput(
                sessionId: sessionId,
                segmentId: seg.id,
                kind: .translation,
                sourceLanguage: lang,
                intent: intent,
                sourceText: self.settings.privacyMode == .storeNoAudioText ? "" : text,
                outputText: text,
                jsonPayload: self.settings.privacyMode == .storeNoRawJSON ? nil : raw
              )
              self.outputs.append(out)
              VVTRDatabase.shared.insertOutput(out)
            }

            if !isZh {
              Task { [llmPipeline] in
                if let llmPipeline {
                  await llmPipeline.handle(text: text, isChinese: false, intent: .statement)
                }
              }
            }
          }
        })
      case .gemini:
        guard !settings.geminiAPIKey.isEmpty else { break }
        let baseURL = URL(string: settings.geminiBaseURL) ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!
        let g = VVTRGeminiClient(config: .init(apiKey: settings.geminiAPIKey, model: settings.geminiModel, baseURL: baseURL))

        llm = VVTRLLMPipelineGemini(client: g, onResult: { [weak self] kind, intent, outputText, json in
          Task { @MainActor in
            guard let self else { return }
            let out = VVTROutput(
              sessionId: sessionId,
              kind: kind,
              intent: intent,
              sourceText: "",
              outputText: outputText,
              jsonPayload: self.settings.privacyMode == .storeNoRawJSON ? nil : json
            )
            self.outputs.append(out)
            VVTRDatabase.shared.insertOutput(out)
            if kind == .summary {
              self.summaryDraft = outputText
              self.isSummaryEditorPresented = true
            }
          }
        })
        let llmPipeline = llm

        asr = VVTRASRPipeline(provider: .gemini(g), onTranscript: { [weak self] lang, text, raw in
          Task { @MainActor in
            guard let self else { return }
            if let raw, self.handleASRErrorIfNeeded(raw: raw, sessionId: sessionId) { return }
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
            let isZh = VVTRTextHeuristics.isLikelyChinese(text, detectedLanguage: lang)
            let isQ = VVTRTextHeuristics.looksLikeQuestion(text)
            let intent: VVTRIntent = isQ ? .question : .statement

            let seg = VVTRTranscriptSegment(
              sessionId: sessionId,
              source: .mixed,
              language: lang,
              text: self.settings.privacyMode == .storeNoAudioText ? "" : text
            )
            self.segments.append(seg)
            VVTRDatabase.shared.insertSegment(seg)

            if isZh {
              let out = VVTROutput(
                sessionId: sessionId,
                segmentId: seg.id,
                kind: .translation,
                sourceLanguage: lang,
                intent: intent,
                sourceText: self.settings.privacyMode == .storeNoAudioText ? "" : text,
                outputText: text,
                jsonPayload: self.settings.privacyMode == .storeNoRawJSON ? nil : raw
              )
              self.outputs.append(out)
              VVTRDatabase.shared.insertOutput(out)
            }

            if !isZh {
              Task { [llmPipeline] in
                if let llmPipeline {
                  await llmPipeline.handle(text: text, isChinese: false, intent: .statement)
                }
              }
            }
          }
        })
      }

      if asr == nil || llm == nil {
        asr = nil
        llm = nil
        outputs.append(
          VVTROutput(
            sessionId: sessionId,
            kind: .summary,
            intent: .statement,
            sourceText: "",
            outputText: "未配置云端 Key：请到“设置”选择 Provider 并填写对应 API Key。",
            jsonPayload: nil
          )
        )
      }

      let asrPipeline = asr

      let sysChunker = VVTRChunker(config: chunkConfig, onChunk: { chunk in
        Task { [asrPipeline] in
          if let asrPipeline { await asrPipeline.process(chunk: chunk) }
        }
      })
      let micChunker = VVTRChunker(config: chunkConfig, onChunk: { chunk in
        Task { [asrPipeline] in
          if let asrPipeline { await asrPipeline.process(chunk: chunk) }
        }
      })

      systemChunker = sysChunker
      self.micChunker = micChunker

      Task {
        let micGranted: Bool
        switch VVTRPermissions.microphoneAuthorizationState() {
        case .authorized:
          micGranted = true
        case .notDetermined:
          micGranted = await VVTRPermissions.requestMicrophoneAccess()
        case .denied, .restricted:
          micGranted = false
        }

        if !micGranted {
          await MainActor.run {
            self.isCapturing = false
            self.capture = nil
            self.outputs.append(
              VVTROutput(
                sessionId: self.currentSession?.id ?? UUID(),
                kind: .summary,
                intent: .statement,
                sourceText: "",
                outputText: "麦克风权限未开启。应用会先检查当前授权状态；如果你之前已拒绝，请到系统设置中手动允许后重试。"
              )
            )
          }
          return
        }
        // Start capture; ingest buffers into chunkers.
        let mgr = VVTRAudioCaptureManager(callbacks: .init(
          onSystemPCMBuffer: { [weak self] buf, at in
            Task { @MainActor in
              self?.lastSystemAudioAt = at
              self?.systemAudioStatusMessage = nil
            }
            if let pcm = VVTRPCM.interleavedInt16Data(from: buf) {
              Task { await sysChunker.ingestInterleavedInt16PCM(pcm.data, sampleRate: pcm.sampleRate, channels: pcm.channels, source: "system") }
            }
          },
          onMicPCMBuffer: { [weak self] buf, at in
            Task { @MainActor in self?.lastMicAudioAt = at }
            if let pcm = VVTRPCM.interleavedInt16Data(from: buf) {
              Task { await micChunker.ingestInterleavedInt16PCM(pcm.data, sampleRate: pcm.sampleRate, channels: pcm.channels, source: "mic") }
            }
          },
          onWarning: { [weak self] err in
            Task { @MainActor in
              self?.systemAudioStatusMessage = "系统音频不可用"
            }
          },
          onError: { [weak self] err in
            Task { @MainActor in
              self?.isCapturing = false
              self?.capture = nil
              self?.outputs.append(
                VVTROutput(
                  sessionId: self?.currentSession?.id ?? UUID(),
                  kind: .summary,
                  intent: .statement,
                  sourceText: "",
                  outputText: "采集错误：\(err.localizedDescription)"
                )
              )
            }
          }
        ))
        await MainActor.run { self.capture = mgr }
        await mgr.start(systemAudio: true, microphone: true)
      }
    } else {
      isCapturing = false
      capture = nil
    }
  }

  func stopCapture() {
    stopCaptureIfNeeded()
    generateSummary()
    llm = nil
  }

  func generateSummary() {
    let transcript = segments
      .map(\.text)
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
      .joined(separator: "\n")

    guard let sessionId = currentSession?.id else {
      presentSummaryFallback(
        sessionId: nil,
        message: "当前还没有会话。请先开始采集，或先追加一些演示数据，再生成会议总结。"
      )
      return
    }

    let content = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else {
      presentSummaryFallback(
        sessionId: sessionId,
        message: "还没有可总结的转写内容。请先开始采集，或追加一些演示数据后再停止采集。"
      )
      llm = nil
      return
    }

    guard let llmPipeline = makeLLMPipeline(sessionId: sessionId) else {
      presentSummaryFallback(
        sessionId: sessionId,
        message: "未配置可用的总结模型。请先到“设置”中选择 Provider，并填写对应 API Key 后再生成会议总结。"
      )
      llm = nil
      return
    }

    Task { @MainActor in
      await llmPipeline.summarizeSession(transcript: content)
    }
  }

  func exportCurrentSessionSummaryPDF() {
    guard let session = currentSession else { return }
    let summary = summaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !summary.isEmpty else {
      outputs.append(
        VVTROutput(
          sessionId: session.id,
          kind: .summary,
          intent: .statement,
          sourceText: "",
          outputText: "还没有可导出的会议总结，请先停止采集并生成总结。"
        )
      )
      return
    }

    let panel = NSSavePanel()
    panel.allowedContentTypes = [.pdf]
    panel.nameFieldStringValue = "\(sanitizedFileName(session.title))-summary.pdf"

    guard panel.runModal() == .OK, let url = panel.url else { return }

    do {
      let pdfData = makeSummaryPDFData(session: session, summary: summary)
      try pdfData.write(to: url)
    } catch {
      outputs.append(
        VVTROutput(
          sessionId: session.id,
          kind: .summary,
          intent: .statement,
          sourceText: "",
          outputText: "导出 PDF 失败：\(error.localizedDescription)"
        )
      )
    }
  }

  func saveEditedSummary() {
    guard let sessionId = currentSession?.id else { return }
    let content = summaryDraft.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }

    if let index = outputs.lastIndex(where: { $0.kind == .summary }) {
      outputs[index].outputText = content
    }

    let saved = VVTROutput(
      sessionId: sessionId,
      kind: .summary,
      intent: .statement,
      sourceText: "",
      outputText: content
    )
    outputs.append(saved)
    VVTRDatabase.shared.insertOutput(saved)
  }

  func appendMockData() {
    guard let sessionId = currentSession?.id else { return }
    let seg = VVTRTranscriptSegment(
      sessionId: sessionId,
      source: .mixed,
      language: "zh",
      text: "大家好，今天我们讨论一下如何把系统音频和麦克风同时采集，并进行实时总结。"
    )
    segments.append(seg)
    outputs.append(
      VVTROutput(
        sessionId: sessionId,
        segmentId: seg.id,
        kind: .summary,
        sourceLanguage: "zh",
        intent: .statement,
        sourceText: seg.text,
        outputText: "摘要：讨论同时采集系统音频与麦克风，并进行实时总结的实现思路。"
      )
    )
  }

  func isQuestionSegment(_ segment: VVTRTranscriptSegment) -> Bool {
    VVTRTextHeuristics.looksLikeQuestion(segment.text)
  }

  func isQuestionSelected(_ segmentID: UUID) -> Bool {
    selectedQuestionSegmentIDs.contains(segmentID)
  }

  func toggleQuestionSelection(_ segmentID: UUID) {
    if selectedQuestionSegmentIDs.contains(segmentID) {
      selectedQuestionSegmentIDs.remove(segmentID)
    } else {
      selectedQuestionSegmentIDs.insert(segmentID)
    }
  }

  func answerSelectedQuestions() {
    guard let sessionId = currentSession?.id else { return }
    guard let llmPipeline = makeLLMPipeline(sessionId: sessionId) else {
      outputs.append(
        VVTROutput(
          sessionId: sessionId,
          kind: .answer,
          intent: .question,
          sourceText: "",
          outputText: "未配置可用的云端问答模型，请先在设置中填写 API Key。"
        )
      )
      return
    }

    let targets = segments.filter { selectedQuestionSegmentIDs.contains($0.id) && isQuestionSegment($0) }
    guard !targets.isEmpty else { return }

    for segment in targets {
      let text = segment.text.trimmingCharacters(in: .whitespacesAndNewlines)
      let isChinese = VVTRTextHeuristics.isLikelyChinese(text, detectedLanguage: segment.language)
      guard !text.isEmpty else { continue }
      Task {
        await llmPipeline.handle(text: text, isChinese: isChinese, intent: .question)
      }
    }

    selectedQuestionSegmentIDs.subtract(targets.map(\.id))
  }

  private func stopCaptureIfNeeded() {
    capture?.stop()
    capture = nil
    isCapturing = false
    systemChunker = nil
    micChunker = nil
    asr = nil
  }

  private func makeSummaryPDFData(session: VVTRSession, summary: String) -> Data {
    let titleFont = NSFont.boldSystemFont(ofSize: 22)
    let bodyFont = NSFont.systemFont(ofSize: 13)
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4

    let content = NSMutableAttributedString(
      string: "\(session.title)\n",
      attributes: [
        .font: titleFont,
        .foregroundColor: NSColor.labelColor,
      ]
    )
    content.append(NSAttributedString(
      string: "生成时间：\(Date().formatted(date: .abbreviated, time: .shortened))\n\n",
      attributes: [
        .font: NSFont.systemFont(ofSize: 11),
        .foregroundColor: NSColor.secondaryLabelColor,
      ]
    ))
    content.append(NSAttributedString(
      string: summary,
      attributes: [
        .font: bodyFont,
        .foregroundColor: NSColor.labelColor,
        .paragraphStyle: paragraph,
      ]
    ))

    let pageWidth: CGFloat = 595
    let textWidth: CGFloat = 515
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: textWidth, height: 842))
    textView.textContainerInset = NSSize(width: 0, height: 0)
    textView.isEditable = false
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.textContainer?.containerSize = NSSize(width: textWidth, height: .greatestFiniteMagnitude)
    textView.textContainer?.widthTracksTextView = true
    textView.textStorage?.setAttributedString(content)
    textView.layoutManager?.ensureLayout(for: textView.textContainer!)
    let textHeight = (textView.layoutManager?.usedRect(for: textView.textContainer!).height ?? 0) + 40

    let documentView = NSView(frame: NSRect(x: 0, y: 0, width: pageWidth, height: max(842, textHeight + 80)))
    textView.frame = NSRect(x: 40, y: 40, width: textWidth, height: max(762, textHeight))
    documentView.addSubview(textView)
    return documentView.dataWithPDF(inside: documentView.bounds)
  }

  private func sanitizedFileName(_ value: String) -> String {
    let invalid = CharacterSet(charactersIn: "/:\\?%*|\"<>")
    let cleaned = value.components(separatedBy: invalid).joined(separator: "-")
    return cleaned.isEmpty ? "meeting" : cleaned
  }

  private func defaultTitle() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm"
    return "会话 \(df.string(from: Date()))"
  }

  private func presentSummaryFallback(sessionId: UUID?, message: String) {
    let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return }

    summaryDraft = trimmed
    isSummaryEditorPresented = true

    if let sessionId {
      let out = VVTROutput(
        sessionId: sessionId,
        kind: .summary,
        intent: .statement,
        sourceText: "",
        outputText: trimmed
      )
      outputs.append(out)
      VVTRDatabase.shared.insertOutput(out)
    }
  }

  private func makeLLMPipeline(sessionId: UUID) -> (any VVTRLLMHandling)? {
    switch settings.provider {
    case .openai:
      guard !settings.openAIAPIKey.isEmpty else { return nil }
      let baseURL = URL(string: settings.openAIBaseURL) ?? URL(string: "https://api.openai.com/v1")!
      let client = VVTROpenAIClient(config: .init(apiKey: settings.openAIAPIKey, model: settings.openAIModel, baseURL: baseURL))
      return VVTRLLMPipeline(client: client, onResult: { [weak self] kind, intent, outputText, json in
        Task { @MainActor in
          guard let self else { return }
          let out = VVTROutput(
            sessionId: sessionId,
            kind: kind,
            intent: intent,
            sourceText: "",
            outputText: outputText,
            jsonPayload: self.settings.privacyMode == .storeNoRawJSON ? nil : json
          )
          self.outputs.append(out)
          VVTRDatabase.shared.insertOutput(out)
          if kind == .summary {
            self.summaryDraft = outputText
            self.isSummaryEditorPresented = true
          }
        }
      })
    case .gemini:
      guard !settings.geminiAPIKey.isEmpty else { return nil }
      let baseURL = URL(string: settings.geminiBaseURL) ?? URL(string: "https://generativelanguage.googleapis.com/v1beta")!
      let client = VVTRGeminiClient(config: .init(apiKey: settings.geminiAPIKey, model: settings.geminiModel, baseURL: baseURL))
      return VVTRLLMPipelineGemini(client: client, onResult: { [weak self] kind, intent, outputText, json in
        Task { @MainActor in
          guard let self else { return }
          let out = VVTROutput(
            sessionId: sessionId,
            kind: kind,
            intent: intent,
            sourceText: "",
            outputText: outputText,
            jsonPayload: self.settings.privacyMode == .storeNoRawJSON ? nil : json
          )
          self.outputs.append(out)
          VVTRDatabase.shared.insertOutput(out)
          if kind == .summary {
            self.summaryDraft = outputText
            self.isSummaryEditorPresented = true
          }
        }
      })
    }
  }

  private func handleASRErrorIfNeeded(raw: String, sessionId: UUID) -> Bool {
    guard raw.hasPrefix(Self.asrErrorPrefix) else { return false }
    let message = String(raw.dropFirst(Self.asrErrorPrefix.count))
    outputs.append(
      VVTROutput(
        sessionId: sessionId,
        kind: .summary,
        intent: .statement,
        sourceText: "",
        outputText: "转写失败：\(message)",
        jsonPayload: settings.privacyMode == .storeNoRawJSON ? nil : raw
      )
    )
    return true
  }
}
