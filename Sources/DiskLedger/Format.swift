import Foundation

enum Format {
    /// Finder と同じ十進の単位（1 GB = 10 億バイト）。
    static func bytes(_ value: UInt64) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(clamping: value), countStyle: .file)
    }

    static func count(_ value: Int) -> String {
        value.formatted(.number)
    }

    static func percent(_ share: Double) -> String {
        if share > 0, share < 0.001 { return "<0.1%" }
        return share.formatted(.percent.precision(.fractionLength(1)))
    }

    static func date(_ seconds: UInt32) -> String {
        guard seconds > 0 else { return "" }
        return Date(timeIntervalSince1970: TimeInterval(seconds))
            .formatted(.dateTime.year().month(.twoDigits).day(.twoDigits))
    }
}
