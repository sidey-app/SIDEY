import AppKit
import CryptoKit
import Foundation
import Network
import Security

/// Installed-desktop authorization code + PKCE, as specified by Google's
/// https://developers.google.com/identity/protocols/oauth2/native-app.
enum GoogleDesktopOAuth {
    static func authenticate(configuration: RuntimeConfiguration, nonce: String, network: URLSession) async throws -> String {
        let verifier = try randomToken()
        let state = try randomToken()
        let callback = GoogleLoopbackCallback(state: state)
        let redirect = try await callback.start()
        defer { callback.cancel() }
        let url = authorizationURL(clientID: configuration.googleClientID, nonce: nonce,
                                   verifier: verifier, state: state, redirect: redirect)
        guard await MainActor.run(body: { NSWorkspace.shared.open(url) }) else {
            throw SideySessionError.rejected("browser_unavailable")
        }
        let code = try await callback.code()
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 30
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var fields = ["client_id": configuration.googleClientID, "code": code,
                      "code_verifier": verifier, "redirect_uri": redirect.absoluteString,
                      "grant_type": "authorization_code"]
        if !configuration.googleClientSecret.isEmpty { fields["client_secret"] = configuration.googleClientSecret }
        request.httpBody = formData(fields)
        let (data, response) = try await network.data(for: request)
        guard let response = response as? HTTPURLResponse, response.statusCode == 200,
              let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = object["id_token"] as? String, !token.isEmpty else {
            throw SideySessionError.rejected("google_code_exchange_failed")
        }
        return token
    }

    static func authorizationURL(clientID: String, nonce: String, verifier: String, state: String, redirect: URL) -> URL {
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        let challenge = base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
        components.queryItems = [
            URLQueryItem(name: "client_id", value: clientID), URLQueryItem(name: "redirect_uri", value: redirect.absoluteString),
            URLQueryItem(name: "response_type", value: "code"), URLQueryItem(name: "scope", value: "openid email"),
            URLQueryItem(name: "state", value: state), URLQueryItem(name: "nonce", value: nonce),
            URLQueryItem(name: "code_challenge", value: challenge), URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "prompt", value: "select_account")
        ]
        return components.url!
    }
    static func formData(_ fields: [String: String]) -> Data {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        return Data(fields.sorted { $0.key < $1.key }.map {
            "\($0.key.addingPercentEncoding(withAllowedCharacters: allowed)!)=\($0.value.addingPercentEncoding(withAllowedCharacters: allowed)!)"
        }.joined(separator: "&").utf8)
    }
    private static func randomToken() throws -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw SideySessionError.rejected("secure_random_unavailable")
        }
        return base64URL(Data(bytes))
    }
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
    }
}

/// All listener state is confined to queue. Only 127.0.0.1 is bound; the
/// callback has a bounded lifetime, payload and number of pending connections.
final class GoogleLoopbackCallback: @unchecked Sendable {
    private let queue = DispatchQueue(label: "app.sidey.google-loopback")
    private let expectedState: String
    private var listener: NWListener?
    private var ready: CheckedContinuation<URL, Error>?
    private var waiting: CheckedContinuation<String, Error>?
    private var result: Result<String, Error>?
    private var connections: [ObjectIdentifier: NWConnection] = [:]

    init(state: String) { expectedState = state }
    func start() async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let parameters = NWParameters.tcp
                    parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
                    let listener = try NWListener(using: parameters)
                    self.listener = listener
                    self.ready = continuation
                    listener.stateUpdateHandler = { [weak self] state in
                        guard let self else { return }
                        switch state {
                        case .ready:
                            guard let port = listener.port else { return }
                            self.ready?.resume(returning: URL(string: "http://127.0.0.1:\(port.rawValue)/")!)
                            self.ready = nil
                        case .failed(let error): self.finish(.failure(error))
                        default: break
                        }
                    }
                    listener.newConnectionHandler = { [weak self] connection in self?.receive(connection) }
                    listener.start(queue: self.queue)
                    self.queue.asyncAfter(deadline: .now() + 180) {
                        self.finish(.failure(SideySessionError.rejected("google_login_timeout")))
                    }
                } catch { continuation.resume(throwing: error) }
            }
        }
    }
    func code() async throws -> String {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                queue.async {
                    if let result = self.result { continuation.resume(with: result) }
                    else { self.waiting = continuation }
                }
            }
        } onCancel: { self.cancel() }
    }
    func cancel() { queue.async { self.finish(.failure(CancellationError())) } }

    static func parseRequest(_ data: Data, state: String) -> Result<String, Error>? {
        guard let request = String(data: data, encoding: .utf8), request.contains("\r\n\r\n") else { return nil }
        let firstLine = request.components(separatedBy: "\r\n")[0].split(separator: " ")
        guard firstLine.count == 3, firstLine[0] == "GET",
              let parts = URLComponents(string: "http://127.0.0.1" + firstLine[1]), parts.path == "/" else {
            return .failure(SideySessionError.rejected("invalid_oauth_callback"))
        }
        let query = parts.queryItems ?? []
        guard query.filter({ $0.name == "state" }).count == 1,
              query.first(where: { $0.name == "state" })?.value == state,
              query.filter({ $0.name == "code" }).count <= 1 else {
            return .failure(SideySessionError.rejected("invalid_oauth_state"))
        }
        if query.contains(where: { $0.name == "error" }) { return .failure(SideySessionError.rejected("google_login_cancelled")) }
        guard let code = query.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
            return .failure(SideySessionError.rejected("missing_oauth_code"))
        }
        return .success(code)
    }
    private func receive(_ connection: NWConnection) {
        guard connections.count < 4, result == nil else { connection.cancel(); return }
        connections[ObjectIdentifier(connection)] = connection
        connection.start(queue: queue)
        read(connection, accumulated: Data())
        queue.asyncAfter(deadline: .now() + 5) { [weak self, weak connection] in
            guard let self, let connection else { return }
            self.connections.removeValue(forKey: ObjectIdentifier(connection))
            connection.cancel()
        }
    }
    private func read(_ connection: NWConnection, accumulated: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192 - accumulated.count) { data, _, complete, error in
            var all = accumulated
            if let data { all.append(data) }
            if let parsed = Self.parseRequest(all, state: self.expectedState) {
                let success: Bool
                if case .success = parsed { success = true } else { success = false }
                let body = success ? "SIDEY login received. You can close this window." : "Invalid login callback."
                let response = "HTTP/1.1 \(success ? "200 OK" : "400 Bad Request")\r\nContent-Type: text/plain\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
                connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in
                    self.connections.removeValue(forKey: ObjectIdentifier(connection))
                    connection.cancel()
                    // Unrelated local requests cannot terminate an active login.
                    if success { self.finish(parsed) }
                    else if case .failure(SideySessionError.rejected("google_login_cancelled")) = parsed {
                        self.finish(parsed)
                    }
                })
            } else if error != nil || complete || all.count >= 8192 {
                self.connections.removeValue(forKey: ObjectIdentifier(connection))
                connection.cancel()
            } else { self.read(connection, accumulated: all) }
        }
    }
    private func finish(_ value: Result<String, Error>) {
        guard result == nil else { return }
        result = value
        if let ready { ready.resume(throwing: SideySessionError.rejected("google_listener_unavailable")); self.ready = nil }
        waiting?.resume(with: value)
        waiting = nil
        listener?.cancel()
        listener = nil
        connections.values.forEach { $0.cancel() }
        connections.removeAll()
    }
}
