import Foundation
import UIKit
import WebKit
import UserNotifications
import AuthenticationServices
import CryptoKit
import Security

/// Connects the web page to iPhone features: real notifications and Google sign-in.
final class Bridge: NSObject, WKScriptMessageHandler, UNUserNotificationCenterDelegate,
                    ASWebAuthenticationPresentationContextProviding {
    static let shared = Bridge()
    weak var webView: WKWebView?
    private var authSession: ASWebAuthenticationSession?

    // MARK: messages from the page

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard let body = message.body as? [String: Any], let type = body["type"] as? String else { return }
        switch type {
        case "permStatus":
            UNUserNotificationCenter.current().getNotificationSettings { s in
                let ok = s.authorizationStatus == .authorized || s.authorizationStatus == .provisional
                self.send("onPermission", ok)
            }
        case "notifyPermission":
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { granted, _ in
                self.send("onPermission", granted)
            }
        case "schedule":
            schedule(body["items"] as? [[String: Any]] ?? [])
        case "signIn":
            signIn(clientId: body["clientId"] as? String ?? "", scope: body["scope"] as? String ?? "")
        case "getToken":
            refreshToken(clientId: body["clientId"] as? String ?? "")
        case "signOut":
            Keychain.delete()
        default:
            break
        }
    }

    private func send(_ fn: String, _ value: Any) {
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.fragmentsAllowed]),
              let json = String(data: data, encoding: .utf8) else { return }
        DispatchQueue.main.async {
            self.webView?.evaluateJavaScript("window.__native && window.__native.\(fn)(\(json))")
        }
    }

    // MARK: notifications

    private func schedule(_ items: [[String: Any]]) {
        let center = UNUserNotificationCenter.current()
        center.removeAllPendingNotificationRequests()
        let now = Date().timeIntervalSince1970
        for item in items {
            guard let id = item["id"] as? String,
                  let title = item["title"] as? String,
                  let body = item["body"] as? String,
                  let ms = (item["ts"] as? NSNumber)?.doubleValue else { continue }
            let interval = ms / 1000 - now
            if interval < 2 { continue }
            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default
            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            center.add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
        }
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    // MARK: Google sign-in (OAuth with PKCE, no password ever seen by the app)

    private func signIn(clientId: String, scope: String) {
        let prefix = clientId.replacingOccurrences(of: ".apps.googleusercontent.com", with: "")
        guard !prefix.isEmpty else { send("onAuth", ["error": "missing client ID"]); return }
        let scheme = "com.googleusercontent.apps.\(prefix)"
        let redirect = "\(scheme):/oauth2redirect"

        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        let verifier = Data(bytes).base64URL
        let challenge = Data(SHA256.hash(data: Data(verifier.utf8))).base64URL

        var comps = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        comps.queryItems = [
            .init(name: "client_id", value: clientId),
            .init(name: "redirect_uri", value: redirect),
            .init(name: "response_type", value: "code"),
            .init(name: "scope", value: scope),
            .init(name: "code_challenge", value: challenge),
            .init(name: "code_challenge_method", value: "S256"),
            .init(name: "access_type", value: "offline"),
            .init(name: "prompt", value: "consent"),
        ]
        guard let url = comps.url else { return }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: scheme) { [weak self] callback, error in
            guard let self = self else { return }
            if let error = error {
                // closing the sign-in sheet is not an error worth shouting about
                if (error as? ASWebAuthenticationSessionError)?.code == .canceledLogin { self.send("onAuth", ["error": "cancelled"]); return }
                self.send("onAuth", ["error": error.localizedDescription]); return
            }
            guard let callback = callback,
                  let code = URLComponents(url: callback, resolvingAgainstBaseURL: false)?
                    .queryItems?.first(where: { $0.name == "code" })?.value else {
                self.send("onAuth", ["error": "no code returned"]); return
            }
            self.tokenRequest(["client_id": clientId, "code": code, "code_verifier": verifier,
                               "redirect_uri": redirect, "grant_type": "authorization_code"])
        }
        session.presentationContextProvider = self
        session.prefersEphemeralWebBrowserSession = false
        authSession = session
        session.start()
    }

    private func refreshToken(clientId: String) {
        guard !clientId.isEmpty, let refresh = Keychain.read() else { send("onAuth", ["error": "signed_out"]); return }
        tokenRequest(["client_id": clientId, "refresh_token": refresh, "grant_type": "refresh_token"], refreshing: true)
    }

    private func tokenRequest(_ params: [String: String], refreshing: Bool = false) {
        var req = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        req.httpMethod = "POST"
        req.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-._~"))
        req.httpBody = params.map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&").data(using: .utf8)

        URLSession.shared.dataTask(with: req) { [weak self] data, _, error in
            guard let self = self else { return }
            if let error = error { self.send("onAuth", ["error": error.localizedDescription]); return }
            guard let data = data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                self.send("onAuth", ["error": "bad response"]); return
            }
            if let token = json["access_token"] as? String {
                if let refresh = json["refresh_token"] as? String { Keychain.save(refresh) }
                self.send("onAuth", ["access_token": token, "expires_in": json["expires_in"] as? Int ?? 3600])
            } else {
                if refreshing, (json["error"] as? String) == "invalid_grant" {
                    Keychain.delete(); self.send("onAuth", ["error": "signed_out"])
                } else {
                    self.send("onAuth", ["error": (json["error_description"] as? String) ?? (json["error"] as? String) ?? "unknown"])
                }
            }
        }.resume()
    }

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: { $0.isKeyWindow }) }
            .first ?? ASPresentationAnchor()
    }
}

private extension Data {
    var base64URL: String {
        base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// Keeps the Google "stay signed in" token in the iPhone Keychain (never in the web page).
enum Keychain {
    private static let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "momo.google",
        kSecAttrAccount as String: "refresh",
    ]
    static func save(_ value: String) {
        delete()
        var q = query
        q[kSecValueData as String] = Data(value.utf8)
        q[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(q as CFDictionary, nil)
    }
    static func read() -> String? {
        var q = query
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
    static func delete() { SecItemDelete(query as CFDictionary) }
}
