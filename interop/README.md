# Interop harness

A tiny go-libp2p node that speaks starling's exact MVP stack — **Noise** security,
**Yamux** muxer, ping + identify — so we can confirm starling talks to a real
libp2p implementation rather than only to itself.

## Build

```sh
cd interop
go build .          # produces ./starling-interop (gitignored)
```

## starling dials go-libp2p

```sh
# terminal 1 — go node serves ping + identify
./starling-interop listen 4101
#   go-libp2p listening on /ip4/127.0.0.1/tcp/4101/p2p/12D3KooW...

# terminal 2 — starling dials it
dune exec starling -- dial /ip4/127.0.0.1/tcp/4101/p2p/12D3KooW...
#   established session with 12D3KooW...
#   ping: 0.3 ms
#   identify: agent=... protocols=[/ipfs/id/1.0.0, ...]
```

## go-libp2p dials starling

```sh
# terminal 1 — starling listens
dune exec starling -- listen 4001
#   starling listening on /ip4/127.0.0.1/tcp/4001/p2p/12D3KooW...

# terminal 2 — go dials it
./starling-interop dial /ip4/127.0.0.1/tcp/4001/p2p/12D3KooW...
#   connected to 12D3KooW...
#   ping: 300µs
```

Both directions complete the Noise XX handshake with mutual Peer-ID
authentication, negotiate `/yamux/1.0.0`, and exchange `/ipfs/ping/1.0.0`.
The go node version is pinned in `go.mod` / `go.sum`.
