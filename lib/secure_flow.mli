(** The post-handshake Noise transport presented as an ordinary
    {!Eio.Flow.two_way}.

    Plaintext written to it is split into Noise transport messages
    ([<2-byte BE len><ChaCha20-Poly1305 ciphertext>], zero AAD) and encrypted;
    bytes read are decrypted and delivered as a byte stream. Because it is a
    standard Eio flow, [Eio.Buf_read]/[Eio.Buf_write] — and hence
    {!Multistream} and {!Yamux} — compose over it unchanged. *)

(** [make r w session] wraps the underlying (already-buffered) connection and
    the handshake's transport keys into an encrypted duplex flow. [r] and [w]
    must be the same buffers used for the handshake, so no buffered bytes are
    lost. *)
val make :
  Eio.Buf_read.t -> Eio.Buf_write.t -> Noise.session -> Eio.Flow.two_way_ty Eio.Resource.t
