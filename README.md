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

**Phases 0–1 complete** (17 tests green). Foundation + connectivity:

- ✅ `Varint` — unsigned-varint (LEB128), with spec vectors
- ✅ `Base58` — base58btc, anchored on the `"Hello World!" → 2NEpo7TZRRrLZSi2U` vector
- ✅ `Multihash` — identity + sha2-256
- ✅ `Multiaddr` — `/ip4` `/ip6` `/tcp` `/p2p`, string ↔ binary
- ✅ `Keys` — Ed25519 keypairs (mirage-crypto-ec)
- ✅ `Peer_id` — `PublicKey` protobuf → identity multihash → base58btc
- ✅ `Transport` — Eio TCP dial (multiaddr → socket)
- ✅ `Multistream` — multistream-select 1.0.0 (framing, propose/accept/`na`),
  tested over Eio socketpairs and real loopback TCP

**Next:** Phase 2 — Noise XX (the hard part). See [`ROADMAP.md`](ROADMAP.md).

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
