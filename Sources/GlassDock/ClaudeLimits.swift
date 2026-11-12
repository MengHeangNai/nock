import Foundation
import Security

/// Claude Code's plan limits (5-hour and weekly), as shown by Claude Code's /usage.
///
/// Off by default. When the user turns it on, GlassDock reads the sign-in that Claude Code keeps in
/// the Keychain (macOS asks first) and sends it only to Anthropic's usage endpoint. The token is kept
/// in memory and never written anywhere.
enum ClaudeLimits {
    struct Result {
        var plan: String?
        var fiveHour: Double?
        var fiveHourResets: Date?
        var weekly: Double?
        var weeklyResets: Date?
    }

    enum Failure: Error {
        case notSignedIn, expired, denied, network(String)

        var message: String {
            switch self {
            case .notSignedIn: return "Sign in to Claude Code to see plan limits"
            case .expired: return "Run Claude Code once to refresh its sign-in"
            case .denied: return "Keychain access wasn't allowed"
            case .network(let detail): return "Couldn't load limits (\(detail))"
            }
        }
    }

    private struct Credentials {
        let token: String
        let expiresAt: Date?
        let plan: String?
    }

    private static let queue = DispatchQueue(label: "GlassDock.ClaudeLimits")
    private static var cached: Credentials?

    static func fetch(completion: @escaping (Swift.Result<Result, Failure>) -> Void) {
        queue.async {
            let credentials: Credentials
            if let cached, cached.expiresAt.map({ $0 > Date() }) ?? true {
                credentials = cached
            } else {
                switch readCredentials() {
                case .failure(let failure):
                    completion(.failure(failure))
                    return
                case .success(let fresh):
                    credentials = fresh
                }
            }
            if let expires = credentials.expiresAt, expires <= Date() {
                cached = nil
                completion(.failure(.expired))
                return
            }
            cached = credentials

            var request = URLRequest(url: URL(string: "https://api.anthropic.com/api/oauth/usage")!, timeoutInterval: 15)
            request.setValue("Bearer \(credentials.token)", forHTTPHeaderField: "Authorization")
            request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            URLSession.shared.dataTask(with: request) { data, response, error in
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 401 || status == 403 {
                    queue.async { cached = nil }
                    completion(.failure(.expired))
                    return
                }
                guard status == 200, let data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                    completion(.failure(.network(error?.localizedDescription ?? "HTTP \(status)")))
                    return
                }
                func window(_ key: String) -> (Double?, Date?) {
                    guard let window = json[key] as? [String: Any] else { return (nil, nil) }
                    return ((window["utilization"] as? NSNumber)?.doubleValue, parseDate(window["resets_at"] as? String))
                }
                var result = Result(plan: credentials.plan)
                (result.fiveHour, result.fiveHourResets) = window("five_hour")
                (result.weekly, result.weeklyResets) = window("seven_day")
                completion(.success(result))
            }.resume()
        }
    }

    private static func readCredentials() -> Swift.Result<Credentials, Failure> {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        var data = status == errSecSuccess ? item as? Data : nil
        if status == errSecUserCanceled || status == errSecAuthFailed || status == errSecInteractionNotAllowed {
            return .failure(.denied)
        }
        if data == nil {
            // Older setups keep the sign-in in a file instead.
            let file = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/.credentials.json")
            data = try? Data(contentsOf: file)
        }
        guard let data,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let oauth = json["claudeAiOauth"] as? [String: Any],
              let token = oauth["accessToken"] as? String, !token.isEmpty else {
            return .failure(.notSignedIn)
        }
        let expires = (oauth["expiresAt"] as? NSNumber).map { value -> Date in
            let raw = value.doubleValue
            return Date(timeIntervalSince1970: raw > 1e12 ? raw / 1000 : raw)
        }
        let plan = planName(tier: oauth["rateLimitTier"] as? String, subscription: oauth["subscriptionType"] as? String)
        return .success(Credentials(token: token, expiresAt: expires, plan: plan))
    }

    /// "default_claude_max_5x" → "Max 5x"; "pro" → "Pro".
    static func planName(tier: String?, subscription: String?) -> String? {
        if let tier, let range = tier.lowercased().range(of: #"max_\d+x"#, options: .regularExpression) {
            let digits = tier.lowercased()[range].filter(\.isNumber)
            return "Max \(digits)x"
        }
        guard let subscription, !subscription.isEmpty else { return nil }
        return subscription.prefix(1).uppercased() + subscription.dropFirst()
    }

    static func parseDate(_ string: String?) -> Date? {
        guard var string else { return nil }
        // Fractional seconds can have more digits than ISO8601DateFormatter accepts.
        if let range = string.range(of: #"\.\d+"#, options: .regularExpression) { string.removeSubrange(range) }
        return ISO8601DateFormatter().date(from: string)
    }
}
