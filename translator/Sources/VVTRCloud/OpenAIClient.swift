import Foundation

public struct VVTROpenAIConfig: Sendable {
  public var apiKey: String
  public var model: String
  public var baseURL: URL

  public init(apiKey: String, model: String, baseURL: URL = URL(string: "https://api.openai.com/v1")!) {
    self.apiKey = apiKey
    self.model = model
    self.baseURL = baseURL
  }
}

public enum VVTRCloudError: Error, LocalizedError, Sendable {
  case missingAPIKey
  case http(Int, String)
  case decoding(String)
  case other(String)

  public var errorDescription: String? {
    switch self {
    case .missingAPIKey: return "缺少 API Key"
    case let .http(code, msg): return "HTTP \(code)：\(msg)"
    case let .decoding(msg): return "解析失败：\(msg)"
    case let .other(msg): return msg
    }
  }
}

public final class VVTROpenAIClient: @unchecked Sendable {
  private let config: VVTROpenAIConfig
  private let urlSession: URLSession

  public init(config: VVTROpenAIConfig, urlSession: URLSession = .shared) {
    self.config = config
    self.urlSession = urlSession
  }

  public func transcribeWav(data: Data, fileName: String = "audio.wav") async throws -> VVTRTranscription {
    guard !config.apiKey.isEmpty else { throw VVTRCloudError.missingAPIKey }

    let url = config.baseURL.appendingPathComponent("audio/transcriptions")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")

    let boundary = "vvtr-\(UUID().uuidString)"
    req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

    var body = Data()
    func addField(_ name: String, _ value: String) {
      body.appendString("--\(boundary)\r\n")
      body.appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
      body.appendString("\(value)\r\n")
    }
    func addFile(_ name: String, _ filename: String, _ mime: String, _ data: Data) {
      body.appendString("--\(boundary)\r\n")
      body.appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
      body.appendString("Content-Type: \(mime)\r\n\r\n")
      body.append(data)
      body.appendString("\r\n")
    }

    // whisper-1 is still supported on most OpenAI-compatible endpoints for transcription.
    addField("model", "whisper-1")
    addField("response_format", "verbose_json")
    addFile("file", fileName, "audio/wav", data)
    body.appendString("--\(boundary)--\r\n")
    req.httpBody = body

    let (respData, resp) = try await urlSession.data(for: req)
    let http = resp as? HTTPURLResponse
    guard let http else { throw VVTRCloudError.other("无效响应") }
    guard (200..<300).contains(http.statusCode) else {
      throw VVTRCloudError.http(http.statusCode, String(data: respData, encoding: .utf8) ?? "")
    }

    do {
      let decoded = try JSONDecoder().decode(OpenAITranscriptionResponse.self, from: respData)
      let lang = decoded.language
      let text = decoded.text ?? decoded.fullText ?? ""
      return VVTRTranscription(language: lang, text: text, rawJSON: String(data: respData, encoding: .utf8))
    } catch {
      throw VVTRCloudError.decoding(error.localizedDescription)
    }
  }

  public func chatJSON(system: String, user: String) async throws -> String {
    guard !config.apiKey.isEmpty else { throw VVTRCloudError.missingAPIKey }

    let url = config.baseURL.appendingPathComponent("chat/completions")
    var req = URLRequest(url: url)
    req.httpMethod = "POST"
    req.setValue("Bearer \(config.apiKey)", forHTTPHeaderField: "Authorization")
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    let payload: [String: Any] = [
      "model": config.model,
      "temperature": 0.2,
      "response_format": ["type": "json_object"],
      "messages": [
        ["role": "system", "content": system],
        ["role": "user", "content": user],
      ],
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

    let (respData, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw VVTRCloudError.other("无效响应") }
    guard (200..<300).contains(http.statusCode) else {
      throw VVTRCloudError.http(http.statusCode, String(data: respData, encoding: .utf8) ?? "")
    }

    do {
      let decoded = try JSONDecoder().decode(OpenAIChatResponse.self, from: respData)
      return decoded.choices.first?.message.content ?? "{}"
    } catch {
      throw VVTRCloudError.decoding(error.localizedDescription)
    }
  }
}

public struct VVTRTranscription: Sendable, Hashable {
  public var language: String?
  public var text: String
  public var rawJSON: String?

  public init(language: String?, text: String, rawJSON: String?) {
    self.language = language
    self.text = text
    self.rawJSON = rawJSON
  }
}

private struct OpenAITranscriptionResponse: Decodable {
  var language: String?
  var text: String?

  // some compatible gateways may use a different field name
  var fullText: String?

  private enum CodingKeys: String, CodingKey {
    case language
    case text
    case fullText = "full_text"
  }
}

private struct OpenAIChatResponse: Decodable {
  struct Choice: Decodable {
    struct Message: Decodable { var content: String }
    var message: Message
  }
  var choices: [Choice]
}

private extension Data {
  mutating func appendString(_ s: String) {
    if let d = s.data(using: .utf8) { append(d) }
  }
}

