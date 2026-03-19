import Foundation

public struct VVTRGeminiConfig: Sendable {
  public var apiKey: String
  public var model: String
  public var baseURL: URL

  /// Default baseURL is Google AI for Developers Gemini API.
  public init(
    apiKey: String,
    model: String = "gemini-2.0-flash",
    baseURL: URL = URL(string: "https://generativelanguage.googleapis.com/v1beta")!
  ) {
    self.apiKey = apiKey
    self.model = model
    self.baseURL = baseURL
  }
}

public final class VVTRGeminiClient: @unchecked Sendable {
  private let config: VVTRGeminiConfig
  private let urlSession: URLSession

  public init(config: VVTRGeminiConfig, urlSession: URLSession = .shared) {
    self.config = config
    self.urlSession = urlSession
  }

  public func generateJSON(prompt: String, inlineAudioWavBase64: String? = nil) async throws -> String {
    guard !config.apiKey.isEmpty else { throw VVTRCloudError.missingAPIKey }

    // POST {baseURL}/models/{model}:generateContent?key=...
    let url = config.baseURL
      .appendingPathComponent("models")
      .appendingPathComponent("\(config.model):generateContent")
    var comps = URLComponents(url: url, resolvingAgainstBaseURL: false)!
    comps.queryItems = [URLQueryItem(name: "key", value: config.apiKey)]
    var req = URLRequest(url: comps.url!)
    req.httpMethod = "POST"
    req.setValue("application/json", forHTTPHeaderField: "Content-Type")

    var parts: [[String: Any]] = [
      ["text": prompt],
    ]

    if let inlineAudioWavBase64 {
      parts.append([
        "inlineData": [
          "mimeType": "audio/wav",
          "data": inlineAudioWavBase64,
        ],
      ])
    }

    let payload: [String: Any] = [
      "contents": [
        [
          "role": "user",
          "parts": parts,
        ],
      ],
      "generationConfig": [
        "temperature": 0.2,
        "responseMimeType": "application/json",
      ],
    ]
    req.httpBody = try JSONSerialization.data(withJSONObject: payload, options: [])

    let (data, resp) = try await urlSession.data(for: req)
    guard let http = resp as? HTTPURLResponse else { throw VVTRCloudError.other("无效响应") }
    guard (200..<300).contains(http.statusCode) else {
      throw VVTRCloudError.http(http.statusCode, String(data: data, encoding: .utf8) ?? "")
    }

    do {
      let decoded = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
      // Extract text from first candidate
      let text = decoded.candidates?.first?.content?.parts?.compactMap { $0.text }.joined() ?? ""
      return text.isEmpty ? (String(data: data, encoding: .utf8) ?? "{}") : text
    } catch {
      throw VVTRCloudError.decoding(error.localizedDescription)
    }
  }
}

private struct GeminiGenerateContentResponse: Decodable {
  struct Candidate: Decodable {
    struct Content: Decodable {
      struct Part: Decodable {
        var text: String?
      }
      var parts: [Part]?
    }
    var content: Content?
  }
  var candidates: [Candidate]?
}

