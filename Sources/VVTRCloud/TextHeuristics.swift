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

