(** Unsigned variable-length integers (LEB128, base-128, little-endian).

    This is the multiformats "unsigned-varint": each byte carries 7 bits of
    payload in its low bits, with the high bit set on every byte except the last.
    libp2p uses it for multistream-select length prefixes, multiaddr protocol
    codes, multihash code/length, and protobuf field tags.

    We only ever encode non-negative values that fit in an OCaml native [int]
    (63 bits), which is well within the 9-byte practical limit. *)

(** [encode n] is the varint byte string for [n]. Raises [Invalid_argument] if
    [n] is negative. *)
val encode : int -> string

(** [write buf n] appends the varint encoding of [n] to [buf]. *)
val write : Buffer.t -> int -> unit

(** [read s pos] decodes a varint starting at byte [pos] of [s], returning the
    value and the position just past it. Raises [Invalid_argument] on a
    truncated sequence or a value that would overflow 63 bits. *)
val read : string -> int -> int * int
