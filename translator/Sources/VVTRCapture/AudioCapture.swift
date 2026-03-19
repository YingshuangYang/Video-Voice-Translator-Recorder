import AVFoundation
import CoreMedia
import Foundation

@available(macOS 13.0, *)
public final class VVTRAudioCaptureManager: NSObject, @unchecked Sendable {
  public struct Callbacks: Sendable {
    public var onSystemPCMBuffer: @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void
    public var onMicPCMBuffer: @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void
    public var onWarning: @Sendable (_ error: Error) -> Void
    public var onError: @Sendable (_ error: Error) -> Void

    public init(
      onSystemPCMBuffer: @escaping @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void,
      onMicPCMBuffer: @escaping @Sendable (_ buffer: AVAudioPCMBuffer, _ at: Date) -> Void,
      onWarning: @escaping @Sendable (_ error: Error) -> Void,
      onError: @escaping @Sendable (_ error: Error) -> Void
    ) {
      self.onSystemPCMBuffer = onSystemPCMBuffer
      self.onMicPCMBuffer = onMicPCMBuffer
      self.onWarning = onWarning
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
    var startedAtLeastOneSource = false

    if systemAudio {
      do {
        let sys = try await VVTRSystemAudioCapture { [callbacks] buffer, at in
          callbacks.onSystemPCMBuffer(buffer, at)
        }
        self.systemCapture = sys
        try await sys.start()
        startedAtLeastOneSource = true
      } catch {
        callbacks.onWarning(error)
      }
    }

    if microphone {
      do {
        try startMicrophone()
        startedAtLeastOneSource = true
      } catch {
        callbacks.onError(error)
        return
      }
    }

    if !startedAtLeastOneSource {
      callbacks.onError(VVTRCaptureError.noAudioSourceAvailable)
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

public enum VVTRMicrophoneAuthorizationState: Sendable {
  case authorized
  case denied
  case restricted
  case notDetermined
}

public enum VVTRPermissions {
  public static func microphoneAuthorizationState() -> VVTRMicrophoneAuthorizationState {
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      return .authorized
    case .denied:
      return .denied
    case .restricted:
      return .restricted
    case .notDetermined:
      return .notDetermined
    @unknown default:
      return .restricted
    }
  }

  public static func requestMicrophoneAccess() async -> Bool {
    await withCheckedContinuation { cont in
      AVCaptureDevice.requestAccess(for: .audio) { granted in
        cont.resume(returning: granted)
      }
    }
  }
}

public enum VVTRCaptureError: Error, LocalizedError {
  case noAudioSourceAvailable

  public var errorDescription: String? {
    switch self {
    case .noAudioSourceAvailable:
      return "没有可用的音频输入源，请检查麦克风和系统音频录制权限。"
    }
  }
}

