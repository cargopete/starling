# Security notes

starling hand-rolls the libp2p **Noise XX** security handshake on top of
[mirage-crypto](https://github.com/mirage/mirage-crypto) primitives. This
document records the security posture honestly — what is guaranteed, what is
delegated, and what is a known limitation — so a reviewer need not reverse-
engineer it from the source.

## What the channel provides

After a successful upgrade the connection has:

- **Confidentiality + integrity** — ChaCha20-Poly1305 AEAD on every transport
  frame (`Noise_cipher_state`).
- **Mutual authentication** — each peer signs its Noise static public key with
  its Ed25519 identity key (`"noise-libp2p-static-key:" ‖ static_pub`); the
  remote Peer ID is recovered from, and verified against, that signature
  (`Noise.verify_payload`). A Peer ID mismatch aborts the handshake.
- **Forward secrecy** — the XX pattern mixes per-connection ephemeral keys
  (`ee`, `es`, `se`); a fresh X25519 ephemeral is generated per connection and
  is never persisted.

## Constant-time posture

Every operation whose timing could leak secret material is delegated to
mirage-crypto, whose primitives are written to run in constant time:

| Operation | Owner |
|---|---|
| AEAD encrypt / **tag verification** | `Mirage_crypto.Chacha20.authenticate_{encrypt,decrypt}` |
| Ed25519 sign / **signature verify** | `Mirage_crypto_ec.Ed25519` |
| X25519 DH | `Mirage_crypto_ec.X25519` |
| HKDF / HMAC-SHA256 | `digestif` (via `Noise_hkdf`) |

starling's own code performs **no variable-time comparison on secret, tag, or
signature material**. The only equality checks in the library are on public
values — multistream protocol strings, Peer IDs, the ping echo nonce — and on
buffer lengths. In particular, the AEAD tag is never compared by hand; a forged
tag is rejected inside `authenticate_decrypt`, which returns an error that
`Noise_cipher_state.decrypt_with_ad` propagates.

## Validation

The hand-rolled crypto is checked against external references, both offline and
on the wire:

- **RFC 8439** — the ChaCha20-Poly1305 AEAD is pinned to the §2.8.2 test vector.
- **flynn/noise cross-impl vector** — the full XX handshake (msg1/2/3, the
  channel-binding hash, and the first transport message) is pinned byte-for-byte
  to a vector produced by flynn/noise, the Noise library go-libp2p uses.
  Regenerate with `interop/starling-interop noisekat`.
- **Live go-libp2p interop** — starling completes the handshake with a real
  go-libp2p node in both directions (see `interop/`).

## Known limitation: secret zeroization

starling does **not** reliably wipe secret key material from memory after use,
and on the OCaml runtime it largely cannot:

- Secrets derived through mirage-crypto (Ed25519 / X25519 keys, cipher keys) are
  held in **opaque types** that expose no zeroization hook.
- Other secret bytes (the persisted identity seed, the Noise chaining key and
  symmetric-state keys) live in **immutable `string`s**, which cannot be
  overwritten in place.
- The **moving, copying garbage collector** may duplicate any of the above, so
  even wiping a mutable buffer would be best-effort rather than a guarantee.

Adding wipe calls would therefore be security theatre under the current runtime.
This is tracked as an open item in [`ROADMAP.md`](ROADMAP.md); a real fix needs
support from the underlying crypto library (secret types backed by wipeable,
GC-pinned buffers) rather than application-level code.

## Reporting

This is pre-1.0 research software and has not had an external audit. Do not use
it to protect anything that matters yet. Security issues can be raised on the
[issue tracker](https://github.com/cargopete/starling/issues).
