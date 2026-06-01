(** HKDF as Noise uses it (spec §4.3): HMAC-SHA256, zero-length info, with the
    chaining key as the salt. Each output is 32 bytes.

    This is the textbook RFC 5869 expand step with [info = ""], unrolled to
    exactly two or three outputs so the byte conventions are explicit and
    interop-exact. *)

(** [hkdf2 ~ck ~ikm] is [(out1, out2)] where
    [temp = HMAC(ck, ikm)], [out1 = HMAC(temp, 0x01)],
    [out2 = HMAC(temp, out1 ‖ 0x02)]. *)
val hkdf2 : ck:string -> ikm:string -> string * string

(** [hkdf3 ~ck ~ikm] additionally yields [out3 = HMAC(temp, out2 ‖ 0x03)]. *)
val hkdf3 : ck:string -> ikm:string -> string * string * string
