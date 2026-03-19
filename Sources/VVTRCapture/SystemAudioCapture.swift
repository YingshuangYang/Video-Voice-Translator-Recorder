import AVFoundation
import CoreMedia
import Foundation
import ScreenCaptureKit
import Darwin

@available(macOS 13.0, *)
final class VVTRSystemAudioCapture: NSObject {
  typealias OnPCM = @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void

  private let onPCM: OnPCM

  private var stream: SCStream?
  private var output: VVTRSCStreamOutput?

  init(onPCM: @escaping OnPCM) async throws {
    self.onPCM = onPCM
    super.init()
  }

  func start() async throws {
    // Request Screen Recording permission if needed.
    _ = VVTRScreenCaptureAccess.requestIfNeeded()

    let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
    guard let display = content.displays.first else {
      throw NSError(domain: "VVTRCapture", code: 1, userInfo: [NSLocalizedDescriptionKey: "未找到可用显示器用于系统音频捕获。"])
    }

    let filter = SCContentFilter(display: display, excludingWindows: [])
    let config = SCStreamConfiguration()
    config.capturesAudio = true
    config.sampleRate = 48_000
    config.channelCount = 2
    config.excludesCurrentProcessAudio = false

    let out = VVTRSCStreamOutput(onPCM: onPCM)
    self.output = out

    let stream = SCStream(filter: filter, configuration: config, delegate: out)
    self.stream = stream

    try stream.addStreamOutput(out, type: .audio, sampleHandlerQueue: DispatchQueue(label: "vvtr.systemAudio"))
    try await stream.startCapture()
  }

  func stop() async {
    do {
      try await stream?.stopCapture()
    } catch {
      // ignore
    }
    stream = nil
    output = nil
  }
}

@available(macOS 13.0, *)
private final class VVTRSCStreamOutput: NSObject, SCStreamOutput, SCStreamDelegate {
  private let onPCM: VVTRSystemAudioCapture.OnPCM

  init(onPCM: @escaping VVTRSystemAudioCapture.OnPCM) {
    self.onPCM = onPCM
  }

  func stream(_ stream: SCStream, didOutputSampleBuffer sampleBuffer: CMSampleBuffer, of type: SCStreamOutputType) {
    guard type == .audio else { return }
    guard CMSampleBufferDataIsReady(sampleBuffer) else { return }
    guard let pcm = VVTRAudioBufferConverter.toPCM(sampleBuffer: sampleBuffer) else { return }
    onPCM(pcm, Date())
  }
}

private enum VVTRAudioBufferConverter {
  static func toPCM(sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer) else { return nil }
    guard let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)?.pointee else { return nil }

    var blockBuffer: CMBlockBuffer?
    var audioBufferList = AudioBufferList(
      mNumberBuffers: 1,
      mBuffers: AudioBuffer(mNumberChannels: asbd.mChannelsPerFrame, mDataByteSize: 0, mData: nil)
    )

    var dataPointer: UnsafeMutableAudioBufferListPointer?
    let status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
      sampleBuffer,
      bufferListSizeNeededOut: nil,
      bufferListOut: &audioBufferList,
      bufferListSize: MemoryLayout<AudioBufferList>.size,
      blockBufferAllocator: nil,
      blockBufferMemoryAllocator: nil,
      flags: kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment,
      blockBufferOut: &blockBuffer
    )
    guard status == noErr else { return nil }

    dataPointer = UnsafeMutableAudioBufferListPointer(&audioBufferList)
    guard let dataPointer else { return nil }

    let sampleRate = Double(asbd.mSampleRate)
    let channels = AVAudioChannelCount(asbd.mChannelsPerFrame)
    let isFloat = (asbd.mFormatFlags & kAudioFormatFlagIsFloat) != 0

    let commonFormat: AVAudioCommonFormat = isFloat ? .pcmFormatFloat32 : .pcmFormatInt16
    guard let format = AVAudioFormat(commonFormat: commonFormat, sampleRate: sampleRate, channels: channels, interleaved: true) else {
      return nil
    }

    let numSamples = CMSampleBufferGetNumSamples(sampleBuffer)
    guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(numSamples)) else { return nil }
    pcmBuffer.frameLength = AVAudioFrameCount(numSamples)

    // Copy bytes from AudioBufferList into pcmBuffer
    if let dst = pcmBuffer.int16ChannelData, commonFormat == .pcmFormatInt16 {
      // Interleaved: int16ChannelData points to one channel pointer.
      let dstPtr = dst[0]
      let src = dataPointer[0]
      guard let srcData = src.mData else { return nil }
      memcpy(dstPtr, srcData, Int(src.mDataByteSize))
      return pcmBuffer
    }

    if let dst = pcmBuffer.floatChannelData, commonFormat == .pcmFormatFloat32 {
      let dstPtr = dst[0]
      let src = dataPointer[0]
      guard let srcData = src.mData else { return nil }
      memcpy(dstPtr, srcData, Int(src.mDataByteSize))
      return pcmBuffer
    }

    return nil
  }
}

private enum VVTRScreenCaptureAccess {
  static func requestIfNeeded() -> Bool {
    // Prefer simple CoreGraphics import? To keep dependencies low, call via dlsym.
    // If unavailable, just return true and let SCStream fail with a permission error.
    typealias CGAccessFn = @convention(c) () -> Bool

    let preflightPtr = dlsymWrapper("CGPreflightScreenCaptureAccess")
    let requestPtr = dlsymWrapper("CGRequestScreenCaptureAccess")

    if let preflightPtr {
      let fn = unsafeBitCast(preflightPtr, to: CGAccessFn.self)
      if fn() { return true }
    }

    if let requestPtr {
      let fn = unsafeBitCast(requestPtr, to: CGAccessFn.self)
      return fn()
    }

    return true
  }

  private static func dlsymWrapper(_ symbol: String) -> UnsafeMutableRawPointer? {
    let handle = dlopen("/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics", RTLD_LAZY)
    defer { if handle != nil { dlclose(handle) } }
    return dlsym(handle, symbol)
  }
}

