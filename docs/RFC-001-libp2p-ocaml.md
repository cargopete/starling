# RFC-001: A Native libp2p Node in OCaml — Phased Implementation Specification

> This is the canonical spec for **starling**. The MVP target and all wire-format
> details below are authoritative; deviate only with a documented reason.

## TL;DR
- **Build it; the gap is real.** As of mid-2026 there is no native OCaml libp2p
  implementation (only Mina's out-of-process Go `libp2p_helper` shim and a stalled
  2019 devgrant proposal to wrap Go via C). The OCaml ecosystem now has every
  primitive needed: Eio 1.2 (stable TCP), mirage-crypto/mirage-crypto-ec (X25519 +
  ChaCha20-Poly1305), digestif (SHA-256/HMAC), and ocaml-protoc-plugin (proto2).
- **MVP scope:** **TCP → multistream-select 1.0.0 → Noise XX → Yamux → Identify + ping.**
  Do **not** add TLS, mplex, or QUIC for the MVP.
- **"Done" =** dial a real go-libp2p ping node, complete the
  `Noise_XX_25519_ChaChaPoly_SHA256` handshake, negotiate Yamux, open a stream,
  exchange one 32-byte ping echo, and run Identify.
- **Effort:** ~6–9 focused weeks to MVP. Noise and Yamux flow-control are the two
  hardest parts.

## Concurrency / IO: Eio (not Lwt)
- A muxer is inherently concurrent (N streams over one connection). Eio's structured
  concurrency (`Switch`, `Fiber.both`, `Fiber.fork`) models "spawn a fiber per stream,
  scoped to the connection's switch" cleanly, and **backtraces work** through fibers.
- Direct style means the Noise state machine and Yamux loop read like synchronous code.
- `Eio.Buf_read` / `Eio.Buf_write` give buffered, length-prefix-friendly framing
  (raw flow reads return packet-sized chunks, not message-sized).
- Caveat: thread `net`, `sw`, `clock` from `env` (capability passing). `tls-eio` is
  precedent for a security layer over Eio flows; `lwt_eio` exists if interop is needed.

## Crypto: mirage-crypto (mind the API breaks)
- **X25519 ECDH**: `Mirage_crypto_ec.X25519`, `key_exchange : secret -> public -> (shared, error) result`.
  RFC 7748 behavior (all-zero output for invalid points) matches Noise §12.1.
- **ChaCha20-Poly1305 AEAD**: `Mirage_crypto.Chacha20` via `Mirage_crypto.AEAD`.
  **Critical: pass a 12-byte nonce to select IETF/RFC 8439 mode** (96-bit nonce,
  32-bit counter). A 64-bit nonce selects DJB legacy mode and will NOT interop.
- **SHA-256 + HMAC**: **digestif** (`Digestif.SHA256.digest_string`, `hmac_string`).
  mirage-crypto's `Hash` module was removed at v1.0.0 — do not use it.
- **HKDF**: hand-roll the 3-line HMAC chain per Noise §4.3 for byte-exact behavior.
- **API caveat**: mirage-crypto switched `Cstruct.t` → `string`/`bytes` at v1.0.0
  (latest 2.0.2). Pin one major and confirm labels against odoc.
