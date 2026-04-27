import Foundation
import os.log

/// Log level. Severity increases left-to-right.
enum EidosLogLevel: String, Sendable, Codable, CaseIterable, Comparable {
    case debug, info, warn, error, metric

    /// Numeric rank for filtering and comparison.
    var rank: Int {
        switch self {
        case .debug: 0
        case .info: 1
        case .warn: 2
        case .error: 3
        case .metric: 4
        }
    }

    static func < (lhs: EidosLogLevel, rhs: EidosLogLevel) -> Bool {
        lhs.rank < rhs.rank
    }
}

/// Broad subsystem a log line belongs to. Lets the Diagnostics UI and
/// any offline analysis filter cleanly.
enum EidosLogCategory: String, Sendable, Codable, CaseIterable {
    case model      // inference, loading, generation
    case chat       // user-facing chat pipeline
    case memory     // memory manager, crystallizer, decay
    case rag        // knowledge base, embeddings, retrieval
    case download   // model download, asset fetching
    case permission // mic, camera, health, notifications
    case ui         // view lifecycle, user interactions
    case intent     // App Intents, shortcuts
    case skill      // skill registry execution
    case persona    // Phase 9: persona router, cross-consult
    case safety     // SafetyGate intercepts
    case benchmark  // benchmark runner
    case crash      // unhandled exceptions, traps
    case app        // lifecycle: launch, background, foreground
}

/// One structured log entry. Serialised as a single JSONL line on disk.
///
/// The `payload` dictionary accepts anything JSON-representable (String,
/// Number, Bool, Array, nested Dict). We enforce this at the call site
/// by accepting `[String: AnyCodableValue]`, defined below.
struct EidosLogEntry: Sendable, Codable {
    /// ISO 8601 timestamp with milliseconds.
    let timestamp: String
    let level: EidosLogLevel
    let category: EidosLogCategory
    /// A short event name: "model.load.start", "chat.send", "rag.miss".
    let event: String
    /// Free-form human-readable summary.
    let message: String?
    /// Structured payload — metrics, error codes, etc.
    let payload: [String: AnyCodableValue]?
    /// If this entry represents a failure, the typed category.
    let failure: FailureCategory?
}

