(** Noise CipherState (spec §5.1): a symmetric key plus a 64-bit nonce counter.

    AEAD is ChaCha20-Poly1305 in IETF mode. The 96-bit nonce is
    [0x00000000 ‖ little-endian-uint64(n)] per Noise §12.3. With no key set, the
    cipher is a pass-through (used for the cleartext first handshake message). *)

type t

(** A CipherState with no key — encrypt/decrypt are identity. *)
val empty : t

(** [init k] is a CipherState keyed with the 32-byte [k] and nonce 0. *)
val init : string -> t

val has_key : t -> bool

(** [encrypt_with_ad t ~ad pt] returns the advanced state and the ciphertext
    (with the 16-byte tag appended). Identity if [t] has no key. *)
val encrypt_with_ad : t -> ad:string -> string -> t * string

(** [decrypt_with_ad t ~ad ct] authenticates and decrypts. Identity if [t] has
    no key. [Error `Decrypt_failed] on a tag mismatch. *)
val decrypt_with_ad :
  t -> ad:string -> string -> (t * string, [ `Decrypt_failed ]) result
