import Foundation

public enum VVTRAudioSource: String, Codable, Sendable {
  case system
  case microphone
  case mixed
}

public struct VVTRTranscriptSegment: Codable, Sendable, Identifiable, Hashable {
  public var id: UUID
  public var sessionId: UUID
  public var createdAt: Date
  public var startTime: TimeInterval?
  public var endTime: TimeInterval?
  public var source: VVTRAudioSource
  public var language: String?
  public var text: String

  public init(
    id: UUID = UUID(),
    sessionId: UUID,
    createdAt: Date = Date(),
    startTime: TimeInterval? = nil,
    endTime: TimeInterval? = nil,
    source: VVTRAudioSource,
    language: String? = nil,
    text: String
  ) {
    self.id = id
    self.sessionId = sessionId
    self.createdAt = createdAt
    self.startTime = startTime
    self.endTime = endTime
    self.source = source
    self.language = language
    self.text = text
  }
}

public enum VVTRIntent: String, Codable, Sendable {
  case statement
  case question
}

public enum VVTROutputKind: String, Codable, Sendable {
  case summary
  case translation
  case answer
}

public struct VVTROutput: Codable, Sendable, Identifiable, Hashable {
  public var id: UUID
  public var sessionId: UUID
  public var segmentId: UUID?
  public var createdAt: Date
  public var kind: VVTROutputKind
  public var sourceLanguage: String?
  public var intent: VVTRIntent
  public var sourceText: String
  public var outputText: String
  public var jsonPayload: String?

  public init(
    id: UUID = UUID(),
    sessionId: UUID,
    segmentId: UUID? = nil,
    createdAt: Date = Date(),
    kind: VVTROutputKind,
    sourceLanguage: String? = nil,
    intent: VVTRIntent,
    sourceText: String,
    outputText: String,
    jsonPayload: String? = nil
  ) {
    self.id = id
    self.sessionId = sessionId
    self.segmentId = segmentId
    self.createdAt = createdAt
    self.kind = kind
    self.sourceLanguage = sourceLanguage
    self.intent = intent
    self.sourceText = sourceText
    self.outputText = outputText
    self.jsonPayload = jsonPayload
  }
}

public struct VVTRSession: Codable, Sendable, Identifiable, Hashable {
  public var id: UUID
  public var createdAt: Date
  public var title: String

  public init(id: UUID = UUID(), createdAt: Date = Date(), title: String) {
    self.id = id
    self.createdAt = createdAt
    self.title = title
  }
}

