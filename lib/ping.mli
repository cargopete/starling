(** The libp2p ping protocol ([/ipfs/ping/1.0.0]): the dialer writes 32 random
    bytes, the responder echoes them verbatim. Runs over an already-negotiated
    stream (its [Buf_read]/[Buf_write]). *)

val protocol_id : string
(** ["/ipfs/ping/1.0.0"] *)

val size : int
(** 32 *)

(** [ping ~clock r w] sends one 32-byte ping and returns the round-trip time in
    seconds. Raises [Failure] if the echo does not match. *)
val ping : clock:_ Eio.Time.clock -> Eio.Buf_read.t -> Eio.Buf_write.t -> float

(** [handle r w] echoes pings until the peer closes the stream. *)
val handle : Eio.Buf_read.t -> Eio.Buf_write.t -> unit
