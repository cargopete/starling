(** Peer IDs: the multihash of a peer's serialized public key, shown in base58btc.

    For an Ed25519 key the serialized {!marshal_ed25519_pubkey} protobuf is
    36 bytes (<= 42), so per the libp2p spec it is wrapped in an *identity*
    multihash and the key is recoverable from the ID. Such IDs always render
    with the [12D3Koo] prefix. *)

type t

(** The marshalled libp2p [PublicKey] protobuf for a 32-byte raw Ed25519 public
    key: [{ Type = Ed25519 (1); Data = <raw> }]. This is also what goes in the
    Noise handshake payload and Identify. *)
val marshal_ed25519_pubkey : string -> string

(** [of_ed25519_pubkey raw] is the Peer ID for a 32-byte raw Ed25519 public key. *)
val of_ed25519_pubkey : string -> t

(** [ed25519_raw_of_proto bytes] extracts the 32-byte raw Ed25519 key from a
    marshalled [PublicKey] protobuf, if it is a well-formed Ed25519 key. *)
val ed25519_raw_of_proto : string -> string option

(** The underlying multihash. *)
val to_multihash : t -> Multihash.t

(** The binary multihash bytes (as embedded in a [/p2p/...] multiaddr). *)
val to_bytes : t -> string

(** Parse from binary multihash bytes. *)
val of_bytes : string -> t

(** The base58btc textual form, e.g. ["12D3KooW..."]. *)
val to_string : t -> string

(** Parse from the base58btc textual form. *)
val of_string : string -> t

val equal : t -> t -> bool
