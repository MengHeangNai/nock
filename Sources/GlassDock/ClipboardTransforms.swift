import Foundation

/// Text transforms for clipboard items. Pure functions, no UI or pasteboard access.
enum ClipboardTransform: CaseIterable, Identifiable {
    case formatJSON, minifyJSON
    case stripTrackingParameters
    case trimWhitespace, collapseBlankLines
    case uppercase, lowercase, titleCase
    case base64Encode, base64Decode
    case urlEncode, urlDecode

    struct Failure: Error {
        let message: String
    }

    var id: Self { self }

    var title: String {
        switch self {
        case .formatJSON: return "Format JSON"
        case .minifyJSON: return "Minify JSON"
        case .stripTrackingParameters: return "Remove tracking parameters"
        case .trimWhitespace: return "Trim whitespace"
        case .collapseBlankLines: return "Collapse blank lines"
        case .uppercase: return "UPPERCASE"
        case .lowercase: return "lowercase"
        case .titleCase: return "Title Case"
        case .base64Encode: return "Base64 encode"
        case .base64Decode: return "Base64 decode"
        case .urlEncode: return "URL encode"
        case .urlDecode: return "URL decode"
        }
    }

    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "gbraid", "wbraid", "msclkid", "yclid", "twclid", "ttclid",
        "mc_eid", "mc_cid", "igshid", "ref", "ref_src", "ref_url", "_hsenc", "_hsmi",
    ]

    private static let urlComponentCharacters = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")

    /// The transforms that would change `text`, in menu order. Pass the clipboard item's text.
    static func applicable(to text: String) -> [ClipboardTransform] {
        allCases.filter { transform in
            guard case .success(let output) = transform.apply(to: text) else { return false }
            return output != text
        }
    }

    /// True when `text` is shaped like a JSON object or array but does not parse, so the UI can say so.
    static func looksLikeInvalidJSON(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let isBraced = trimmed.hasPrefix("{") && trimmed.hasSuffix("}")
        let isBracketed = trimmed.hasPrefix("[") && trimmed.hasSuffix("]")
        return (isBraced || isBracketed) && !isValidJSONContainer(trimmed)
    }

    /// Returns the transformed copy of `text`, or a failure with a message to show the user.
    func apply(to text: String) -> Result<String, Failure> {
        switch self {
        case .formatJSON: return Self.reformatJSON(text, indent: "  ")
        case .minifyJSON: return Self.reformatJSON(text, indent: nil)
        case .stripTrackingParameters: return Self.stripTrackingParameters(text)
        case .trimWhitespace: return .success(Self.trimmed(text))
        case .collapseBlankLines: return .success(Self.collapsingBlankLines(text))
        case .uppercase: return .success(text.uppercased())
        case .lowercase: return .success(text.lowercased())
        case .titleCase: return .success(text.capitalized)
        case .base64Encode: return .success(Data(text.utf8).base64EncodedString())
        case .base64Decode: return Self.decodeBase64(text)
        case .urlEncode: return Self.encodeURLComponent(text)
        case .urlDecode: return Self.decodeURLComponent(text)
        }
    }

    private static func isValidJSONContainer(_ text: String) -> Bool {
        guard let data = text.data(using: .utf8),
              let root = try? JSONSerialization.jsonObject(with: data),
              root is [String: Any] || root is [Any] else { return false }
        return !hasTrailingComma(text)
    }

    /// Foundation's parser accepts a comma before a closing bracket; strict JSON does not.
    private static func hasTrailingComma(_ text: String) -> Bool {
        var inString = false
        var isEscaped = false
        var previous: Character = " "
        for character in text {
            if inString {
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character.isWhitespace { continue }
            if (character == "}" || character == "]") && previous == "," { return true }
            if character == "\"" { inString = true }
            previous = character
        }
        return false
    }

    private static func reformatJSON(_ text: String, indent: String?) -> Result<String, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isValidJSONContainer(trimmed) else { return .failure(Failure(message: "Not valid JSON")) }

        func lineBreak(_ depth: Int) -> String {
            guard let indent else { return "" }
            return "\n" + String(repeating: indent, count: depth)
        }

        var output = ""
        var depth = 0
        var inString = false
        var isEscaped = false
        var justOpened = false
        for character in trimmed {
            if inString {
                output.append(character)
                if isEscaped {
                    isEscaped = false
                } else if character == "\\" {
                    isEscaped = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }
            if character.isWhitespace { continue }

            let isClosing = character == "}" || character == "]"
            if isClosing { depth -= 1 }
            if justOpened && !isClosing { output += lineBreak(depth) }
            if isClosing && !justOpened { output += lineBreak(depth) }
            justOpened = false

            switch character {
            case "{", "[":
                output.append(character)
                depth += 1
                justOpened = true
            case ",":
                output += "," + lineBreak(depth)
            case ":":
                output += indent == nil ? ":" : ": "
            case "\"":
                inString = true
                output.append(character)
            default:
                output.append(character)
            }
        }
        return .success(output)
    }

    private static func stripTrackingParameters(_ text: String) -> Result<String, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.contains(where: \.isWhitespace),
              var components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(), scheme == "http" || scheme == "https",
              components.host != nil else { return .failure(Failure(message: "Not a URL")) }

        let items = components.percentEncodedQueryItems ?? []
        let kept = items.filter { !isTrackingParameter($0.name) }
        guard kept.count < items.count else { return .success(text) }

        components.percentEncodedQueryItems = kept.isEmpty ? nil : kept
        guard let cleaned = components.string else { return .failure(Failure(message: "Not a URL")) }
        return .success(cleaned)
    }

    private static func isTrackingParameter(_ encodedName: String) -> Bool {
        let name = (encodedName.removingPercentEncoding ?? encodedName).lowercased()
        return name.hasPrefix("utm_") || trackingParameters.contains(name)
    }

    private static func trimmed(_ text: String) -> String {
        lines(of: text)
            .map { String($0.reversed().drop(while: \.isWhitespace).reversed()) }
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func collapsingBlankLines(_ text: String) -> String {
        var result: [String] = []
        for line in lines(of: text) {
            let isBlank = line.allSatisfy(\.isWhitespace)
            if isBlank && result.last?.isEmpty == true { continue }
            result.append(isBlank ? "" : String(line))
        }
        return result.joined(separator: "\n")
    }

    private static func lines(of text: String) -> [Substring] {
        text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    }

    private static func decodeBase64(_ text: String) -> Result<String, Failure> {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let data = Data(base64Encoded: trimmed),
              let decoded = String(data: data, encoding: .utf8),
              !decoded.unicodeScalars.contains(where: { $0.properties.generalCategory == .control && !$0.properties.isWhitespace })
        else { return .failure(Failure(message: "Not valid Base64 text")) }
        return .success(decoded)
    }

    private static func encodeURLComponent(_ text: String) -> Result<String, Failure> {
        guard let encoded = text.addingPercentEncoding(withAllowedCharacters: urlComponentCharacters) else {
            return .failure(Failure(message: "Can't URL encode"))
        }
        return .success(encoded)
    }

    private static func decodeURLComponent(_ text: String) -> Result<String, Failure> {
        guard let decoded = text.removingPercentEncoding else {
            return .failure(Failure(message: "Invalid percent-encoding"))
        }
        return .success(decoded)
    }
}
