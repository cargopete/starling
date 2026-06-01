(** Multiaddr: a self-describing network address as a list of typed components.

    MVP subset only: [/ip4], [/ip6], [/tcp], [/p2p]. Binary form is a sequence
    of [<varint protocol code><value>] components. *)

type component =
  | Ip4 of string  (** dotted-quad, e.g. ["127.0.0.1"] *)
  | Ip6 of string
  | Tcp of int
  | P2p of Peer_id.t

type t = component list

(** Protocol codes (multicodec). *)
val code_ip4 : int  (** 0x04 *)

val code_tcp : int  (** 0x06 *)

val code_ip6 : int  (** 0x29 *)

val code_p2p : int  (** 0x01A5 = 421 *)

(** [of_string "/ip4/127.0.0.1/tcp/4001"] parses the human form. Raises
    [Invalid_argument] on an unknown protocol or malformed value. *)
val of_string : string -> t

(** The human form, e.g. ["/ip4/127.0.0.1/tcp/4001"]. *)
val to_string : t -> string

(** The binary form. *)
val to_bytes : t -> string

(** Parse the binary form. *)
val of_bytes : string -> t

(** Convenience: the first [/ip4] or [/ip6] host and first [/tcp] port, if both
    are present — what you need to actually open a socket. *)
val tcp_endpoint : t -> (string * int) option
