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

**MVP complete + go-libp2p interop proven** — Phases 0–4, **39 tests green**.
`starling` is a working libp2p node: it holds a real conversation over TCP with
mutual Peer-ID authentication, a **ping (~0.3 ms RTT)**, and an Identify exchange —
both starling↔starling *and* against a real **go-libp2p** node, in both directions
(see [`interop/`](interop/README.md)).

The MVP stack is `TCP → multistream-select 1.0.0 → Noise XX → Yamux → ping + Identify`
(no TLS, mplex, or QUIC — those are deliberately out of scope). Every wire format is
built to spec and now confirmed on the wire against the reference implementation.

## Try it

```sh
opam switch create . ocaml-base-compiler.5.2.0   # local switch (first time)
opam install --deps-only .
dune build
dune runtest                                      # 39 tests, all green
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

Both `listen` and `dial` use a **persistent host identity**: the Ed25519 seed is
loaded from `$STARLING_IDENTITY` (default `~/.starling/identity.key`, mode `0600`),
or minted and saved on first run — so a node keeps the same Peer ID across restarts.
Set `$STARLING_LOG` (`debug` | `info` | `warning` | `error` | `quiet`, default
`info`) to control the node's structured log output.

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
| Security | `Noise_*`, `Noise` | hand-rolled `Noise_XX_25519_ChaChaPoly_SHA256`; AEAD verified vs **RFC 8439**, full handshake pinned to a **flynn/noise** cross-impl vector; mutual Peer-ID auth |
| Encrypted channel | `Secure_flow` | the Noise transport as a custom `Eio.Flow.two_way` — every higher layer composes over it |
| Multiplexing | `Yamux` | 12-byte frames, SYN/ACK/FIN/RST, 256 KiB window with **consumption-driven backpressure**, **keep-alive** ping (reaps dead peers), daemon read-loop; **streams are Eio flows** |
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

go-libp2p interop is done. **Production hardening** is underway — connection-failure
isolation, persistent host identity, handshake timeouts + a connection cap, real
Yamux backpressure, yamux keep-alive (reaps silent peers), a clean constant-time
review ([`SECURITY.md`](SECURITY.md)), and structured logging + yamux `GoAway`
graceful close are in; metrics + signal-driven shutdown and secret zeroization (a
documented runtime limitation) remain. After that: rust/nim interop, then growth
protocols — Identify push, Kademlia DHT (`/ipfs/kad`), GossipSub (`/meshsub`).
See [`ROADMAP.md`](ROADMAP.md).

## License

MIT
