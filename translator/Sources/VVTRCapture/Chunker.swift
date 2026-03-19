import AVFoundation
import Foundation

public struct VVTRChunk: Sendable {
  public let id: UUID
  public let createdAt: Date
  public let source: String
  public let pcmData: Data
  public let sampleRate: Double
  public let channels: Int

  public init(id: UUID = UUID(), createdAt: Date = Date(), source: String, pcmData: Data, sampleRate: Double, channels: Int) {
    self.id = id
    self.createdAt = createdAt
    self.source = source
    self.pcmData = pcmData
    self.sampleRate = sampleRate
    self.channels = channels
  }
}

public actor VVTRChunker {
  public struct Config: Sendable {
    public var chunkSeconds: Double
    public var overlapSeconds: Double

    public init(chunkSeconds: Double = 10, overlapSeconds: Double = 1) {
      self.chunkSeconds = max(1, chunkSeconds)
      self.overlapSeconds = max(0, min(overlapSeconds, chunkSeconds * 0.5))
    }
  }

  public typealias OnChunk = @Sendable (VVTRChunk) -> Void

  private let config: Config
  private let onChunk: OnChunk

  private var sampleRate: Double?
  private var channels: Int?
  private var bytesPerFrame: Int?

  private var preRollBuffer = Data()
  private var speechBuffer = Data()
  private var trailingSilenceBuffer = Data()
  private var speechDuration: Double = 0
  private var silenceDuration: Double = 0
  private var hasActiveSpeech = false

  private let speechRMS: Double = 0.010
  private let speechPeak: Double = 0.040
  private let endSilenceSeconds: Double = 1.20
  private let minSpeechSeconds: Double = 0.60
  private let preRollSeconds: Double = 0.25

  public init(config: Config, onChunk: @escaping OnChunk) {
    self.config = config
    self.onChunk = onChunk
  }

  public func ingestInterleavedInt16PCM(_ data: Data, sampleRate: Double, channels: Int, source: String) {
    if self.sampleRate == nil {
      self.sampleRate = sampleRate
      self.channels = channels
      self.bytesPerFrame = channels * MemoryLayout<Int16>.size
    }

    if self.sampleRate != sampleRate || self.channels != channels {
      resetState()
      self.sampleRate = sampleRate
      self.channels = channels
      self.bytesPerFrame = channels * MemoryLayout<Int16>.size
    }

    guard let bytesPerFrame else { return }
    let frameCount = data.count / bytesPerFrame
    guard frameCount > 0 else { return }

    let duration = Double(frameCount) / sampleRate
    let level = VVTRAudioLevel.measure(pcmData: data)
    let isSpeechLike = level.rms >= speechRMS || level.peak >= speechPeak

    if isSpeechLike {
      if !hasActiveSpeech {
        hasActiveSpeech = true
        speechBuffer = preRollBuffer
        speechDuration = Double(preRollBuffer.count / bytesPerFrame) / sampleRate
        silenceDuration = 0
        trailingSilenceBuffer.removeAll(keepingCapacity: true)
      }

      speechBuffer.append(data)
      speechDuration += duration
      silenceDuration = 0
      trailingSilenceBuffer.removeAll(keepingCapacity: true)
    } else {
      appendToPreRoll(data, sampleRate: sampleRate, bytesPerFrame: bytesPerFrame)

      guard hasActiveSpeech else { return }
      speechBuffer.append(data)
      trailingSilenceBuffer.append(data)
      silenceDuration += duration
    }

    if shouldEmitChunk() {
      emitChunk(source: source, sampleRate: sampleRate, channels: channels)
    }
  }

  private func shouldEmitChunk() -> Bool {
    guard hasActiveSpeech else { return false }
    if speechDuration >= config.chunkSeconds {
      return true
    }
    return speechDuration >= minSpeechSeconds && silenceDuration >= endSilenceSeconds
  }

  private func emitChunk(source: String, sampleRate: Double, channels: Int) {
    guard let bytesPerFrame else { return }

    var output = speechBuffer
    if silenceDuration >= endSilenceSeconds, !trailingSilenceBuffer.isEmpty, output.count >= trailingSilenceBuffer.count {
      output.removeLast(trailingSilenceBuffer.count)
    }

    let effectiveDuration = Double(output.count / bytesPerFrame) / sampleRate
    guard effectiveDuration >= minSpeechSeconds else {
      resetSpeechState(keepingPreRoll: true)
      return
    }

    let out = VVTRChunk(source: source, pcmData: output, sampleRate: sampleRate, channels: channels)
    onChunk(out)
    resetSpeechState(keepingPreRoll: true)
  }

  private func appendToPreRoll(_ data: Data, sampleRate: Double, bytesPerFrame: Int) {
    preRollBuffer.append(data)
    let maxBytes = Int(sampleRate * preRollSeconds) * bytesPerFrame
    if preRollBuffer.count > maxBytes {
      preRollBuffer.removeFirst(preRollBuffer.count - maxBytes)
    }
  }

  private func resetState() {
    preRollBuffer.removeAll(keepingCapacity: true)
    resetSpeechState(keepingPreRoll: false)
  }

  private func resetSpeechState(keepingPreRoll: Bool) {
    if !keepingPreRoll {
      preRollBuffer.removeAll(keepingCapacity: true)
    }
    speechBuffer.removeAll(keepingCapacity: true)
    trailingSilenceBuffer.removeAll(keepingCapacity: true)
    speechDuration = 0
    silenceDuration = 0
    hasActiveSpeech = false
  }
}

