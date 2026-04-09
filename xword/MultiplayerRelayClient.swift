//
//  MultiplayerRelayClient.swift
//  xword
//

import Foundation

@MainActor
final class MultiplayerRelayClient: NSObject {
    enum Role: String {
        case host
        case join
    }

    private enum Configuration {
        static let relayBaseURL = URL(string: "ws://127.0.0.1:8787")!
    }

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private var webSocketTask: URLSessionWebSocketTask?
    private var activePin: String?
    private var activeRole: Role?

    func connect(pin: String, role: Role) {
        if activePin == pin, activeRole == role, webSocketTask != nil {
            return
        }

        disconnect()

        var url = Configuration.relayBaseURL
        url.append(path: "connect")
        url.append(path: pin)

        let task = session.webSocketTask(with: url)
        activePin = pin
        activeRole = role
        webSocketTask = task
        task.resume()
        receiveNextMessage()
    }

    func disconnect() {
        webSocketTask?.cancel(with: .goingAway, reason: nil)
        webSocketTask = nil
        activePin = nil
        activeRole = nil
    }

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    print("[MultiplayerRelay] Received: \(text)")
                case .data(let data):
                    print("[MultiplayerRelay] Received \(data.count) bytes")
                @unknown default:
                    print("[MultiplayerRelay] Received unknown websocket payload")
                }
                self.receiveNextMessage()
            case .failure(let error):
                print("[MultiplayerRelay] Receive failed: \(error.localizedDescription)")
            }
        }
    }
}

extension MultiplayerRelayClient: URLSessionWebSocketDelegate, URLSessionTaskDelegate {
    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        Task { @MainActor [weak self] in
            guard let self, let activePin, let activeRole else {
                return
            }

            print("[MultiplayerRelay] Connected to lobby \(activePin) as \(activeRole.rawValue)")
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            let reasonText = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "none"
            print("[MultiplayerRelay] Closed connection code=\(closeCode.rawValue) reason=\(reasonText)")
            self.webSocketTask = nil
        }
    }

    nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error else {
            return
        }

        Task { @MainActor [weak self] in
            print("[MultiplayerRelay] Task completed with error: \(error.localizedDescription)")
            self?.webSocketTask = nil
        }
    }
}
