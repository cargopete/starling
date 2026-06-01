(** X25519 Diffie-Hellman keypairs for the Noise handshake.

    These are the Noise *static* and *ephemeral* keys — distinct from the
    Ed25519 host identity, which signs the static public key in the handshake
    payload. *)

type keypair

(** [generate ()] makes a fresh random keypair. Requires the global
    mirage-crypto RNG to be seeded (e.g. [Mirage_crypto_rng_unix.use_default ()]). *)
val generate : unit -> keypair

(** [of_secret_bytes b] loads a keypair from a 32-byte secret scalar
    (deterministic — used for test vectors). Raises [Invalid_argument] otherwise. *)
val of_secret_bytes : string -> keypair

(** The 32-byte raw public key. *)
val public : keypair -> string

(** [dh kp ~remote_public] is the 32-byte X25519 shared secret. Raises [Failure]
    if the exchange fails (e.g. a low-order remote point). *)
val dh : keypair -> remote_public:string -> string
