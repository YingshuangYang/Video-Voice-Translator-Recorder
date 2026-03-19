import Foundation
import VVTRCapture

public actor VVTRASRPipeline {
  public typealias OnTranscript = @Sendable (_ language: String?, _ text: String, _ rawJSON: String?) -> Void

  public enum Provider: Sendable {
    case openai(VVTROpenAIClient)
    case gemini(VVTRGeminiClient)
  }

  private let provider: Provider
  private let onTranscript: OnTranscript

  public init(provider: Provider, onTranscript: @escaping OnTranscript) {
    self.provider = provider
    self.onTranscript = onTranscript
  }

  private func shouldProcess(chunk: VVTRChunk) -> Bool {
    let metrics = VVTRAudioLevelMetrics.measure(pcmData: chunk.pcmData)
    return metrics.rms >= 0.008 || metrics.peak >= 0.03
  }

  public func process(chunk: VVTRChunk) async {
    guard shouldProcess(chunk: chunk) else { return }

    do {
      let wav = VVTRWavEncoder.encodePCM16LE(
        pcmData: chunk.pcmData,
        sampleRate: Int(chunk.sampleRate),
        channels: chunk.channels
      )
      switch provider {
      case let .openai(client):
        let result = try await client.transcribeWav(data: wav)
        onTranscript(result.language, result.text, result.rawJSON)
      case let .gemini(client):
        let b64 = wav.base64EncodedString()
        let prompt = """
请对提供的音频做语音转写，并检测语种。
输出必须是 JSON：{ "language":"zh|en|ja|ko|fr|de|auto", "text":"..." }
"""
        let json = try await client.generateJSON(prompt: prompt, inlineAudioWavBase64: b64)
        let (lang, text) = VVTRGeminiParsing.parseTranscription(json: json)
        onTranscript(lang, text, json)
      }
    } catch {
      onTranscript(nil, "", "ASR_ERROR: \(error.localizedDescription)")
    }
  }
}

private enum VVTRAudioLevelMetrics {
  static func measure(pcmData: Data) -> (rms: Double, peak: Double) {
    guard !pcmData.isEmpty else { return (0, 0) }

    let samples = pcmData.count / MemoryLayout<Int16>.size
    guard samples > 0 else { return (0, 0) }

    return pcmData.withUnsafeBytes { rawBuffer in
      let int16Buffer = rawBuffer.bindMemory(to: Int16.self)
      var sumSquares = 0.0
      var peak = 0.0

      for sample in int16Buffer {
        let normalized = Double(sample) / Double(Int16.max)
        let magnitude = abs(normalized)
        sumSquares += normalized * normalized
        if magnitude > peak {
          peak = magnitude
        }
      }

      let rms = sqrt(sumSquares / Double(samples))
      return (rms, peak)
    }
  }
}

enum VVTRGeminiParsing {
  static func parseTranscription(json: String) -> (String?, String) {
    let normalized = extractJSONObject(from: json)
    guard let data = normalized.data(using: .utf8),
          let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
      return (nil, json)
    }
    let lang = obj["language"] as? String
    let text = (obj["text"] as? String) ?? ""
    return (lang, text)
  }

  private static func extractJSONObject(from text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.hasPrefix("```") else { return trimmed }

    var content = trimmed
    if let firstNewline = content.firstIndex(of: "\n") {
      content = String(content[content.index(after: firstNewline)...])
    }
    if let closingFence = content.range(of: "\n```", options: .backwards) {
      content = String(content[..<closingFence.lowerBound])
    }
    return content.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