/// A JSON-encodable variant that supports the handful of value types we
/// actually pass to the logger. Keeps us clear of `Any` + `JSONSerialization`.
enum AnyCodableValue: Sendable, Codable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case null
    indirect case array([AnyCodableValue])
    indirect case dict([String: AnyCodableValue])

    init(_ value: Any?) {
        switch value {
        case nil: self = .null
        case let s as String: self = .string(s)
        case let i as Int: self = .int(i)
        case let d as Double: self = .double(d)
        case let b as Bool: self = .bool(b)
        case let a as [Any?]: self = .array(a.map { AnyCodableValue($0) })
        case let m as [String: Any?]:
            self = .dict(m.mapValues { AnyCodableValue($0) })
        default:
            // Last resort: stringify.
            self = .string(String(describing: value ?? "nil"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .string(let s): try container.encode(s)
        case .int(let i): try container.encode(i)
        case .double(let d): try container.encode(d)
        case .bool(let b): try container.encode(b)
        case .array(let a): try container.encode(a)
        case .dict(let d): try container.encode(d)
        }
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let b = try? c.decode(Bool.self) { self = .bool(b); return }
        if let i = try? c.decode(Int.self) { self = .int(i); return }
        if let d = try? c.decode(Double.self) { self = .double(d); return }
        if let s = try? c.decode(String.self) { self = .string(s); return }
        if let a = try? c.decode([AnyCodableValue].self) { self = .array(a); return }
        if let m = try? c.decode([String: AnyCodableValue].self) { self = .dict(m); return }
        self = .null
    }
}

/// Central logger — one instance per app launch.
///
/// Design goals:
///   - Crash-safe: writer runs on a dedicated queue, failures are
///     swallowed silently (never re-entered into the logger).
///   - Never blocks UI: public `log(...)` methods enqueue and return
///     synchronously; flushing is asynchronous.
///   - Append-only JSONL files rotated by UTC date.
///   - Mirrored to `os.Logger` so Console.app sees the stream live.
///   - Zero config: works immediately on `EidosLogger.shared` access.
final class EidosLogger: @unchecked Sendable {

    /// Shared instance. Safe to call from any thread.
    ///
    /// `@unchecked Sendable` is justified because mutable state is
    /// confined to the `writeQueue` and the two atomic-update vars
    /// (`minimumLevel`, `onDiskListener`) are only read under that
    /// queue.
    static let shared = EidosLogger()

    /// Minimum severity written to disk. Debug is never shipped.
    var minimumLevel: EidosLogLevel = {
        #if DEBUG
        return .debug
        #else
        return .info
        #endif
    }()

    /// Optional live hook used by the Diagnostics UI to receive entries
    /// in real time without polling the file.
    var onDiskListener: (@Sendable (EidosLogEntry) -> Void)?

    // MARK: - Private state

    private let writeQueue = DispatchQueue(label: "com.hissamuddin.eidos.logger", qos: .utility)
    private let osLogger = os.Logger(subsystem: "com.hissamuddin.eidos", category: "eidos")
    private let dateFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(secondsFromGMT: 0)
        return f
    }()
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }()

    private init() {}

    // MARK: - Public API

    /// Logs a single event. Returns synchronously; disk I/O is async.
    ///
    /// - Parameters:
    ///   - level: severity
    ///   - category: subsystem
    ///   - event: short dotted-identifier ("model.load.start")
    ///   - message: optional free-text
    ///   - payload: optional structured dict — numbers, strings, nested
    ///   - failure: if logging a failure, its typed category
    func log(
        _ level: EidosLogLevel,
        category: EidosLogCategory,
        event: String,
        message: String? = nil,
        payload: [String: Any?]? = nil,
        failure: FailureCategory? = nil
    ) {
        guard level >= minimumLevel else { return }

        let entry = EidosLogEntry(
            timestamp: dateFormatter.string(from: Date()),
            level: level,
            category: category,
            event: event,
            message: message,
            payload: payload.map { $0.mapValues { AnyCodableValue($0) } },
            failure: failure
        )

        // Mirror to unified log (Console.app).
        let osLog = "[\(category.rawValue)] \(event)\(message.map { " — \($0)" } ?? "")"
        switch level {
        case .debug: osLogger.debug("\(osLog, privacy: .public)")
        case .info: osLogger.info("\(osLog, privacy: .public)")
        case .warn: osLogger.warning("\(osLog, privacy: .public)")
        case .error: osLogger.error("\(osLog, privacy: .public)")
        case .metric: osLogger.notice("\(osLog, privacy: .public)")
        }

        // Fan out to listener (UI) on the write queue so there's a
        // single ordered stream.
        writeQueue.async { [weak self] in
            self?.onDiskListener?(entry)
            self?.persist(entry)
        }
    }

    /// Blocks the calling thread until every pending write on the
    /// internal serial queue has hit disk. Used from crash and signal
    /// handlers right before the process dies — the standard `log(...)`
    /// path is async via `writeQueue.async`, which means a fatal
    /// signal between log call and queue drain would lose the final
    /// breadcrumb.
    func flushSynchronously() {
        writeQueue.sync { /* drain barrier */ }
    }

    /// Convenience: log a metric with a numeric value dict.
    func metric(
        _ category: EidosLogCategory,
        event: String,
        values: [String: Any?]
    ) {
        log(.metric, category: category, event: event, payload: values)
    }

    /// Convenience: log a caught error.
    func error(
        _ category: EidosLogCategory,
        event: String,
        error: Error,
        failure: FailureCategory,
        extra: [String: Any?]? = nil
    ) {
        var payload: [String: Any?] = [
            "errorDescription": error.localizedDescription,
            "errorType": String(describing: type(of: error)),
        ]
        if let extra { payload.merge(extra) { _, new in new } }
        log(.error, category: category, event: event, message: error.localizedDescription, payload: payload, failure: failure)
    }

    // MARK: - Disk persistence

    private func persist(_ entry: EidosLogEntry) {
        do {
            let data = try encoder.encode(entry)
            guard let line = String(data: data, encoding: .utf8) else { return }

            let url = try currentLogFileURL()
            let withNewline = line + "\n"
            if let fh = try? FileHandle(forWritingTo: url) {
                _ = try? fh.seekToEnd()
                try? fh.write(contentsOf: Data(withNewline.utf8))
                try? fh.close()
            } else {
                // File didn't exist yet — create with the line.
                try withNewline.data(using: .utf8)?
                    .write(to: url, options: .atomic)
            }
        } catch {
            // We must never re-log through ourselves (infinite loop).
            // Mirror to os.Logger only.
            osLogger.fault("Logger failed to persist: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// `<AppSupport>/eidos/logs/YYYY-MM-DD.jsonl`. Rotated by UTC date.
    private func currentLogFileURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dir = base.appendingPathComponent("eidos/logs", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let today = dayFormatter.string(from: Date())
        return dir.appendingPathComponent("\(today).jsonl")
    }

    // MARK: - Read-back (for Diagnostics UI)

    /// Returns the last `limit` entries across today and yesterday's
    /// files, newest first.
    func recentEntries(limit: Int = 200) -> [EidosLogEntry] {
        let decoder = JSONDecoder()
        let base = (try? FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false
        ))?.appendingPathComponent("eidos/logs", isDirectory: true)
        guard let base else { return [] }

        let files = ((try? FileManager.default.contentsOfDirectory(
            at: base, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []).sorted { (a, b) in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }

        var out: [EidosLogEntry] = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let lines = text.split(separator: "\n")
            for line in lines.reversed() {
                if out.count >= limit { return out }
                if let data = line.data(using: .utf8),
                   let entry = try? decoder.decode(EidosLogEntry.self, from: data) {
                    out.append(entry)
                }
            }
        }
        return out
    }

    /// Exports all logs as a single `.jsonl` file for sharing.
    func exportAll() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: false
        )
        let dir = base.appendingPathComponent("eidos/logs", isDirectory: true)
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("eidos-logs-\(Int(Date().timeIntervalSince1970)).jsonl")

        let files = (try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil))
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var combined = Data()
        for file in files {
            let data = try Data(contentsOf: file)
            combined.append(data)
            if combined.last != UInt8(ascii: "\n") {
                combined.append(UInt8(ascii: "\n"))
            }
        }
        try combined.write(to: tmp, options: .atomic)
        return tmp
    }
}
