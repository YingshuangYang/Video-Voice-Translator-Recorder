import Foundation
import VVTRCore

public protocol VVTRLLMHandling: Sendable {
  func handle(text: String, isChinese: Bool, intent: VVTRIntent) async
  func summarizeSession(transcript: String) async
}

