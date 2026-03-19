import Foundation
import VVTRCore

public actor VVTRLLMPipeline {
  public typealias OnResult = @Sendable (_ kind: VVTROutputKind, _ intent: VVTRIntent, _ outputText: String, _ json: String) -> Void

  private let client: VVTROpenAIClient
  private let onResult: OnResult

  public init(client: VVTROpenAIClient, onResult: @escaping OnResult) {
    self.client = client
    self.onResult = onResult
  }

  public func handle(text: String, isChinese: Bool, intent: VVTRIntent) async {
    do {
      if intent == .question {
        let system = """
你是一个严谨的双语助理。用户给你的是一段语音转写文本，其中可能包含上下文噪声。请抽取明确的问题，先给出中文回答，再给出对应的英文翻译。
输出必须是 JSON 对象：{ "type":"answer", "question":"...", "answer":"...", "english_answer":"...", "confidence":"low|med|high" }
"""
        let user = "转写文本：\n\(text)"
        let json = try await client.chatJSON(system: system, user: user)
        let (q, a, en, conf) = parseAnswer(json: json)
        onResult(.answer, .question, "问题：\(q)\n中文回答：\(a)\nEnglish: \(en)\n置信度：\(conf)", json)
        return
      }

      guard !isChinese else { return }

      let system = """
你是一个翻译器。请把用户给出的文本翻译成中文，尽量忠实并保留专有名词。
输出必须是 JSON 对象：{ "type":"translation", "source_lang":"auto", "target_lang":"zh", "source":"...", "translation":"..." }
"""
      let user = "文本：\n\(text)"
      let json = try await client.chatJSON(system: system, user: user)
      let translation = parseTranslation(json: json)
      onResult(.translation, .statement, translation, json)
    } catch {
      let kind: VVTROutputKind = intent == .question ? .answer : .translation
      onResult(kind, intent, "LLM 调用失败：\(error.localizedDescription)", "{\"error\":\"\(error.localizedDescription)\"}")
    }
  }

  public func summarizeSession(transcript: String) async {
    let content = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !content.isEmpty else { return }

    do {
      let system = """
你是一个中文会议总结器。请基于整场会议的转写内容输出中文总结。
输出必须是 JSON 对象：{ "type":"summary", "lang":"zh", "text":"...", "bullets":[...], "key_points":[...] }
"""
      let user = "整场会议转写：\n\(content)"
      let json = try await client.chatJSON(system: system, user: user)
      let summary = parseSummary(json: json)
      onResult(.summary, .statement, summary, json)
    } catch {
      onResult(.summary, .statement, "会议总结失败：\(error.localizedDescription)", "{\"error\":\"\(error.localizedDescription)\"}")
    }
  }

  private func parseSummary(json: String) -> String {
    guard let obj = decodeJSONObject(json) else { return json }
    let text = (obj["text"] as? String) ?? ""
    let bullets = (obj["bullets"] as? [String]) ?? []
    let keyPoints = (obj["key_points"] as? [String]) ?? []
    var out = ""
    if !text.isEmpty { out += "摘要：\(text)\n" }
    if !bullets.isEmpty {
      out += "要点：\n" + bullets.map { "- \($0)" }.joined(separator: "\n") + "\n"
    }
    if !keyPoints.isEmpty {
      out += "关键点：\n" + keyPoints.map { "- \($0)" }.joined(separator: "\n")
    }
    return out.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  private func parseTranslation(json: String) -> String {
    guard let obj = decodeJSONObject(json) else { return json }
    return (obj["translation"] as? String) ?? json
  }

  private func parseAnswer(json: String) -> (String, String, String, String) {
    guard let obj = decodeJSONObject(json) else { return ("", json, json, "low") }
    let q = (obj["question"] as? String) ?? ""
    let a = (obj["answer"] as? String) ?? ""
    let en = (obj["english_answer"] as? String) ?? a
    let c = (obj["confidence"] as? String) ?? "low"
    return (q, a, en, c)
  }

  private func decodeJSONObject(_ json: String) -> [String: Any]? {
    guard let data = json.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}

extension VVTRLLMPipeline: VVTRLLMHandling {}

