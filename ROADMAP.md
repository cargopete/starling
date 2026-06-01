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

## Phase 1 — TCP + multistream-select (next)

- [ ] Eio TCP dial / listen (`Transport`)
- [ ] `Multistream` — `<varint-len>msg\n` framing, header exchange, propose/`na`
- [ ] Milestone: exchange `/multistream/1.0.0` with a local go-libp2p node; propose
      `/noise`, read the acceptance (handshake then fails — negotiation proven)

## Phase 2 — Noise XX (the hard part)

- [ ] `Noise.Symmetric_state` / `Cipher_state` on mirage-crypto (X25519, ChaCha20
      **12-byte IETF nonce**, digestif SHA-256, hand-rolled HKDF)
- [ ] XX message state machine (`-> e` / `<- e,ee,s,es` / `-> s,se`)
- [ ] `NoiseHandshakePayload` proto2 (ocaml-protoc-plugin); static-key signature
      over `"noise-libp2p-static-key:" || static_pub`; Peer ID verification
- [ ] Milestone: pass Noise test vectors; complete XX vs local go-libp2p; decrypt
      both directions. Top debug checks: nonce mode, AAD = `h`, signature bytes.

## Phase 3 — Yamux

- [ ] 12-byte frame codec; SYN/ACK/FIN/RST; 256 KiB window + WindowUpdate
      (accept larger peer windows)
- [ ] Eio read-loop/demux fiber; `open_stream` / `accept_stream`
- [ ] Milestone: negotiate `/yamux/1.0.0` over Noise vs go-libp2p; open a stream,
      observe the ACK

## Phase 4 — ping + Identify = MVP DONE

- [ ] Per-stream multistream-select dispatch
- [ ] `ping` (`/ipfs/ping/1.0.0`) — 32-byte echo, dial + respond
- [ ] `identify` (`/ipfs/id/1.0.0`) — respond minimal, parse peer's
- [ ] **Definition of done:** dial a real go-libp2p ping node, full handshake,
      ping echo + RTT, parse Identify. Repeat vs rust-libp2p, nim-libp2p.

## Growth (post-MVP)

- [ ] Identify push + signed peer records + early muxer negotiation
- [ ] Kademlia DHT `/ipfs/kad/1.0.0` (needs RSA for IPFS bootstrap)
- [ ] GossipSub v1.1 `/meshsub/1.1.0`
- [ ] QUIC `/quic-v1` (heaviest lift; likely C bindings)
- [ ] Circuit Relay v2 + DCUtR hole punching
- [ ] Plug into `libp2p/test-plans` (`unified-testing`) interop harness
- [ ] ~~mplex~~ — skipped (no flow control, deprecated)
