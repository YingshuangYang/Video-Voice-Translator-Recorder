import Foundation

public enum VVTRTextHeuristics {
  public static func looksLikeChinese(_ text: String) -> Bool {
    let scalars = text.unicodeScalars
    guard !scalars.isEmpty else { return false }
    var cjk = 0
    var letters = 0
    for s in scalars {
      if (0x4E00...0x9FFF).contains(Int(s.value)) { cjk += 1; continue }
      if CharacterSet.letters.contains(s) { letters += 1 }
    }
    // If there is meaningful amount of CJK, treat as Chinese.
    return cjk >= max(2, letters / 3)
  }

  public static func looksMostlyLatin(_ text: String) -> Bool {
    let scalars = text.unicodeScalars
    guard !scalars.isEmpty else { return false }
    var latinLetters = 0
    var cjk = 0
    for scalar in scalars {
      if (0x4E00...0x9FFF).contains(Int(scalar.value)) {
        cjk += 1
        continue
      }
      if CharacterSet.letters.contains(scalar), scalar.properties.isAlphabetic {
        let value = Int(scalar.value)
        if (0x41...0x5A).contains(value) || (0x61...0x7A).contains(value) {
          latinLetters += 1
        }
      }
    }
    return latinLetters >= max(4, cjk * 2)
  }

  public static func isLikelyChinese(_ text: String, detectedLanguage: String?) -> Bool {
    if looksLikeChinese(text) { return true }
    guard let detectedLanguage, !detectedLanguage.isEmpty else { return false }
    let normalized = detectedLanguage.lowercased()
    if normalized.hasPrefix("zh") {
      return !looksMostlyLatin(text)
    }
    return false
  }

  public static func looksLikeQuestion(_ text: String) -> Bool {
    let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !t.isEmpty else { return false }
    if t.contains("?") || t.contains("？") { return true }
    let zh = ["吗", "么", "怎么", "如何", "为什么", "为啥", "啥", "多少", "几", "能不能", "是否", "可否", "请问"]
    for k in zh where t.contains(k) { return true }
    let en = ["what", "why", "how", "when", "where", "which", "who", "can you", "could you", "do you", "is it", "are you"]
    let lower = t.lowercased()
    for k in en where lower.contains(k) { return true }
    return false
  }
}
