(** The libp2p Identify protocol ([/ipfs/id/1.0.0]): the responder sends one
    length-prefixed [Identify] protobuf describing itself; the dialer reads it.

    The message is prefixed with an unsigned-varint length on the stream. *)

type t = {
  protocol_version : string option;  (** field 5, e.g. "ipfs/0.1.0" *)
  agent_version : string option;  (** field 6, e.g. "starling/0.2.0" *)
  public_key : string option;  (** field 1, marshalled [PublicKey] protobuf *)
  listen_addrs : string list;  (** field 2, binary multiaddrs *)
  protocols : string list;  (** field 3 *)
  observed_addr : string option;  (** field 4, binary multiaddr *)
}

val protocol_id : string
(** ["/ipfs/id/1.0.0"] *)

val empty : t

val encode : t -> string
val decode : string -> t

(** The Peer ID implied by [public_key], if present and an Ed25519 key. *)
val peer_id : t -> Peer_id.t option

(** [respond w t] writes the length-prefixed Identify message. *)
val respond : Eio.Buf_write.t -> t -> unit

(** [request r] reads a length-prefixed Identify message. *)
val request : Eio.Buf_read.t -> t
