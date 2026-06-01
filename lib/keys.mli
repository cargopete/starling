(** Ed25519 identity keypairs (the libp2p host identity).

    Ed25519 is the MUST-support key type; we start there. The private key is a
    32-byte seed, so {!of_seed} gives deterministic keypairs for tests. *)

type t

(** [of_seed seed] derives a keypair from a 32-byte seed. Raises
    [Invalid_argument] unless [seed] is exactly 32 bytes and a valid scalar. *)
val of_seed : string -> t

(** [generate ()] makes a fresh random keypair. Requires the mirage-crypto RNG
    to have been seeded (e.g. via [Mirage_crypto_rng_eio.run] or the unix RNG). *)
val generate : ?g:Mirage_crypto_rng.g -> unit -> t

(** The 32-byte raw Ed25519 public key. *)
val public_key_raw : t -> string

(** The 32-byte raw Ed25519 private seed. *)
val private_key_raw : t -> string

(** The marshalled libp2p [PublicKey] protobuf (for handshake / Identify). *)
val public_key_proto : t -> string

(** This host's Peer ID. *)
val peer_id : t -> Peer_id.t

(** [sign t msg] is the Ed25519 signature of [msg]. *)
val sign : t -> string -> string

(** [verify ~raw_pub ~signature msg] checks an Ed25519 signature against a
    32-byte raw public key. *)
val verify : raw_pub:string -> signature:string -> string -> bool
