export class LobbyRelay {
  constructor(state, env) {
    this.state = state;
    this.env = env;
    this.sessions = new Map();
  }

  async fetch(request) {
    if (request.headers.get("Upgrade") !== "websocket") {
      return json(
        {
          error: "Expected websocket upgrade",
        },
        426
      );
    }

    const url = new URL(request.url);
    const role = url.searchParams.get("role") === "host" ? "host" : "join";
    const pin = url.searchParams.get("pin") ?? this.state.id.toString();
    const pair = new WebSocketPair();
    const client = pair[0];
    const server = pair[1];

    server.accept();

    const session = {
      role,
      pin,
    };

    this.sessions.set(server, session);

    server.addEventListener("message", (event) => {
      this.broadcast({
        type: "message",
        from: role,
        payload: event.data,
      });
    });

    const closeSession = () => {
      this.sessions.delete(server);
    };

    server.addEventListener("close", closeSession);
    server.addEventListener("error", closeSession);

    server.send(
      JSON.stringify({
        type: "connected",
        pin,
        role,
        peers: this.sessions.size,
      })
    );

    return new Response(null, {
      status: 101,
      webSocket: client,
    });
  }

  broadcast(message) {
    const encoded = JSON.stringify(message);
    for (const socket of this.sessions.keys()) {
      try {
        socket.send(encoded);
      } catch {
        this.sessions.delete(socket);
      }
    }
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
