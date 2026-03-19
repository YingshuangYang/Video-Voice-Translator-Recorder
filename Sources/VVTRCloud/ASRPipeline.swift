import Foundation
import VVTRCapture

public actor VVTRASRPipeline {
  public typealias OnTranscript = @Sendable (_ language: String?, _ text: String, _ rawJSON: String?) -> Void

  private let client: VVTROpenAIClient
  private let onTranscript: OnTranscript

  public init(client: VVTROpenAIClient, onTranscript: @escaping OnTranscript) {
    self.client = client
    self.onTranscript = onTranscript
  }

  public func process(chunk: VVTRChunk) async {
    do {
      let wav = VVTRWavEncoder.encodePCM16LE(
        pcmData: chunk.pcmData,
        sampleRate: Int(chunk.sampleRate),
        channels: chunk.channels
      )
      let result = try await client.transcribeWav(data: wav)
      onTranscript(result.language, result.text, result.rawJSON)
    } catch {
      onTranscript(nil, "", "ASR_ERROR: \(error.localizedDescription)")
    }
  }
}

