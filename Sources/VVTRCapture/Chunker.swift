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

  private var buffer: Data = Data()
  private var sampleRate: Double?
  private var channels: Int?
  private var bytesPerFrame: Int?
  private var lastEmitAt: Date?

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
      // format change: flush current buffer
      buffer.removeAll(keepingCapacity: true)
      self.sampleRate = sampleRate
      self.channels = channels
      self.bytesPerFrame = channels * MemoryLayout<Int16>.size
      self.lastEmitAt = nil
    }

    buffer.append(data)
    emitIfNeeded(source: source)
  }

  private func emitIfNeeded(source: String) {
    guard let sampleRate, let channels, let bytesPerFrame else { return }
    let chunkBytes = Int(sampleRate * config.chunkSeconds) * bytesPerFrame
    let overlapBytes = Int(sampleRate * config.overlapSeconds) * bytesPerFrame

    while buffer.count >= chunkBytes, chunkBytes > 0 {
      let chunkData = buffer.prefix(chunkBytes)
      let out = VVTRChunk(source: source, pcmData: Data(chunkData), sampleRate: sampleRate, channels: channels)
      onChunk(out)
      lastEmitAt = Date()

      if overlapBytes > 0 {
        buffer.removeFirst(max(0, chunkBytes - overlapBytes))
      } else {
        buffer.removeFirst(chunkBytes)
      }
    }
  }
}

public enum VVTRPCM {
  public static func interleavedInt16Data(from buffer: AVAudioPCMBuffer) -> (data: Data, sampleRate: Double, channels: Int)? {
    let format = buffer.format
    let channels = Int(format.channelCount)
    let sampleRate = format.sampleRate

    if format.commonFormat == .pcmFormatInt16 {
      guard let src = buffer.int16ChannelData else { return nil }
      // When interleaved, only one pointer is provided.
      let frameCount = Int(buffer.frameLength)
      let bytes = frameCount * channels * MemoryLayout<Int16>.size
      let ptr = UnsafeRawPointer(src[0])
      return (Data(bytes: ptr, count: bytes), sampleRate, channels)
    }

    if format.commonFormat == .pcmFormatFloat32 {
      guard let src = buffer.floatChannelData else { return nil }
      let frameCount = Int(buffer.frameLength)
      let floatCount = frameCount * channels
      let inPtr = UnsafeBufferPointer(start: src[0], count: floatCount)
      var out = Data(count: floatCount * MemoryLayout<Int16>.size)
      out.withUnsafeMutableBytes { raw in
        let outPtr = raw.bindMemory(to: Int16.self).baseAddress!
        for i in 0..<floatCount {
          let x = max(-1.0, min(1.0, inPtr[i]))
          outPtr[i] = Int16((x * Float(Int16.max)).rounded())
        }
      }
      return (out, sampleRate, channels)
    }

    return nil
  }
}

