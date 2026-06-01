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
mirage-crypto for X25519/ChaCha20-Poly1305, digestif for SHA-256 — so `starling`
fills the gap natively. See [`docs/RFC-001-libp2p-ocaml.md`](docs/RFC-001-libp2p-ocaml.md)
for the full wire-format spec.

## Status

**MVP complete** — Phases 0–4, **31 tests green**. `starling` is a working libp2p
node: two instances hold a real conversation over TCP, with mutual Peer-ID
authentication, a **ping (~1.6 ms RTT)**, and an Identify exchange.

The MVP stack is `TCP → multistream-select 1.0.0 → Noise XX → Yamux → ping + Identify`
(no TLS, mplex, or QUIC — those are deliberately out of scope). The one remaining
"definition of done" is external interop against a real go-libp2p node, which only
needs a Go toolchain to stand one up; every wire format is built to spec.

## Try it

```sh
opam switch create . ocaml-base-compiler.5.2.0   # local switch (first time)
opam install --deps-only .
dune build
dune runtest                                      # 31 tests, all green
```

Run two nodes and have them talk:

```sh
# terminal 1 — a node that serves ping + identify
dune exec starling -- listen 4001
#   starling listening on /ip4/127.0.0.1/tcp/4001/p2p/12D3KooWKCr...

# terminal 2 — dial it, ping it, fetch its identify
dune exec starling -- dial /ip4/127.0.0.1/tcp/4001
#   local peer: 12D3KooWGWZ...
#   established session with 12D3KooWKCr...
#   ping: 1.654 ms
#   identify: agent=starling/0.1.0 protocols=[/ipfs/ping/1.0.0, /ipfs/id/1.0.0]
```

Other subcommands:

```sh
dune exec starling                      # print a Peer ID from a dev seed
dune exec starling -- id <64-hex-seed>  # derive a Peer ID from your own Ed25519 seed
```

## The stack

Each layer is hand-rolled and tested, with external vectors where it counts.

| Layer | Module(s) | Notes |
|---|---|---|
| Multiformats | `Varint`, `Base58`, `Multihash`, `Multiaddr` | unsigned-varint; base58btc anchored on `"Hello World!" → 2NEpo7TZRRrLZSi2U`; `/ip4 /ip6 /tcp /p2p` |
| Identity | `Keys`, `Peer_id` | Ed25519 → `PublicKey` protobuf → identity multihash → base58btc (`12D3Koo…`) |
| Transport | `Transport` | Eio TCP dial (multiaddr → socket) |
| Negotiation | `Multistream` | multistream-select 1.0.0 |
| Security | `Noise_*`, `Noise` | hand-rolled `Noise_XX_25519_ChaChaPoly_SHA256`; AEAD verified vs **RFC 8439**; mutual Peer-ID auth |
| Encrypted channel | `Secure_flow` | the Noise transport as a custom `Eio.Flow.two_way` — every higher layer composes over it |
| Multiplexing | `Yamux` | 12-byte frames, SYN/ACK/FIN/RST, 256 KiB window, daemon read-loop; **streams are Eio flows** |
| Upgrade & dispatch | `Upgrade`, `Host` | TCP → Noise → `/yamux`; per-stream protocol routing |
| Protocols | `Ping`, `Identify` | `/ipfs/ping/1.0.0` (32-byte echo + RTT), `/ipfs/id/1.0.0` |

Because the Noise channel and each Yamux stream are both ordinary `Eio.Flow.two_way`
values, the same `Buf_read`/`Buf_write` and `Multistream` code composes at every
level — the layering is literal, not just conceptual.

## Layout

```
docs/   RFC-001 — the canonical wire-format spec
lib/    the library, one module per layer (see the table above)
bin/    the starling CLI — id / listen / dial
test/   Alcotest suites, anchored on external vectors per layer
```

## What's next

External interop against go-libp2p (then rust/nim), then growth protocols —
Identify push, Kademlia DHT (`/ipfs/kad`), GossipSub (`/meshsub`). See
[`ROADMAP.md`](ROADMAP.md).

## License

MIT
