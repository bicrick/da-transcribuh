import Foundation
import os
import os.signpost

/// Lightweight Instruments intervals for the recording capture path.
///
/// In Instruments: Points of Interest / os_signpost, subsystem
/// `com.bicrick.PromptAnnotator`, category `CapturePerf`.
enum CapturePerf {
    static let log = OSLog(subsystem: "com.bicrick.PromptAnnotator", category: "CapturePerf")
    static let logger = Logger(subsystem: "com.bicrick.PromptAnnotator", category: "CapturePerf")

    enum Interval {
        case capture
        case shareableContent
        case screenshot
        case composite
        case crop
        case encode
        case write
        case thumbnail
        case uiUpdate

        var signpostName: StaticString {
            switch self {
            case .capture: return "capture"
            case .shareableContent: return "shareableContent"
            case .screenshot: return "screenshot"
            case .composite: return "composite"
            case .crop: return "crop"
            case .encode: return "encode"
            case .write: return "write"
            case .thumbnail: return "thumbnail"
            case .uiUpdate: return "uiUpdate"
            }
        }
    }

    @inline(__always)
    static func begin(_ name: Interval) -> OSSignpostID {
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name.signpostName, signpostID: id)
        return id
    }

    @inline(__always)
    static func end(_ name: Interval, _ id: OSSignpostID) {
        os_signpost(.end, log: log, name: name.signpostName, signpostID: id)
    }

    @inline(__always)
    static func interval<T>(_ name: Interval, _ body: () throws -> T) rethrows -> T {
        let id = begin(name)
        defer { end(name, id) }
        return try body()
    }

    @inline(__always)
    static func intervalAsync<T>(_ name: Interval, _ body: () async throws -> T) async rethrows -> T {
        let id = begin(name)
        defer { end(name, id) }
        return try await body()
    }
}
