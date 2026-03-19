import Foundation
import SQLite
import VVTRCore

public final class VVTRDatabase: @unchecked Sendable {
  public static let shared = VVTRDatabase()

  private let db: Connection

  private let sessions = Table("sessions")
  private let segments = Table("segments")
  private let outputs = Table("outputs")

  private let id = Expression<String>("id")
  private let createdAt = Expression<Double>("created_at")
  private let title = Expression<String>("title")

  private let sessionId = Expression<String>("session_id")
  private let segmentId = Expression<String?>("segment_id")
  private let source = Expression<String>("source")
  private let language = Expression<String?>("language")
  private let text = Expression<String>("text")

  private let kind = Expression<String>("kind")
  private let intent = Expression<String>("intent")
  private let outputText = Expression<String>("output_text")
  private let jsonPayload = Expression<String?>("json_payload")
  private let sourceLanguage = Expression<String?>("source_language")
  private let sourceText = Expression<String>("source_text")

  public init(appName: String = "VideoVoiceTranslatorRecorder") {
    let fm = FileManager.default
    let dir = (try? fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true))
      ?? fm.temporaryDirectory
    let appDir = dir.appendingPathComponent(appName, isDirectory: true)
    try? fm.createDirectory(at: appDir, withIntermediateDirectories: true)
    let dbURL = appDir.appendingPathComponent("vvtr.sqlite3")
    db = try! Connection(dbURL.path)
    db.busyTimeout = 5
    db.busyHandler({ tries in tries < 50 })
    try? migrate()
  }

  private func migrate() throws {
    try db.run(sessions.create(ifNotExists: true) { t in
      t.column(id, primaryKey: true)
      t.column(createdAt)
      t.column(title)
    })

    try db.run(segments.create(ifNotExists: true) { t in
      t.column(id, primaryKey: true)
      t.column(sessionId)
      t.column(createdAt)
      t.column(source)
      t.column(language)
      t.column(text)
      t.column(Expression<Double?>("start_time"))
      t.column(Expression<Double?>("end_time"))
      t.foreignKey(sessionId, references: sessions, id)
    })

    try db.run(outputs.create(ifNotExists: true) { t in
      t.column(id, primaryKey: true)
      t.column(sessionId)
      t.column(segmentId)
      t.column(createdAt)
      t.column(kind)
      t.column(sourceLanguage)
      t.column(intent)
      t.column(sourceText)
      t.column(outputText)
      t.column(jsonPayload)
      t.foreignKey(sessionId, references: sessions, id)
    })

    try db.run(outputs.createIndex(sessionId, ifNotExists: true))
    try db.run(outputs.createIndex(createdAt, ifNotExists: true))
  }

  public func upsertSession(_ s: VVTRSession) {
    let row = sessions.filter(id == s.id.uuidString)
    do {
      if try db.scalar(row.count) == 0 {
        try db.run(sessions.insert(
          id <- s.id.uuidString,
          createdAt <- s.createdAt.timeIntervalSince1970,
          title <- s.title
        ))
      } else {
        try db.run(row.update(
          title <- s.title
        ))
      }
    } catch {
      // ignore for now
    }
  }

  public func insertSegment(_ seg: VVTRTranscriptSegment) {
    do {
      try db.run(segments.insert(
        id <- seg.id.uuidString,
        sessionId <- seg.sessionId.uuidString,
        createdAt <- seg.createdAt.timeIntervalSince1970,
        source <- seg.source.rawValue,
        language <- seg.language,
        text <- seg.text
      ))
    } catch {
      // ignore
    }
  }

  public func insertOutput(_ out: VVTROutput) {
    do {
      try db.run(outputs.insert(
        id <- out.id.uuidString,
        sessionId <- out.sessionId.uuidString,
        segmentId <- out.segmentId?.uuidString,
        createdAt <- out.createdAt.timeIntervalSince1970,
        kind <- out.kind.rawValue,
        sourceLanguage <- out.sourceLanguage,
        intent <- out.intent.rawValue,
        sourceText <- out.sourceText,
        outputText <- out.outputText,
        jsonPayload <- out.jsonPayload
      ))
    } catch {
      // ignore
    }
  }

  public func searchOutputs(keyword: String, limit: Int = 200) -> [VVTROutput] {
    let k = keyword.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !k.isEmpty else { return listOutputs(limit: limit) }
    do {
      let q = outputs
        .filter(outputText.like("%\(k)%") || sourceText.like("%\(k)%"))
        .order(createdAt.desc)
        .limit(limit)
      return try db.prepare(q).compactMap { row in
        decodeOutput(row)
      }
    } catch {
      return []
    }
  }

  public func listOutputs(limit: Int = 200) -> [VVTROutput] {
    do {
      let q = outputs.order(createdAt.desc).limit(limit)
      return try db.prepare(q).compactMap { row in decodeOutput(row) }
    } catch {
      return []
    }
  }

  private func decodeOutput(_ row: Row) -> VVTROutput? {
    guard let sid = UUID(uuidString: row[sessionId]) else { return nil }
    let outId = UUID(uuidString: row[id]) ?? UUID()
    let segId = row[segmentId].flatMap { UUID(uuidString: $0) }
    let created = Date(timeIntervalSince1970: row[createdAt])
    let k = VVTROutputKind(rawValue: row[kind]) ?? .summary
    let it = VVTRIntent(rawValue: row[intent]) ?? .statement
    return VVTROutput(
      id: outId,
      sessionId: sid,
      segmentId: segId,
      createdAt: created,
      kind: k,
      sourceLanguage: row[sourceLanguage],
      intent: it,
      sourceText: row[sourceText],
      outputText: row[outputText],
      jsonPayload: row[jsonPayload]
    )
  }
}

