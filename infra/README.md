# Running your own multiplayer infrastructure

Out of the box the game leans on PeerJS's free public services twice: its
**broker** introduces the players to each other (that's how a join code finds
the host), and its shared **TURN relay** carries the game when a player's
network refuses direct browser-to-browser connections (phones on mobile data,
strict office/campus Wi-Fi). Both are best-effort infrastructure, and they're
the usual reason joining a battle feels flaky.

This directory replaces both with your own: one small VPS running

- **peerjs-server** — the broker, behind **Caddy** for automatic HTTPS, and
- **coturn** — the TURN relay,

all via a single `docker compose up`. The game itself stays a static site;
only these two support services run on the server, and only introductions and
relayed-fallback traffic flow through them.

## What you need

- A VPS with a public IPv4 address and Docker installed (any provider;
  the smallest instance is plenty — 1 vCPU / 1 GB).
- A hostname for it, e.g. `mp.yourdomain.com`, with an **A record pointing at
  the VPS's IP**. One hostname serves both the broker and the relay.

## Server setup

1. Put this directory on the VPS (clone the repo, or copy just `infra/`).

2. Configure it:

   ```bash
   cd infra
   cp .env.example .env
   nano .env    # hostname, email, TURN password
   ```

3. Open the firewall (provider security group and/or ufw):

   | Port(s)          | Protocol  | For                          |
   | ---------------- | --------- | ---------------------------- |
   | 80, 443          | TCP       | Caddy (HTTPS for the broker) |
   | 3478             | TCP + UDP | TURN                         |
   | 49152–49400      | UDP       | TURN relay allocations       |

4. Start it:

   ```bash
   docker compose up -d
   ```

5. Verify:

   - **Broker**: `curl https://mp.yourdomain.com` should return a small JSON
     blob naming PeerJS Server. (Give Caddy a minute on first boot to fetch
     the certificate.)
   - **TURN**: open the [WebRTC Trickle ICE tester](https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/),
     add `turn:mp.yourdomain.com:3478` with your username and password, and
     gather candidates — a row of **type `relay`** means the relay works.

## Pointing the game at it

The client reads its endpoints at **build time** from Vite env vars — see
`.env.example` at the repo root. Locally, copy it to `.env.local` (gitignored)
and build; on a hosting platform (Netlify, Vercel, Pages, …), set the same
variables in the site's build settings instead:

```bash
VITE_PEER_HOST=mp.yourdomain.com
VITE_TURN_URL=turn:mp.yourdomain.com:3478?transport=udp,turn:mp.yourdomain.com:3478?transport=tcp
VITE_TURN_USERNAME=nana
VITE_TURN_CREDENTIAL=<the TURN_PASSWORD from infra/.env>
npm run build
```

Unset, each piece falls back to the public PeerJS service independently — so
you can roll out the TURN relay first and the broker later, or vice versa.
After deploying, host a lobby and check the network tab: the signaling
WebSocket should go to `wss://mp.yourdomain.com`.

## Notes

- **The TURN credentials ship in the game's JS bundle**, so anyone who reads
  it can use your relay. That's normal for a static site with no backend;
  the `total-quota`, `user-quota` and `max-bps` flags in the compose file are
  the real guardrails. To rotate the password: edit `infra/.env`,
  `docker compose up -d`, rebuild the site with the new credential.
- **Bandwidth**: only *relayed* games flow through the VPS (most connect
  directly and use it for introductions only), and this game's traffic is
  tiny — scores and tile counts, never boards or letters. A hobby lobby
  won't dent a typical VPS transfer allowance.
- **Managed TURN instead of coturn**: if you'd rather not run the relay,
  services like Metered, Twilio or Cloudflare sell TURN by the GB (several
  have free tiers). Set `VITE_TURN_URL`/`VITE_TURN_USERNAME`/
  `VITE_TURN_CREDENTIAL` to what they give you and drop the `coturn` service
  from the compose file — the broker setup is unchanged.
- **Logs**: `docker compose logs -f peerjs` shows joins hitting the broker;
  `docker compose logs -f coturn` shows relay allocations.
