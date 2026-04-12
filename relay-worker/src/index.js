const PLAYER_COLORS = ["pink", "orange", "yellow", "teal", "lightGreen"];
const MAX_PLAYERS = PLAYER_COLORS.length + 1;

export class LobbyRelay {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.sessions = new Map();
    this.joinSequence = 0;
    this.latestSnapshot = null;
  }

  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") {
      return json({ error: "Expected websocket upgrade" }, 426);
    }

    const url = new URL(request.url);
    const role = url.searchParams.get("role") === "host" ? "host" : "join";
    const pin = url.searchParams.get("pin") ?? this.state.id.toString();

    if (this.sessions.size >= MAX_PLAYERS) {
      return json({ error: "Lobby full" }, 409);
    }

    if (role === "host" && this.currentHost()) {
      return json({ error: "Host already connected" }, 409);
    }

    const color = this.nextAvailableColor();
    if (!color) {
      return json({ error: "No colors available" }, 409);
    }

    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];
    const playerId = crypto.randomUUID();
    const session = {
      id: playerId,
      pin,
      role,
      color,
      joinedAt: ++this.joinSequence,
      socket: server,
    };

    server.accept();
    if (role === "host") {
      this.latestSnapshot = null;
    }
    this.sessions.set(playerId, session);

    server.addEventListener("message", (event) => {
      this.handleMessage(session, event.data);
    });

    server.addEventListener("close", () => {
      this.removeSession(playerId, "close");
    });

    server.addEventListener("error", () => {
      this.removeSession(playerId, "error");
    });

    server.send(
      JSON.stringify({
        type: "welcome",
        selfID: playerId,
        pin,
        role,
        players: this.playerList(),
      })
    );

    this.broadcast(
      {
        type: "roster",
        players: this.playerList(),
      },
      { excludePlayerId: playerId }
    );

    if (role === "join") {
      this.broadcast(
        {
          type: "player_joined",
          playerID: playerId,
        },
        { excludePlayerId: playerId }
      );

      this.sendStoredSnapshotTo(playerId);
    }

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  handleMessage(session, rawData) {
    let message;

    try {
      message = typeof rawData === "string" ? JSON.parse(rawData) : JSON.parse(new TextDecoder().decode(rawData));
    } catch {
      this.sendTo(session.id, { type: "error", message: "Malformed message" });
      return;
    }

    switch (message.type) {
      case "state_update":
        this.storeSnapshot(session, message.snapshot);
        break;
      case "relay":
        this.forwardRelay(session, message);
        break;
      case "kick":
        this.kickPlayer(session, message.playerID);
        break;
      case "end_lobby":
        this.endLobby(session);
        break;
      default:
        this.sendTo(session.id, { type: "error", message: `Unknown message type: ${message.type}` });
    }
  }

  forwardRelay(session, message) {
    if (message.event?.type === "snapshotRequested") {
      if (this.sendStoredSnapshotTo(session.id)) {
        return;
      }
    }

    if (session.role === "host" && message.event?.type === "stateSnapshot" && message.event.snapshot) {
      this.latestSnapshot = message.event.snapshot;
    }

    const payload = {
      type: "relay",
      fromPlayerID: session.id,
      event: message.event,
    };

    if (message.targetPlayerID) {
      this.sendTo(message.targetPlayerID, payload);
      return;
    }

    this.broadcast(payload, { excludePlayerId: session.id });
  }

  storeSnapshot(session, snapshot) {
    if (session.role !== "host") {
      this.sendTo(session.id, { type: "error", message: "Only the host can upload board state" });
      return;
    }

    if (!snapshot) {
      this.sendTo(session.id, { type: "error", message: "Missing snapshot payload" });
      return;
    }

    this.latestSnapshot = snapshot;
  }

  kickPlayer(session, targetPlayerId) {
    if (session.role !== "host") {
      this.sendTo(session.id, { type: "error", message: "Only the host can kick players" });
      return;
    }

    const target = this.sessions.get(targetPlayerId);
    if (!target || target.role === "host") {
      return;
    }

    this.sendTo(targetPlayerId, { type: "kicked" });
    target.socket.close(4002, "kicked");
    this.removeSession(targetPlayerId, "kicked");
  }

  endLobby(session) {
    if (session.role !== "host") {
      this.sendTo(session.id, { type: "error", message: "Only the host can end the lobby" });
      return;
    }

    this.latestSnapshot = null;
    for (const [playerId, entry] of this.sessions.entries()) {
      this.sendTo(playerId, { type: "lobby_ended" });
      entry.socket.close(4003, "lobby ended");
    }

    this.sessions.clear();
  }

  removeSession(playerId, reason) {
    const removed = this.sessions.get(playerId);
    if (!removed) {
      return;
    }

    const wasHost = removed.role === "host";
    this.sessions.delete(playerId);

    if (wasHost && reason !== "kicked") {
      this.latestSnapshot = null;
      for (const [remainingId, session] of this.sessions.entries()) {
        this.sendTo(remainingId, { type: "lobby_ended" });
        session.socket.close(4004, "host disconnected");
      }
      this.sessions.clear();
      return;
    }

    this.broadcast({
      type: "roster",
      players: this.playerList(),
    });
  }

  playerList() {
    return [...this.sessions.values()]
      .sort((left, right) => left.joinedAt - right.joinedAt)
      .map((session) => ({
        id: session.id,
        role: session.role,
        color: session.color,
        joinedAt: session.joinedAt,
      }));
  }

  broadcast(message, options = {}) {
    const encoded = JSON.stringify(message);
    const excludePlayerId = options.excludePlayerId;

    for (const [playerId, session] of this.sessions.entries()) {
      if (playerId === excludePlayerId) {
        continue;
      }

      try {
        session.socket.send(encoded);
      } catch {
        this.sessions.delete(playerId);
      }
    }
  }

  sendTo(playerId, message) {
    const target = this.sessions.get(playerId);
    if (!target) {
      return;
    }

    try {
      target.socket.send(JSON.stringify(message));
    } catch {
      this.sessions.delete(playerId);
    }
  }

  sendStoredSnapshotTo(playerId) {
    const host = this.currentHost();
    if (!host || !this.latestSnapshot) {
      return false;
    }

    this.sendTo(playerId, {
      type: "relay",
      fromPlayerID: host.id,
      event: {
        type: "stateSnapshot",
        snapshot: this.latestSnapshot,
      },
    });
    return true;
  }

  currentHost() {
    return [...this.sessions.values()].find((session) => session.role === "host") ?? null;
  }

  nextAvailableColor() {
    const used = new Set([...this.sessions.values()].map((session) => session.color));
    const available = PLAYER_COLORS.filter((color) => !used.has(color));
    if (available.length === 0) {
      return null;
    }

    const index = Math.floor(Math.random() * available.length);
    return available[index];
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);

    if (url.pathname === "/health") {
      return json({ ok: true });
    }

    if (request.headers.get("Upgrade") !== "websocket") {
      return json({ error: "Expected websocket request" }, 400);
    }

    const match = url.pathname.match(/^\/connect\/([A-Z0-9-]+)$/);
    if (!match) {
      return json({ error: "Unknown route" }, 404);
    }

    const pin = match[1];
    const objectId = env.LOBBY_RELAY.idFromName(pin);
    const stub = env.LOBBY_RELAY.get(objectId);
    const relayUrl = new URL(request.url);
    relayUrl.pathname = "/relay";
    relayUrl.searchParams.set("pin", pin);

    return stub.fetch(relayUrl, request);
  },
};

function json(value, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
    },
  });
}
