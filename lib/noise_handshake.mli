(** The Noise XX handshake state machine (pure — no IO, no framing).

    {v
      XX:
        -> e
        <- e, ee, s, es
        -> s, se
    v}

    Each [write_*] returns the on-wire message bytes (no length prefix); each
    [read_*] consumes them and yields the decrypted payload. The libp2p payload
    (identity key + signature) is opaque here — the driver builds and verifies it.

    Steps must be called in order for the role: an initiator does
    [write_msg1] → [read_msg2] → [write_msg3] → [split]; a responder does
    [read_msg1] → [write_msg2] → [read_msg3] → [split]. *)

type role =
  | Initiator
  | Responder

type t

type error =
  [ `Truncated
  | `Decrypt
  ]

(** [create role ~static ?ephemeral ()] initialises the handshake with the local
    Noise static keypair. [ephemeral] may be supplied for deterministic tests;
    otherwise it is generated on first use (needs a seeded RNG). *)
val create : role -> static:Noise_dh.keypair -> ?ephemeral:Noise_dh.keypair -> unit -> t

val write_msg1 : t -> payload:string -> t * string
val read_msg1 : t -> string -> (t * string, error) result
val write_msg2 : t -> payload:string -> t * string
val read_msg2 : t -> string -> (t * string, error) result
val write_msg3 : t -> payload:string -> t * string
val read_msg3 : t -> string -> (t * string, error) result

(** The remote peer's Noise static public key, once learned. *)
val remote_static : t -> string option

(** The final handshake hash [h] — the channel-binding value. *)
val handshake_hash : t -> string

(** Derive the two transport cipher states: (initiator→responder, responder→initiator). *)
val split : t -> Noise_cipher_state.t * Noise_cipher_state.t
