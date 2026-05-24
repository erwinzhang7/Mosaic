import Foundation

enum SearchMatcher {
    static func score(_ candidate: String, query: String) -> Int? {
        let n = candidate.lowercased()
        let q = query.lowercased().trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return 0 }
        if n.hasPrefix(q) { return 100 }
        let words = n.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
        for w in words where w.hasPrefix(q) { return 80 }
        let initials = String(words.compactMap { $0.first })
        if initials.hasPrefix(q) || initials.contains(q) { return 60 }
        if n.contains(q) { return 30 }
        return nil
    }
}
