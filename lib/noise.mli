(** The libp2p Noise security transport: runs the XX handshake over an Eio flow,
    authenticates the peer's identity, and yields the transport cipher states.

    Noise messages are framed on the wire as [<2-byte big-endian length><message>]. *)

type session = {
  send : Noise_cipher_state.t;  (** encrypts outbound transport messages *)
  recv : Noise_cipher_state.t;  (** decrypts inbound transport messages *)
  remote_peer : Peer_id.t;  (** the verified remote Peer ID *)
  handshake_hash : string;  (** channel binding *)
}

type error =
  [ `Handshake_failed
  | `Bad_payload
  | `Bad_signature
  ]

(** The string signed by the identity key over the Noise static public key. *)
val sig_prefix : string

(** Build this host's [NoiseHandshakePayload]: the marshalled identity public key
    plus a signature over [sig_prefix ‖ static_public]. *)
val make_payload : identity:Keys.t -> static:Noise_dh.keypair -> string

(** Verify a peer's payload against the Noise static key they used, returning
    their Peer ID on success. *)
val verify_payload :
  string -> remote_static:string -> (Peer_id.t, [ `Bad_payload | `Bad_signature ]) result

(** Run the handshake as the dialer (initiator). [static] defaults to a fresh
    random Noise keypair. *)
val run_initiator :
  identity:Keys.t ->
  ?static:Noise_dh.keypair ->
  Eio.Buf_read.t ->
  Eio.Buf_write.t ->
  (session, error) result

(** Run the handshake as the listener (responder). *)
val run_responder :
  identity:Keys.t ->
  ?static:Noise_dh.keypair ->
  Eio.Buf_read.t ->
  Eio.Buf_write.t ->
  (session, error) result
