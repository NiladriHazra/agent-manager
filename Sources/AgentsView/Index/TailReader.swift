import Foundation

/// Bounded reads for append-only JSONL logs.
///
/// Session files reach 295 MB on this machine, so no code path here may ever
/// read a whole file. Every function takes a byte budget and gives up rather
/// than escalating without limit.
enum TailReader {
    /// Complete lines from the last `bytes` of a file, newest first. The first
    /// line in the window is dropped because it is almost certainly truncated.
    static func lines(of url: URL, bytes: Int) -> [String] {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return [] }
        defer { try? handle.close() }

        guard let end = try? handle.seekToEnd() else { return [] }
        let window = UInt64(min(Int(end), bytes))
        guard window > 0 else { return [] }

        try? handle.seek(toOffset: end - window)
        guard let data = try? handle.readToEnd(), !data.isEmpty else { return [] }

        var text = String(decoding: data, as: UTF8.self)
        if window < end, let firstBreak = text.firstIndex(of: "\n") {
            text = String(text[text.index(after: firstBreak)...])
        }
        return text.split(separator: "\n").map(String.init).reversed()
    }

    /// Walks a widening tail looking for the newest line containing `marker`,
    /// decoding it once found. Stops at 4 MB instead of degrading to a full read.
    static func newestLine<T>(
        in url: URL,
        containing marker: String,
        budgets: [Int] = [64 * 1024, 256 * 1024, 1024 * 1024, 4 * 1024 * 1024],
        decode: (Data) -> T?
    ) -> T? {
        for budget in budgets {
            for line in lines(of: url, bytes: budget) where line.contains(marker) {
                if let value = decode(Data(line.utf8)) { return value }
            }
            // A tail smaller than the budget means the whole file was covered.
            if let size = try? FileManager.default
                .attributesOfItem(atPath: url.path)[.size] as? Int, size <= budget {
                return nil
            }
        }
        return nil
    }
}