private enum VVTRAudioLevel {
  static func measure(pcmData: Data) -> (rms: Double, peak: Double) {
    guard !pcmData.isEmpty else { return (0, 0) }

    let sampleCount = pcmData.count / MemoryLayout<Int16>.size
    guard sampleCount > 0 else { return (0, 0) }

    return pcmData.withUnsafeBytes { rawBuffer in
      let samples = rawBuffer.bindMemory(to: Int16.self)
      var sumSquares = 0.0
      var peak = 0.0

      for sample in samples {
        let normalized = Double(sample) / Double(Int16.max)
        let magnitude = abs(normalized)
        sumSquares += normalized * normalized
        if magnitude > peak {
          peak = magnitude
        }
      }

      return (sqrt(sumSquares / Double(sampleCount)), peak)
    }
  }
}

public enum VVTRPCM {
  public static func interleavedInt16Data(from buffer: AVAudioPCMBuffer) -> (data: Data, sampleRate: Double, channels: Int)? {
    let format = buffer.format
    let channels = Int(format.channelCount)
    let sampleRate = format.sampleRate
    let frames = Int(buffer.frameLength)
    guard frames > 0, channels > 0 else { return nil }

    if format.commonFormat == .pcmFormatInt16 {
      guard let src = buffer.int16ChannelData else { return nil }
      if format.isInterleaved {
        let bytes = frames * channels * MemoryLayout<Int16>.size
        return (Data(bytes: UnsafeRawPointer(src[0]), count: bytes), sampleRate, channels)
      } else {
        var out = Data(count: frames * channels * MemoryLayout<Int16>.size)
        out.withUnsafeMutableBytes { raw in
          let outPtr = raw.bindMemory(to: Int16.self).baseAddress!
          for f in 0..<frames {
            for ch in 0..<channels {
              outPtr[f * channels + ch] = src[ch][f]
            }
          }
        }
        return (out, sampleRate, channels)
      }
    }

    if format.commonFormat == .pcmFormatFloat32 {
      guard let src = buffer.floatChannelData else { return nil }
      var out = Data(count: frames * channels * MemoryLayout<Int16>.size)
      out.withUnsafeMutableBytes { raw in
        let outPtr = raw.bindMemory(to: Int16.self).baseAddress!
        if format.isInterleaved {
          let floatCount = frames * channels
          let inPtr = UnsafeBufferPointer(start: src[0], count: floatCount)
          for i in 0..<floatCount {
            let x = max(-1.0, min(1.0, inPtr[i]))
            outPtr[i] = Int16((x * Float(Int16.max)).rounded())
          }
        } else {
          for f in 0..<frames {
            for ch in 0..<channels {
              let x = max(-1.0, min(1.0, src[ch][f]))
              outPtr[f * channels + ch] = Int16((x * Float(Int16.max)).rounded())
            }
          }
        }
      }
      return (out, sampleRate, channels)
    }

    return nil
  }
}
