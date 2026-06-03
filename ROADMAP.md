# Roadmap

MVP: `TCP → multistream-select → Noise XX → Yamux → Identify + ping`.
Full wire-format detail in [`docs/RFC-001-libp2p-ocaml.md`](docs/RFC-001-libp2p-ocaml.md).

## Phase 0 — multiformats & identity ✅ (done)

- [x] `Varint` — unsigned-varint (LEB128) encode/decode/read, spec vectors
- [x] `Base58` — base58btc encode/decode (`"Hello World!" → 2NEpo7TZRRrLZSi2U`)
- [x] `Multihash` — identity (0x00) + sha2-256 (0x12)
- [x] `Multiaddr` — `/ip4` `/ip6` `/tcp` `/p2p`, string ↔ binary round-trip
- [x] `Keys` — Ed25519 (mirage-crypto-ec): of_seed, generate, sign, verify
- [x] `Peer_id` — marshalled `PublicKey` protobuf → identity multihash → base58btc
- [x] Alcotest suite (12 tests), Peer ID renders `12D3Koo...`
- [ ] _Follow-up:_ pin an external Ed25519 seed→PeerID vector from a reference impl

## Phase 1 — TCP + multistream-select ✅ (done)

- [x] Eio TCP dial (`Transport.connect`) — multiaddr → loopback/real socket
- [x] `Multistream` — `<varint-len>msg\n` framing, header exchange, propose/`na`,
      dialer + listener
- [x] Tests: negotiation success / second-choice / `na` / framing over Eio
      socketpairs, plus an end-to-end self-dial over real loopback TCP
- [x] `starling dial <multiaddr>` CLI subcommand (proposes `/noise`)
- [ ] _Manual milestone:_ run a local go-libp2p ping node and confirm
      `starling dial` exchanges `/multistream/1.0.0` and reads the `/noise`
      acceptance (handshake then fails — negotiation proven). Needs Go installed.

## Phase 2 — Noise XX (the hard part) — _in progress_

Sitting 1 — pure primitives ✅ (done):
- [x] `Noise_cipher_state` — ChaCha20-Poly1305, **12-byte IETF nonce**, pass-through
      before first key. Verified against the **RFC 8439 §2.8.2** AEAD vector.
- [x] `Noise_hkdf` — Noise §4.3 HMAC-SHA256 chain (hkdf2 / hkdf3)
- [x] `Noise_symmetric_state` — initialize / mix_hash / mix_key / encrypt_and_hash /
      decrypt_and_hash / split. Two-party round-trip + transport split verified.

Sitting 2 — the live handshake ✅ (done):
- [x] `Noise_dh` — X25519 wrapper (gen ephemeral, load static, DH)
- [x] `Pbuf` — minimal proto2 helper; `Noise_payload` (`NoiseHandshakePayload`)
- [x] `Noise_handshake` — XX state machine (`-> e` / `<- e,ee,s,es` / `-> s,se`),
      pure step functions (deterministic, vector-ready)
- [x] `Noise` driver — static-key signature over `"noise-libp2p-static-key:" ‖
      static_pub`, mutual Peer-ID verification, 2-byte-BE transport framing over Eio
- [x] Tests: in-memory fixed-key handshake + live handshake over a socket pair
      (mutual auth, channel-binding agreement, bidirectional transport)
- [x] `starling dial` runs `/noise` + handshake and prints the remote Peer ID
- [ ] _Manual milestone:_ full XX vs a real go-libp2p node (needs Go). Optional:
      pin a published XX test vector for a stricter offline wire check.

## Phase 3 — Yamux ✅ (done)

- [x] `Secure_flow` — the Noise transport as a custom `Eio.Flow.two_way` (so
      `Buf_read`/`Buf_write`, `Multistream`, and `Yamux` compose over it)
- [x] `Yamux` — 12-byte frame codec; SYN/ACK/FIN/RST; 256 KiB window + immediate
      WindowUpdate replenish; daemon read-loop demuxing to per-stream queues
