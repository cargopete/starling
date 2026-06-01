(** multistream-select 1.0.0 — protocol negotiation.

    Each message on the wire is [<varint length><utf8 bytes>'\n'], where the
    length includes the trailing newline. Both peers open by exchanging the
    header [/multistream/1.0.0]; the dialer then proposes a protocol, which the
    listener echoes to accept or answers with [na] to reject.

    These functions work over Eio buffered reader/writer pairs, so they compose
    over a raw TCP flow (connection upgrade) and, later, over each Yamux stream. *)

val protocol_id : string
(** ["/multistream/1.0.0"] *)

type error =
  [ `Protocol_mismatch of string  (** peer's opening header was not ours *)
  | `Unsupported  (** peer answered [na] to our proposal *)
  | `Unexpected of string  (** peer answered with something unexpected *)
  | `Closed  (** peer closed before selecting *)
  ]

(** [write_message w s] frames and writes [s] as one multistream message. *)
val write_message : Eio.Buf_write.t -> string -> unit

(** [read_message r] reads one framed message, with the trailing newline stripped.
    Raises [End_of_file] if the peer closed. *)
val read_message : Eio.Buf_read.t -> string

(** [dial r w ~proto] performs the dialer side: exchange headers and propose
    [proto], returning [Ok ()] if the listener selected it. *)
val dial : Eio.Buf_read.t -> Eio.Buf_write.t -> proto:string -> (unit, error) result

(** [listen r w ~supported] performs the listener side: exchange headers, then
    accept the first proposed protocol that is in [supported] (answering [na] to
    the rest), returning the selected protocol. *)
val listen :
  Eio.Buf_read.t -> Eio.Buf_write.t -> supported:string list -> (string, error) result
