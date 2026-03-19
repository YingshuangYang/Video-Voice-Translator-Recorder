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
  @Published var isCapturing: Bool = false
  @Published var lastSystemAudioAt: Date?
  @Published var lastMicAudioAt: Date?

  private let settingsStore: VVTRSettingsStore
  private var capture: VVTRAudioCaptureManager?
  private var systemChunker: VVTRChunker?
  private var micChunker: VVTRChunker?
  private var asr: VVTRASRPipeline?
  private var llm: VVTRLLMPipeline?

  init() {
    self.settingsStore = (try? VVTRSettingsStore()) ?? {
      // fallback: put settings in temp dir (should never happen)
      try! VVTRSettingsStore(appName: "VVTR-fallback")
    }()

    Task { [weak self] in
      guard let self else { return }
      let loaded = await settingsStore.load()
      self.settings = loaded
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
    VVTRDatabase.shared.upsertSession(session)
  }

  func startCapture() {
    guard capture == nil else { return }
    if currentSession == nil { startNewSession() }
    isCapturing = true

    if #available(macOS 13.0, *) {
      let sessionId = currentSession?.id ?? UUID()
      let chunkConfig = VVTRChunker.Config(chunkSeconds: settings.chunkSeconds, overlapSeconds: settings.overlapSeconds)
      let appendInfo: @Sendable (String) -> Void = { [weak self] msg in
        Task { @MainActor in
          self?.outputs.append(
            VVTROutput(
              sessionId: sessionId,
              kind: .summary,
              intent: .statement,
              sourceText: "",
              outputText: msg
            )
          )
        }
      }

      if !settings.openAIAPIKey.isEmpty {
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
          }
        })

        let llmPipeline = llm
        asr = VVTRASRPipeline(client: client, onTranscript: { [weak self] lang, text, raw in
          guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
          Task { @MainActor in
            guard let self else { return }
            let isZh = VVTRTextHeuristics.looksLikeChinese(text) || (lang?.lowercased().hasPrefix("zh") ?? false)
            let isQ = VVTRTextHeuristics.looksLikeQuestion(text)
            let intent: VVTRIntent = isQ ? .question : .statement
            let kind: VVTROutputKind = isQ ? .answer : (isZh ? .summary : .translation)

            let seg = VVTRTranscriptSegment(
              sessionId: sessionId,
              source: .mixed,
              language: lang,
              text: self.settings.privacyMode == .storeNoAudioText ? "" : text
            )
            self.segments.append(seg)
            VVTRDatabase.shared.insertSegment(seg)
            let out = VVTROutput(
              sessionId: sessionId,
              segmentId: seg.id,
              kind: kind,
              sourceLanguage: lang,
              intent: intent,
              sourceText: self.settings.privacyMode == .storeNoAudioText ? "" : text,
              outputText: "已转写：\(text)",
              jsonPayload: (self.settings.privacyMode == .storeNoRawJSON ? nil : raw)
            )
            self.outputs.append(out)
            VVTRDatabase.shared.insertOutput(out)

            // Kick off LLM work
            Task { [llmPipeline] in
              if let llmPipeline {
                await llmPipeline.handle(text: text, isChinese: isZh, intent: intent)
              }
            }
          }
        })
      } else {
        asr = nil
        llm = nil
      }

      let asrPipeline = asr

      let sysChunker = VVTRChunker(config: chunkConfig, onChunk: { chunk in
        let msg = "已切片（系统音频）：\(chunk.pcmData.count) bytes @ \(Int(chunk.sampleRate))Hz ch\(chunk.channels)"
        appendInfo(msg)
        Task { [asrPipeline] in
          if let asrPipeline { await asrPipeline.process(chunk: chunk) }
        }
      })
      let micChunker = VVTRChunker(config: chunkConfig, onChunk: { chunk in
        let msg = "已切片（麦克风）：\(chunk.pcmData.count) bytes @ \(Int(chunk.sampleRate))Hz ch\(chunk.channels)"
        appendInfo(msg)
        Task { [asrPipeline] in
          if let asrPipeline { await asrPipeline.process(chunk: chunk) }
        }
      })

      systemChunker = sysChunker
      self.micChunker = micChunker

      Task {
        let micGranted = await VVTRPermissions.requestMicrophoneAccess()
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
                outputText: "未获得麦克风权限：请在系统设置中允许后重试。"
              )
            )
          }
          return
        }
        // Start capture; ingest buffers into chunkers.
        let mgr = VVTRAudioCaptureManager(callbacks: .init(
          onSystemPCMBuffer: { [weak self] buf, at in
            Task { @MainActor in self?.lastSystemAudioAt = at }
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
    capture?.stop()
    capture = nil
    isCapturing = false
    systemChunker = nil
    micChunker = nil
    asr = nil
    llm = nil
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

  private func defaultTitle() -> String {
    let df = DateFormatter()
    df.dateFormat = "yyyy-MM-dd HH:mm"
    return "会话 \(df.string(from: Date()))"
  }
}

