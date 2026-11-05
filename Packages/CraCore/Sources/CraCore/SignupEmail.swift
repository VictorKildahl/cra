import Foundation

/// The isolated renderer sends field attributes only. Signup intent is determined separately
/// from the surrounding form so words on a password or verification field cannot label its neighbor.
public enum SignupEmail {
    public enum FieldDecision: Equatable {
        case email, skip, askModel(String)
    }

    public static func address(_ text: String) -> String? {
        let address = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = address.split(separator: "@", omittingEmptySubsequences: false)
        guard address.utf8.count <= 254, parts.count == 2,
              !parts[0].isEmpty, parts[0].utf8.count <= 64, !parts[1].isEmpty else { return nil }
        let local = parts[0]
        let domainLabels = parts[1].split(separator: ".", omittingEmptySubsequences: false)
        let allowedLocal = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.!#$%&'*+-/=?^_`{|}~")
        guard local.unicodeScalars.allSatisfy(allowedLocal.contains),
              !local.hasPrefix("."), !local.hasSuffix("."), !local.contains(".."),
              domainLabels.allSatisfy({ label in
                  !label.isEmpty && label.utf8.count <= 63 && !label.hasPrefix("-") && !label.hasSuffix("-")
                      && label.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }
              }) else { return nil }
        return address
    }

    public static func field(hints: String, signup: Bool) -> FieldDecision {
        guard signup, hints.utf8.count <= 2048 else { return .skip }
        var fields: [String: String] = [:]
        for line in hints.split(separator: "\n") {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = String(line[..<colon])
            guard ["type", "autocomplete", "label", "name", "id", "placeholder"].contains(key) else { continue }
            let raw = String(line[line.index(after: colon)...].prefix(160))
            let clean = raw
                .replacingOccurrences(of: #"(?i)(?:https?://|www\.)\S+|\S*@\S*|\d{3,}"#, with: " ", options: .regularExpression)
                .replacingOccurrences(of: #"([a-z])([A-Z])"#, with: "$1 $2", options: .regularExpression)
                .lowercased()
                .components(separatedBy: CharacterSet.letters.inverted)
                .filter { !$0.isEmpty }.joined(separator: " ")
            if !clean.isEmpty { fields[key] = clean }
        }
        guard let type = fields["type"], type == "email" || type == "text" else { return .skip }
        let keys = ["autocomplete", "label", "name", "id", "placeholder"]
        let descriptions = keys.compactMap { fields[$0] }
        let tokens = Set(descriptions.joined(separator: " ").split(separator: " ").map(String.init))
        let excluded: Set<String> = [
            "otp", "totp", "code", "passcode", "password", "verification", "captcha", "pin",
            "recipient", "friend", "invite", "invitation", "referral", "colleague", "referrer",
            "newsletter", "subscribe", "search", "phone", "mobile", "telephone",
            "billing", "shipping", "recovery", "alternate", "backup", "guardian", "parent",
        ]
        if !tokens.isDisjoint(with: excluded) { return .skip }
        if type == "email" || tokens.contains("email") || descriptions.contains(where: { $0.contains("e mail") }) { return .email }
        // A username, first name, or address can coexist with the account email.
        // Never ask the model to turn an explicitly different role into an email.
        let otherRoles: Set<String> = ["username", "nickname", "firstname", "surname", "lastname", "street", "city", "postal", "country", "company"]
        if !tokens.isDisjoint(with: otherRoles) || descriptions.contains(where: { ["name", "first name", "last name", "full name"].contains($0) }) { return .skip }
        // Visible copy names the field for the person filling it out. Sites often give it
        // an opaque implementation ID ("identity") that would contradict a clear label ("Courriel").
        let keysForModel = fields["label"] != nil || fields["placeholder"] != nil ? ["label", "placeholder"] : ["name", "id"]
        let evidence = keysForModel.compactMap { key in fields[key].map { "\(key): \($0)" } }
        guard !evidence.isEmpty else { return .skip }
        return .askModel(evidence.joined(separator: "\n"))
    }
}
