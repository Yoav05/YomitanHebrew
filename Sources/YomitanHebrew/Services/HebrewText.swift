import Foundation

enum HebrewText {
    static func containsHebrew(_ value: String) -> Bool {
        value.unicodeScalars.contains { scalar in
            (0x0590...0x05FF).contains(scalar.value)
        }
    }

    static func withoutNiqqud(_ value: String) -> String {
        String(value.unicodeScalars.filter { scalar in
            // Hebrew cantillation marks, vowel points and punctuation used as marks.
            !(0x0591...0x05C7).contains(scalar.value)
        })
    }
}

extension String {
    var htmlEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }
}