- **Do NOT use the `noise` opam package** ("not ready for primetime… no side-channel
  countermeasures" — author's own words). Hand-roll Noise on mirage-crypto; read
  `ocaml-noise` only as a structural reference.

## Protobuf, multiformats, utility libraries
- **Protobuf**: `ocaml-protoc-plugin` (5.0.0). Full **proto2** support — required,
  every libp2p schema is `syntax = "proto2"`. Integrate via a dune `rule` calling protoc.
- **base58**: Bitcoin alphabet for Peer IDs.
- **varint, multiaddr, multihash, multibase**: **hand-rolled** (small; no maintained
  OCaml lib). Implement exactly the subset needed: `/ip4`, `/tcp`, `/p2p`; identity +
  sha2-256 multihash; base58btc.

## Interop targets & gotchas
- Test against **go-libp2p first** (flagship, most forgiving), then rust-libp2p, then nim-libp2p.
- go-libp2p ping example prints a dialable `/ip4/.../tcp/PORT/p2p/Qm...` address.
- nim-libp2p `noise.nim` constants to match: `ProtocolXXName = "Noise_XX_25519_ChaChaPoly_SHA256"`,
  `PayloadString = "noise-libp2p-static-key:"`, `NoiseCodec = "/noise"`.
- **Do NOT implement early muxer negotiation** (NoiseExtensions.stream_muxers) for the
  MVP — leave `extensions` empty; peers fall back to negotiating `/yamux/1.0.0` over
  multistream-select on the encrypted channel.
- **ChaCha20 nonce must be 12-byte IETF**, **AAD = current `h`** during the handshake,
  and the **static-key signature** is over `"noise-libp2p-static-key:" || noise_static_pubkey`.
  These three are the top interop failure points.
- Peer ID verification: `identity_sig` must verify as `identity_key` over the prefixed
  static key; on failure, **terminate**.

## Wire-format reference (implement exactly)

### 1. multistream-select 1.0.0
Each message is `<varint-length><utf8-bytes>\n` (length includes the `\n`). Opening
header: the 19 bytes `0x13 /multistream/1.0.0\n`. Select: dialer sends `<varint>/noise\n`;
listener echoes verbatim to accept or sends `0x03 na\n` to reject. `ls\n` not required.
Negotiation runs three times: security (`/noise`), muxer (`/yamux/1.0.0`) over the
encrypted channel, then per-stream (`/ipfs/ping/1.0.0`, `/ipfs/id/1.0.0`).

### 2. Noise XX (`Noise_XX_25519_ChaChaPoly_SHA256`, protocol ID `/noise`)
HASHLEN=32, DHLEN=32, BLOCKLEN=64. Pattern:
```
XX:
  -> e
  <- e, ee, s, es
  -> s, se
```
SymmetricState (Noise spec rev. 34, §5):
- **InitializeSymmetric**: protocol name `Noise_XX_25519_ChaChaPoly_SHA256` is
  **exactly 32 ASCII bytes**, so `h` = the name verbatim (≤ 32 ⇒ right-pad with
  0x00 to 32; here no padding is needed). NOT hashed. `ck = h`; `k = empty`.
  Then `MixHash(prologue)` with empty prologue.
- **MixHash(data)**: `h = SHA256(h || data)`.
- **MixKey(ikm)**: `ck, temp_k = HKDF(ck, ikm, 2)`; `k = temp_k`, `n = 0`.
  HKDF (RFC 5869, salt=ck, zero-length info): `temp = HMAC(ck, ikm)`;
  `out1 = HMAC(temp, 0x01)`; `out2 = HMAC(temp, out1||0x02)`; (`out3 = HMAC(temp, out2||0x03)`).
- **EncryptAndHash(pt)**: `ct = AEAD(k, n, ad=h, pt)`; `n++`; `MixHash(ct)`. If `k` empty, `ct = pt`.
- **DecryptAndHash(ct)**: AAD = current `h`; MixHash the *ciphertext*.
- **Nonce**: 12 bytes = `0x00000000 || little-endian-uint64(n)`. Resets to 0 on MixKey.
- **DH**: `X25519.key_exchange`, then MixKey the 32-byte shared secret.
- **Split()**: `temp_k1, temp_k2 = HKDF(ck, "", 2)`. `c1` = initiator→responder,
  `c2` = responder→initiator. **Transport messages use zero-length AAD** (not `h`).

Payload protobuf (proto2): `NoiseHandshakePayload { identity_key=1 bytes;
identity_sig=2 bytes; extensions=4 NoiseExtensions }`. Carried encrypted in XX
messages 2 (responder) and 3 (initiator). Initiator MUST NOT send extensions before
secrecy. MVP: leave `extensions` empty.

Noise wire framing: each message on TCP is `<2-byte big-endian length><noise_message>`,
max 65535 bytes.

### 3. Yamux (`/yamux/1.0.0`)
12-byte header, big-endian: `| Ver(1) | Type(1) | Flags(2) | StreamID(4) | Length(4) |`.
- Version 0. Type: `0x0` Data, `0x1` WindowUpdate, `0x2` Ping, `0x3` GoAway.
- Flags: `0x1` SYN, `0x2` ACK, `0x4` FIN, `0x8` RST.
- StreamID: client (connection initiator) **odd**, server **even**; ID 0 = session ping/goaway.
- Data: Length = payload bytes. WindowUpdate: Length = window delta. Ping: Length =
  opaque value. GoAway: Length = error code (0 normal, 1 protocol, 2 internal).
- **Flow control**: each stream starts with a **256 KiB** window; no session window.
  Send WindowUpdate frames as you drain the receive buffer. **Accept** peer windows
  larger than 256 KiB (go-yamux uses up to 16 MiB). Open a stream: Data/WindowUpdate
  with a new StreamID + SYN; peer replies ACK (or RST). Data may follow SYN immediately.

### 4. Identify (`/ipfs/id/1.0.0`)
Responder sends one length-prefixed (protobuf-varint length) `Identify` and closes:
```protobuf
syntax = "proto2";
message Identify {
  optional string protocolVersion = 5;
  optional string agentVersion = 6;
  optional bytes publicKey = 1;
  repeated bytes listenAddrs = 2;
  optional bytes observedAddr = 4;
  repeated string protocols = 3;
}
```
`maxOwnIdentifyMsgSize = 4 KiB`. MVP: respond minimal, parse peer's. Push variant out of scope.

### 5. ping (`/ipfs/ping/1.0.0`)
`PingSize = 32`. Dialer writes 32 random bytes; responder echoes exactly; dialer
verifies equality and measures RTT. Not ICMP. go-libp2p `pingTimeout` 10s.

### 6. Peer ID derivation
1. `PublicKey` protobuf `{ Type = Ed25519 (1); Data = <32-byte raw pubkey> }`, serialized.
2. Serialized Ed25519 key is ~36 bytes ≤ 42 → wrap in **identity multihash**
   (code `0x00`, varint length, bytes — no hashing). If > 42 (RSA) → sha2-256 multihash
   (`0x12 0x20 <sha256>`).
3. Text = **base58btc** of the multihash (no multibase prefix) → `12D3Koo...` for Ed25519.
   MUST support Ed25519; RSA only for IPFS DHT bootstrap; others optional.

### 7. multiaddr (binary)
`(<varint protocol code><value>)+`. Codes: `/ip4` = `0x04` (4 bytes), `/tcp` = `0x06`
(2-byte BE port), `/p2p` = `0x01A5` (421; varint-length-prefixed multihash).
Example: `/ip4/127.0.0.1/tcp/4001` = `04 7f000001 06 0fa1`.

## Module architecture (see `lib/`)
```
TRANSPORT  : dial/listen → raw duplex CONN              (TCP via Eio)
SECURE     : raw CONN → encrypted flow + verified PeerId (Noise XX)
MUXER      : encrypted flow → many streams              (Yamux)
PROTOCOL   : runs over one negotiated stream            (ping, identify)
```
Upgrade flow: `raw --(ms:/noise)--> Noise.secure_* --> secured --(ms:/yamux)-->
Yamux.client/server --> session`. Each new stream → multistream-select → `PROTOCOL`.
A `Swarm`/`Host` owns the keypair, transport, protocol handler table, and live sessions.

Concurrency (Eio): one `Switch` per connection; a fiber loops reading Yamux frames and
demuxes to per-stream queues; one fiber per accepted stream runs its handler;
`open_stream` allocates a StreamID and writes SYN. Stream table guarded by `Eio.Mutex`.
Cancellation propagates through the switch on close.

Errors: `result` for expected protocol outcomes (`Bad_signature`, multistream
`Unsupported`); exceptions for IO faults (Eio raises `Eio.Io`, backtraces work). On
fatal stream error send Yamux RST; on session error send GoAway.

## Phased plan
| Phase | Scope | Estimate | Milestone |
|---|---|---|---|
| **0** | multiformats (varint, multihash, base58btc, multiaddr), keys (Ed25519), Peer ID | ~1 wk | derive Peer ID from a fixed Ed25519 key == known `12D3Koo...`; multiaddr str↔bin round-trip |
| **1** | TCP + multistream-select | 0.5–1 wk | exchange `/multistream/1.0.0` headers with go-libp2p; propose `/noise`, read acceptance |
| **2** | Noise XX (the hard part) | 2–3 wks | pass Noise test vectors; complete XX handshake vs local go-libp2p; decrypt both directions |
| **3** | Yamux | 1.5–2 wks | negotiate `/yamux/1.0.0` over Noise vs go-libp2p; open a stream, observe ACK |
| **4** | ping + Identify (MVP DONE) | ~1 wk | dial real go-libp2p, full handshake, ping 32-byte echo + RTT, parse Identify |

## Growth (post-MVP, lower resolution)
- Identify push + signed peer records + early muxer negotiation (~1 wk)
- Kademlia DHT `/ipfs/kad/1.0.0` (~4–6 wks; needs RSA for IPFS bootstrap) — largest item
- GossipSub v1.1 `/meshsub/1.1.0` (~3–5 wks)
- QUIC `/quic-v1` (~4–8 wks; no mature pure-OCaml QUIC — heaviest lift, likely C bindings)
- Circuit Relay v2 + DCUtR hole punching (~3–4 wks)
- **mplex**: skip — no flow control, being deprecated.

## Pinned decisions
- OCaml ≥ 5.1; Eio 1.2 / eio_main 1.3; a single mirage-crypto major (string API).
- Hand-roll: varint, multihash, base58btc, multiaddr, Noise (incl. HKDF).
- Use libs: mirage-crypto(+ec,+rng,+rng-eio), digestif, ocaml-protoc-plugin, base58, eio_main.
- Defer: early-muxer-negotiation, signed peer records, mplex, TLS, QUIC.
- Top three Noise debug checks if interop fails: (a) 12-byte IETF ChaCha nonce,
  (b) AAD = `h` during handshake, (c) signature over the correct prefixed bytes.
  Yamux hang ⇒ missing WindowUpdates as you drain the receive buffer.
- Plug into `libp2p/test-plans` (`unified-testing`) only **after** the manual MVP passes.
