(** Persistent host identity: load the Ed25519 seed from disk, or mint and
    persist a fresh one. A production node must keep a stable Peer ID across
    restarts, so the identity cannot be regenerated each boot. *)

(** The default identity path: [$STARLING_IDENTITY] if set, otherwise
    [$HOME/.starling/identity.key]. Raises [Failure] if neither is available. *)
val default_path : unit -> string

(** [load_or_create path] returns the keypair stored at [path] (a raw 32-byte
    Ed25519 seed). If the file does not exist it generates a fresh keypair,
    writes the seed with [0o600] permissions (creating the parent directory
    [0o700] as needed), and returns it. Requires the RNG to be seeded.

    Raises [Failure] if the file exists but is not a valid 32-byte seed. *)
val load_or_create : string -> Keys.t