- [x] Streams are themselves `Eio.Flow.two_way`; `open_stream` / `accept_stream`
- [x] Tests: codec, plain stream exchange, 100 KB chunked+flow-controlled payload,
      and the **full stack** (Noise → Secure_flow → `/yamux` negotiation → stream
      round-trip over a socket pair)
- [x] `starling dial` now runs Noise → `/yamux` and brings the muxer up
- [x] _Manual milestone:_ open a stream against a real go-libp2p node, observe the
      ACK — done via the [`interop/`](interop/README.md) harness. (The read-side
      "replenish on arrival" simplification is now resolved — see **Hardening**.)

## Phase 4 — ping + Identify = MVP ✅ (done)

- [x] `Upgrade` — the full client/server upgrade (TCP → Noise → `/yamux`) as a
      continuation; `Host` — per-stream multistream dispatch to handlers
- [x] `Ping` (`/ipfs/ping/1.0.0`) — 32-byte echo, dial (with RTT) + respond
- [x] `Identify` (`/ipfs/id/1.0.0`) — encode/decode, respond + request, peer-id recovery
- [x] CLI: `starling listen <port>` (serve ping+identify) and `starling dial <ma>`
      (upgrade, ping with RTT, fetch identify)
- [x] Proven **starling ↔ starling** over real TCP: mutual auth, `ping ~1.6 ms`,
      identify exchange. MVP test green in CI.
- [x] **Definition-of-done — go-libp2p interop, both directions** (see
      [`interop/`](interop/README.md)). starling dials go-libp2p (Noise XX +
      mutual auth, `/yamux`, ping ~0.3 ms, reads go's identify); go-libp2p dials
      starling (ping ~0.3 ms). This surfaced and fixed a real gap: the upgrade
      skipped the multistream-select `/noise` step (starling↔starling worked only
      because both ends skipped it symmetrically) — go-libp2p requires it.
- [ ] rust/nim interop — same harness, other implementations.

## Hardening — towards production — _in progress_

- [x] **Connection-failure isolation** — a peer reset / transport fault tears down
      only that connection (per-connection switches via `Eio.Net.run_server`; the
      Yamux read loop closes the muxer and wakes blocked readers + `accept_stream`
      instead of propagating). One peer can no longer fell the node.
- [x] **Persistent host identity** — `Identity_store`: stable Peer ID across
      restarts, seed at `$STARLING_IDENTITY` / `~/.starling/identity.key`, `0600`.
- [x] **Handshake timeout + connection cap** — every negotiation/handshake step
      runs under a disarm-able deadline (`Eio.Fiber.first` races the work against
      a sleeper; default 15 s), so a peer that connects and stalls no longer pins
      a fiber + fd. `listen` caps concurrency at `max_connections:256`.
- [ ] **Idle timeout** — reap an established connection that goes silent
      (needs per-connection last-activity tracking; pairs with keep-alive below).
- [x] **Yamux backpressure** — the receive window is now replenished on
      *consumption* (`stream_single_read`), not on arrival, so a slow reader
      throttles the sender instead of letting `incoming` grow unbounded.
      WindowUpdates batch at half the window; tested with a 1 MB cross-window
      transfer and an unread-writer stall.
- [ ] **Liveness** — periodic keep-alive ping; reap dead connections.
- [ ] **Observability + graceful shutdown** — structured logging, metrics,
      `GoAway` on close; stop swallowing every exception with `with _ -> ()`.
- [ ] **Crypto assurance** — pin a published Noise XX test vector; constant-time
      / zeroize review of the hand-rolled handshake.

## Growth (post-MVP)

- [ ] Identify push + signed peer records + early muxer negotiation
- [ ] Kademlia DHT `/ipfs/kad/1.0.0` (needs RSA for IPFS bootstrap)
- [ ] GossipSub v1.1 `/meshsub/1.1.0`
- [ ] QUIC `/quic-v1` (heaviest lift; likely C bindings)
- [ ] Circuit Relay v2 + DCUtR hole punching
- [ ] Plug into `libp2p/test-plans` (`unified-testing`) interop harness
- [ ] ~~mplex~~ — skipped (no flow control, deprecated)
