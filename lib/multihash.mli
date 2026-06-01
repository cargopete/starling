(** Multihash: a self-describing hash, [<varint code><varint length><digest>].

    We need exactly two cases for libp2p Peer IDs:
    - [identity] (code 0x00): the "digest" is the data itself, unhashed. Used
      for small public keys (Ed25519), so the key is recoverable from the ID.
    - [sha2_256] (code 0x12): a 32-byte SHA-256 digest. Used for large keys (RSA). *)

type t = {
  code : int;  (** multihash function code *)
  digest : string;  (** the digest bytes (or the raw data, for identity) *)
}

val identity : int
(** [0x00] *)

val sha2_256 : int
(** [0x12] *)

(** [identity_of data] wraps [data] in an identity multihash (no hashing). *)
val identity_of : string -> t

(** [sha256_of data] is the sha2-256 multihash of [data]. *)
val sha256_of : string -> t

(** [to_bytes t] is the binary multihash. *)
val to_bytes : t -> string

(** [of_bytes s] parses a binary multihash. Raises [Invalid_argument] if the
    length prefix disagrees with the remaining bytes. *)
val of_bytes : string -> t
