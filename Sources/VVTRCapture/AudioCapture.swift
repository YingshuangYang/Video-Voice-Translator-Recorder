import AVFoundation
import CoreMedia
import Foundation

@available(macOS 13.0, *)
public final class VVTRAudioCaptureManager: NSObject, @unchecked Sendable {
  public struct Callbacks: Sendable {
    public var onSystemPCMBuffer: @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void
    public var onMicPCMBuffer: @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void
    public var onError: @Sendable (_ error: Error) -> Void

    public init(
      onSystemPCMBuffer: @escaping @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void,
      onMicPCMBuffer: @escaping @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void,
      onError: @escaping @Sendable (_ error: Error) -> Void
    ) {
      self.onSystemPCMBuffer = onSystemPCMBuffer
      self.onMicPCMBuffer = onMicPCMBuffer
      self.onError = onError
    }
  }

  private let callbacks: Callbacks

  // Mic
  private let audioEngine = AVAudioEngine()
  private var micFormat: AVAudioFormat?

  // System audio (ScreenCaptureKit)
  private var systemCapture: VVTRSystemAudioCapture?

  public init(callbacks: Callbacks) {
    self.callbacks = callbacks
  }

  public func start(systemAudio: Bool = true, microphone: Bool = true) async {
    do {
      if systemAudio {
        let sys = try await VVTRSystemAudioCapture { [callbacks] buffer, at in
          callbacks.onSystemPCMBuffer(buffer, at)
        }
        self.systemCapture = sys
        try await sys.start()
      }

      if microphone {
        try startMicrophone()
      }
    } catch {
      callbacks.onError(error)
    }
  }

  public func stop() {
    stopMicrophone()
    Task { [systemCapture] in
      await systemCapture?.stop()
    }
    systemCapture = nil
  }

  private func startMicrophone() throws {
    let input = audioEngine.inputNode
    let format = input.inputFormat(forBus: 0)
    micFormat = format

    input.removeTap(onBus: 0)
    input.installTap(onBus: 0, bufferSize: 2048, format: format) { [callbacks] buffer, _ in
      callbacks.onMicPCMBuffer(buffer, Date())
    }

    audioEngine.prepare()
    try audioEngine.start()
  }

  private func stopMicrophone() {
    audioEngine.inputNode.removeTap(onBus: 0)
    audioEngine.stop()
  }
}

public enum VVTRPermissions {
  public static func requestMicrophoneAccess() async -> Bool {
    await withCheckedContinuation { cont in
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        cont.resume(returning: granted)
      }
    }
  }
}

