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
你是一个严谨的中文助理。用户给你的是一段语音转写文本，其中可能包含上下文噪声。请抽取明确的问题并给出中文回答。
输出必须是 JSON 对象：{ "type":"answer", "question":"...", "answer":"...", "confidence":"low|med|high" }
"""
        let user = "转写文本：\n\(text)"
        let json = try await client.chatJSON(system: system, user: user)
        let (q, a, conf) = parseAnswer(json: json)
        onResult(.answer, .question, "问题：\(q)\n回答：\(a)\n置信度：\(conf)", json)
        return
      }

      if isChinese {
        let system = """
你是一个中文内容总结器。请对用户给出的转写文本进行摘要，提炼要点。
输出必须是 JSON 对象：{ "type":"summary", "lang":"zh", "text":"...", "bullets":[...], "key_points":[...] }
"""
        let user = "转写文本：\n\(text)"
        let json = try await client.chatJSON(system: system, user: user)
        let summary = parseSummary(json: json)
        onResult(.summary, .statement, summary, json)
      } else {
        let system = """
你是一个翻译器。请把用户给出的文本翻译成中文，尽量忠实并保留专有名词。
输出必须是 JSON 对象：{ "type":"translation", "source_lang":"auto", "target_lang":"zh", "source":"...", "translation":"..." }
"""
        let user = "文本：\n\(text)"
        let json = try await client.chatJSON(system: system, user: user)
        let translation = parseTranslation(json: json)
        onResult(.translation, .statement, translation, json)
      }
    } catch {
      onResult(.summary, intent, "LLM 调用失败：\(error.localizedDescription)", "{\"error\":\"\(error.localizedDescription)\"}")
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

  private func parseAnswer(json: String) -> (String, String, String) {
    guard let obj = decodeJSONObject(json) else { return ("", json, "low") }
    let q = (obj["question"] as? String) ?? ""
    let a = (obj["answer"] as? String) ?? ""
    let c = (obj["confidence"] as? String) ?? "low"
    return (q, a, c)
  }

  private func decodeJSONObject(_ json: String) -> [String: Any]? {
    guard let data = json.data(using: .utf8) else { return nil }
    return (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
  }
}

