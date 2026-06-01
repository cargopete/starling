(** base58btc (Bitcoin alphabet) encoding of arbitrary byte strings.

    Used for the textual form of Peer IDs. This is plain base58, not
    Base58Check — no checksum. Leading 0x00 bytes map to leading ['1']s. *)

(** [encode bytes] is the base58btc text for [bytes]. *)
val encode : string -> string

(** [decode s] is the byte string that [encode] would produce [s] from. Raises
    [Invalid_argument] on a character outside the base58 alphabet. *)
val decode : string -> string
