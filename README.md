# starling

A **native [libp2p](https://libp2p.io) node in OCaml** — built from scratch on
[Eio](https://github.com/ocaml-multicore/eio), with no Go shim and no C bindings.

> A murmuration of starlings is thousands of birds moving as one with no leader —
> which is peer-to-peer networking rendered in feathers. (Sibling to the
> [`wren`](https://github.com/cargopete/wren) messaging libraries.)

## Why

As of mid-2026 there is **no native OCaml libp2p**. The only OCaml/libp2p contact
points are Mina's out-of-process Go `libp2p_helper` and a stalled 2019 proposal to
wrap Go via C. The ecosystem now has every primitive needed — Eio for IO,
mirage-crypto for X25519/ChaCha20-Poly1305, digestif for SHA-256, ocaml-protoc-plugin
for proto2 — so `starling` fills the gap natively. See
[`docs/RFC-001-libp2p-ocaml.md`](docs/RFC-001-libp2p-ocaml.md) for the full spec.

## MVP target

```
TCP → multistream-select 1.0.0 → Noise XX → Yamux → Identify + ping
```

**Done** = dial a real go-libp2p ping node, complete the
`Noise_XX_25519_ChaChaPoly_SHA256` handshake, negotiate Yamux, open a stream,
exchange one 32-byte ping echo, and run Identify. (No TLS, mplex, or QUIC in the MVP.)

## Status

**Phases 0–3 complete** (30 tests green). Identity, connectivity, an encrypted +
authenticated channel, and stream multiplexing — the whole connection stack:

- ✅ `Varint` — unsigned-varint (LEB128), with spec vectors
- ✅ `Base58` — base58btc, anchored on the `"Hello World!" → 2NEpo7TZRRrLZSi2U` vector
- ✅ `Multihash` — identity + sha2-256
- ✅ `Multiaddr` — `/ip4` `/ip6` `/tcp` `/p2p`, string ↔ binary
- ✅ `Keys` / `Peer_id` — Ed25519 → `PublicKey` protobuf → identity multihash → base58btc
- ✅ `Transport` — Eio TCP dial (multiaddr → socket)
- ✅ `Multistream` — multistream-select 1.0.0, tested over socketpairs and real TCP
- ✅ **Noise XX** (`Noise_XX_25519_ChaChaPoly_SHA256`) — hand-rolled on mirage-crypto:
  - `Noise_cipher_state` (ChaCha20-Poly1305, 12-byte IETF nonce) — verified vs the
    **RFC 8439** AEAD vector
  - `Noise_hkdf`, `Noise_symmetric_state` (CipherState / key schedule / split)
  - `Noise_handshake` — the XX state machine (`-> e` / `<- e,ee,s,es` / `-> s,se`)
  - `Noise` — the Eio driver: full handshake, `NoiseHandshakePayload`, static-key
    signature, mutual **Peer-ID authentication**, 2-byte-BE transport framing
  - tested end-to-end over a real Eio socket pair (both peers authenticate, channel
    bindings agree, transport encrypts both directions)
- ✅ `Secure_flow` — the Noise transport exposed as a custom `Eio.Flow.two_way`, so
  every higher layer composes over it via `Buf_read`/`Buf_write`
- ✅ **Yamux** (`/yamux/1.0.0`) — 12-byte frame codec, SYN/ACK/FIN/RST, 256 KiB
  flow-control window, a daemon read-loop demuxing to per-stream queues; **streams are
  themselves Eio flows**. Tested with a 100 KB chunked payload and the **full stack**
  (Noise → Secure_flow → `/yamux` negotiation → stream round-trip).

`starling dial <multiaddr>` runs the whole client upgrade — TCP → `/noise` handshake
→ `/yamux` — printing the remote Peer ID and bringing the muxer up. (Live go-libp2p
interop is the remaining manual check — needs Go.)

**Next:** Phase 4 — per-stream `multistream-select` dispatch + ping + Identify = MVP.
See [`ROADMAP.md`](ROADMAP.md).

## Quick start

```sh
opam switch create . ocaml-base-compiler.5.2.0   # local switch
opam install --deps-only .
dune build
dune runtest          # 12 tests, all green
dune exec starling    # prints a Peer ID
# -> 12D3KooWK99VoVxNE7XzyBwXEzW7xhK7Gpv85r9F3V3fyKSUKPH5

dune exec starling id <64-hex-seed>   # derive from your own Ed25519 seed
```

## Layout

```
docs/   RFC-001 — the canonical wire-format spec
lib/    the library (varint, base58, multihash, multiaddr, keys, peer_id, …)
bin/    the starling CLI (grows into dial/listen)
test/   Alcotest suite, anchored on external vectors per layer
```

## License

MIT
