(** Noise SymmetricState (spec §5.2): the running [(ck, h, cipherstate)] that
    drives the handshake key schedule.

    [ck] is the chaining key, [h] the running handshake hash (and the AEAD
    associated data during the handshake), wrapping a {!Noise_cipher_state}. *)

type t

(** [initialize ~protocol_name] sets [h] to [protocol_name] (right-padded with a
    single 0x00 if it is <= 32 bytes, else its SHA-256), [ck = h], and an empty
    cipher. For libp2p the name is ["Noise_XX_25519_ChaChaPoly_SHA256"]. *)
val initialize : protocol_name:string -> t

(** [mix_hash t data] sets [h := SHA256(h ‖ data)]. *)
val mix_hash : t -> string -> t

(** [mix_key t ikm] runs HKDF on [(ck, ikm)], updating [ck] and re-keying the
    cipher with the second output (nonce reset to 0). *)
val mix_key : t -> string -> t

(** [encrypt_and_hash t pt] encrypts [pt] with associated data [h], then mixes
    the ciphertext into [h]. Pass-through (ct = pt) before the first {!mix_key}. *)
val encrypt_and_hash : t -> string -> t * string

(** [decrypt_and_hash t ct] is the inverse; AAD is the current [h], and [h] is
    advanced with the ciphertext. *)
val decrypt_and_hash :
  t -> string -> (t * string, [ `Decrypt_failed ]) result

(** [split t] derives the two transport cipher states from [ck]: the first for
    initiator→responder, the second for responder→initiator. Transport messages
    use a zero-length AAD. *)
val split : t -> Noise_cipher_state.t * Noise_cipher_state.t

(** The running handshake hash [h] — the channel-binding value. *)
val handshake_hash : t -> string

(** The chaining key [ck] (exposed for testing). *)
val chaining_key : t -> string
