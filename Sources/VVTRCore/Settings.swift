import Foundation

public struct VVTRSettings: Codable, Sendable, Hashable {
  public var openAIAPIKey: String
  public var openAIModel: String
  public var openAIBaseURL: String
  public var chunkSeconds: Double
  public var overlapSeconds: Double
  public var realtimeMode: VVTRRealtimeMode
  public var outputFormat: VVTROutputFormat
  public var privacyMode: VVTRPrivacyMode

  public init(
    openAIAPIKey: String = "",
    openAIModel: String = "gpt-4o-mini",
    openAIBaseURL: String = "https://api.openai.com/v1",
    chunkSeconds: Double = 10,
    overlapSeconds: Double = 1,
    realtimeMode: VVTRRealtimeMode = .realtime,
    outputFormat: VVTROutputFormat = .json,
    privacyMode: VVTRPrivacyMode = .storeAll
  ) {
    self.openAIAPIKey = openAIAPIKey
    self.openAIModel = openAIModel
    self.openAIBaseURL = openAIBaseURL
    self.chunkSeconds = chunkSeconds
    self.overlapSeconds = overlapSeconds
    self.realtimeMode = realtimeMode
    self.outputFormat = outputFormat
    self.privacyMode = privacyMode
  }
}

public enum VVTRRealtimeMode: String, Codable, Sendable {
  case realtime
  case summarizeOnSilence
}

public enum VVTROutputFormat: String, Codable, Sendable {
  case json
  case plainText
}

public enum VVTRPrivacyMode: String, Codable, Sendable {
  case storeAll
  case storeNoAudioText
  case storeNoRawJSON
}

public actor VVTRSettingsStore {
  private let url: URL

  public init(appName: String = "VideoVoiceTranslatorRecorder") throws {
    let fm = FileManager.default
    let dir = try fm.url(
      for: .applicationSupportDirectory,
      in: .userDomainMask,
      appropriateFor: nil,
      create: true
    ).appendingPathComponent(appName, isDirectory: true)
    try fm.createDirectory(at: dir, withIntermediateDirectories: true)
    self.url = dir.appendingPathComponent("settings.json", isDirectory: false)
  }

  public func load() async -> VVTRSettings {
    do {
      let data = try Data(contentsOf: url)
      return try JSONDecoder().decode(VVTRSettings.self, from: data)
    } catch {
      return VVTRSettings()
    }
  }

  public func save(_ settings: VVTRSettings) async throws {
    let data = try JSONEncoder().encode(settings)
    try data.write(to: url, options: [.atomic])
  }
}

