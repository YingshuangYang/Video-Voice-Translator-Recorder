import Foundation

public enum VVTRWavEncoder {
  // Encodes interleaved signed 16-bit PCM into a WAV container.
  public static func encodePCM16LE(pcmData: Data, sampleRate: Int, channels: Int) -> Data {
    let bitsPerSample = 16
    let byteRate = sampleRate * channels * bitsPerSample / 8
    let blockAlign = channels * bitsPerSample / 8

    var data = Data()
    data.appendASCII("RIFF")
    data.appendUInt32LE(UInt32(36 + pcmData.count))
    data.appendASCII("WAVE")

    // fmt chunk
    data.appendASCII("fmt ")
    data.appendUInt32LE(16) // PCM fmt chunk size
    data.appendUInt16LE(1)  // audio format = PCM
    data.appendUInt16LE(UInt16(channels))
    data.appendUInt32LE(UInt32(sampleRate))
    data.appendUInt32LE(UInt32(byteRate))
    data.appendUInt16LE(UInt16(blockAlign))
    data.appendUInt16LE(UInt16(bitsPerSample))

    // data chunk
    data.appendASCII("data")
    data.appendUInt32LE(UInt32(pcmData.count))
    data.append(pcmData)

    return data
  }
}

private extension Data {
  mutating func appendASCII(_ s: String) {
    append(s.data(using: .ascii)!)
  }
  mutating func appendUInt16LE(_ v: UInt16) {
    var x = v.littleEndian
    Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
  }
  mutating func appendUInt32LE(_ v: UInt32) {
    var x = v.littleEndian
    Swift.withUnsafeBytes(of: &x) { append(contentsOf: $0) }
  }
}

