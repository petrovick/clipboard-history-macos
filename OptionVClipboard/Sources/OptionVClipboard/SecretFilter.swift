import Foundation

/// Rejects clipboard text that looks unsafe to retain.
struct SecretFilter {
    let skipShortOneTimeCodes: Bool
    private static let longTokenRegex = try? NSRegularExpression(pattern: #"\b[A-Za-z0-9_\-+/=]{32,}\b"#)

    func shouldReject(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.isEmpty == false else {
            return true
        }

        if containsPrivateKeyMarker(trimmed) {
            return true
        }

        if containsSecretLabel(trimmed) {
            return true
        }

        if skipShortOneTimeCodes && looksLikeShortOneTimeCode(trimmed) {
            return true
        }

        return containsLongRandomToken(trimmed)
    }

    private func containsPrivateKeyMarker(_ text: String) -> Bool {
        text.localizedCaseInsensitiveContains("-----BEGIN PRIVATE KEY-----")
            || text.localizedCaseInsensitiveContains("-----BEGIN RSA PRIVATE KEY-----")
            || text.localizedCaseInsensitiveContains("-----BEGIN OPENSSH PRIVATE KEY-----")
            || text.localizedCaseInsensitiveContains("-----BEGIN EC PRIVATE KEY-----")
    }

    private func containsSecretLabel(_ text: String) -> Bool {
        let lowered = text.lowercased()
        let labels = [
            "password=",
            "passwd=",
            "pwd=",
            "token=",
            "secret=",
            "api_key=",
            "apikey=",
            "authorization:",
            "bearer "
        ]

        return labels.contains { lowered.contains($0) }
    }

    private func looksLikeShortOneTimeCode(_ text: String) -> Bool {
        text.range(of: #"^\d{4,8}$"#, options: .regularExpression) != nil
    }

    private func containsLongRandomToken(_ text: String) -> Bool {
        guard let regex = Self.longTokenRegex else {
            return false
        }

        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.matches(in: text, range: range).contains { match in
            guard let tokenRange = Range(match.range, in: text) else {
                return false
            }

            let token = String(text[tokenRange])
            return hasMixedTokenCharacters(token)
        }
    }

    private func hasMixedTokenCharacters(_ token: String) -> Bool {
        let scalars = token.unicodeScalars
        let hasLetter = scalars.contains { CharacterSet.letters.contains($0) }
        let hasNumber = scalars.contains { CharacterSet.decimalDigits.contains($0) }
        let hasSymbol = scalars.contains { CharacterSet(charactersIn: "_-+/=").contains($0) }

        return (hasLetter && hasNumber) || (hasLetter && hasSymbol) || (hasNumber && hasSymbol)
    }
}
