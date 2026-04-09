//
//  MultiplayerRelayClient.swift
//  xword
//

import Foundation

@MainActor
protocol MultiplayerRelayClientDelegate: AnyObject {
    func relayClient(_ client: MultiplayerRelayClient, didReceive event: MultiplayerRelayClient.ServerEvent)
}

@MainActor
final class MultiplayerRelayClient: NSObject {
    enum ConnectionRole: String {
        case host
        case join
    }

    enum ServerEvent {
        case welcome(selfID: String, pin: String, role: MultiplayerRelayRole, players: [MultiplayerLobbyPlayer])
        case roster(players: [MultiplayerLobbyPlayer])
        case playerJoined(playerID: String)
        case relayed(fromPlayerID: String, event: MultiplayerRelayEvent)
        case kicked
        case lobbyEnded
        case error(String)
    }

    private struct KickPayload: Encodable {
        let type = "kick"
        let playerID: String
    }

    private struct EndLobbyPayload: Encodable {
        let type = "end_lobby"
    }

    private struct RelayPayload: Encodable {
        let type = "relay"
        let targetPlayerID: String?
        let event: MultiplayerRelayEvent
    }

    private struct WelcomeMessage: Decodable {
        let type: String
        let selfID: String
        let pin: String
        let role: MultiplayerRelayRole
        let players: [MultiplayerLobbyPlayer]
    }

    private struct LegacyConnectedMessage: Decodable {
        let type: String
        let pin: String
        let role: MultiplayerRelayRole?
    }

    private struct RosterMessage: Decodable {
        let type: String
        let players: [MultiplayerLobbyPlayer]
    }

    private struct PlayerJoinedMessage: Decodable {
        let type: String
        let playerID: String
    }

    private struct RelayedMessage: Decodable {
        let type: String
        let fromPlayerID: String
        let event: MultiplayerRelayEvent
    }

    private struct LegacyBroadcastMessage: Decodable {
        let type: String
        let from: String
        let payload: String
    }

    private struct LegacyNestedRelayMessage: Decodable {
        let type: String
        let event: MultiplayerRelayEvent
    }

    private struct ErrorMessage: Decodable {
        let type: String
        let message: String
    }

    private struct BasicMessage: Decodable {
        let type: String
    }

    private enum Configuration {
        static let relayBaseURL = URL(string: "wss://xword-relay.built-by-cdp.com")!
    }

    weak var delegate: MultiplayerRelayClientDelegate?

    private lazy var session: URLSession = {
        let configuration = URLSessionConfiguration.default
        return URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
    }()

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var webSocketTask: URLSessionWebSocketTask?
    private var activePin: String?
    private var activeRole: ConnectionRole?

    func connect(pin: String, role: ConnectionRole) {
        if activePin == pin, activeRole == role, webSocketTask != nil {
            return
        }

        disconnect()

        var url = Configuration.relayBaseURL
        url.append(path: "connect")
        url.append(path: pin)

        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "role", value: role.rawValue)
        ]

        guard let resolvedURL = components?.url else {
            return
        }

        let task = session.webSocketTask(with: resolvedURL)
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

    func sendRelayEvent(_ event: MultiplayerRelayEvent, targetPlayerID: String? = nil) {
        sendEncodable(RelayPayload(targetPlayerID: targetPlayerID, event: event))
    }

    func kick(playerID: String) {
        sendEncodable(KickPayload(playerID: playerID))
    }

    func endLobby() {
        sendEncodable(EndLobbyPayload())
    }

    private func sendEncodable(_ payload: some Encodable) {
        guard let webSocketTask else {
            return
        }

        do {
            let data = try encoder.encode(payload)
            guard let text = String(data: data, encoding: .utf8) else {
                return
            }

            webSocketTask.send(.string(text)) { error in
                if let error {
                    print("[MultiplayerRelay] Send failed: \(error.localizedDescription)")
                }
            }
        } catch {
            print("[MultiplayerRelay] Encode failed: \(error.localizedDescription)")
        }
    }

    private func receiveNextMessage() {
        webSocketTask?.receive { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                switch result {
                case .success(let message):
                    self.handle(message)
                    self.receiveNextMessage()
                case .failure(let error):
                    print("[MultiplayerRelay] Receive failed: \(error.localizedDescription)")
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data

        switch message {
        case .string(let text):
            data = Data(text.utf8)
        case .data(let rawData):
            data = rawData
        @unknown default:
            print("[MultiplayerRelay] Unknown websocket payload")
            return
        }

        do {
            let basic = try decoder.decode(BasicMessage.self, from: data)

            switch basic.type {
            case "welcome":
                let payload = try decoder.decode(WelcomeMessage.self, from: data)
                delegate?.relayClient(self, didReceive: .welcome(selfID: payload.selfID, pin: payload.pin, role: payload.role, players: payload.players))
            case "connected":
                let payload = try decoder.decode(LegacyConnectedMessage.self, from: data)
                let resolvedRole = payload.role ?? (activeRole == .host ? .host : .join)
                let syntheticPlayer = MultiplayerLobbyPlayer(
                    id: "legacy-\(UUID().uuidString)",
                    role: resolvedRole,
                    color: .pink,
                    joinedAt: 1
                )
                delegate?.relayClient(self, didReceive: .welcome(selfID: syntheticPlayer.id, pin: payload.pin, role: resolvedRole, players: [syntheticPlayer]))
            case "roster":
                let payload = try decoder.decode(RosterMessage.self, from: data)
                delegate?.relayClient(self, didReceive: .roster(players: payload.players))
            case "player_joined":
                let payload = try decoder.decode(PlayerJoinedMessage.self, from: data)
                delegate?.relayClient(self, didReceive: .playerJoined(playerID: payload.playerID))
            case "relay":
                let payload = try decoder.decode(RelayedMessage.self, from: data)
                delegate?.relayClient(self, didReceive: .relayed(fromPlayerID: payload.fromPlayerID, event: payload.event))
            case "message":
                let payload = try decoder.decode(LegacyBroadcastMessage.self, from: data)
                handleLegacyBroadcast(payload)
            case "kicked":
                delegate?.relayClient(self, didReceive: .kicked)
            case "lobby_ended":
                delegate?.relayClient(self, didReceive: .lobbyEnded)
            case "error":
                let payload = try decoder.decode(ErrorMessage.self, from: data)
                delegate?.relayClient(self, didReceive: .error(payload.message))
            default:
                print("[MultiplayerRelay] Ignored event type \(basic.type)")
            }
        } catch {
            print("[MultiplayerRelay] Decode failed: \(error.localizedDescription)")
        }
    }

    private func handleLegacyBroadcast(_ message: LegacyBroadcastMessage) {
        guard let payloadData = message.payload.data(using: .utf8) else {
            return
        }

        guard let basic = try? decoder.decode(BasicMessage.self, from: payloadData) else {
            return
        }

        switch basic.type {
        case "relay":
            guard let relay = try? decoder.decode(LegacyNestedRelayMessage.self, from: payloadData) else {
                return
            }

            delegate?.relayClient(
                self,
                didReceive: .relayed(fromPlayerID: "legacy-\(message.from)", event: relay.event)
            )
        default:
            break
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

            print("[MultiplayerRelay] Connected websocket for \(activeRole.rawValue) lobby \(activePin)")
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
