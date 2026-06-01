type t = {
  r : Eio.Buf_read.t;
  w : Eio.Buf_write.t;
  mutable recv : Noise_cipher_state.t;
  mutable send : Noise_cipher_state.t;
  mutable inbuf : string;  (* decrypted plaintext awaiting delivery *)
  mutable inpos : int;
}

(* Max Noise transport plaintext = 65535 (max message) - 16 (Poly1305 tag). *)
let max_plaintext = 65535 - 16

let rec single_read t buf =
  let avail = String.length t.inbuf - t.inpos in
  if avail > 0 then begin
    let n = min (Cstruct.length buf) avail in
    Cstruct.blit_from_string t.inbuf t.inpos buf 0 n;
    t.inpos <- t.inpos + n;
    n
  end
  else begin
    (* Refill: read and decrypt one Noise transport message. *)
    let hdr = Eio.Buf_read.take 2 t.r in
    let len = (Char.code hdr.[0] lsl 8) lor Char.code hdr.[1] in
    let ct = Eio.Buf_read.take len t.r in
    (match Noise_cipher_state.decrypt_with_ad t.recv ~ad:"" ct with
    | Error _ -> raise End_of_file
    | Ok (recv, pt) ->
      t.recv <- recv;
      t.inbuf <- pt;
      t.inpos <- 0);
    single_read t buf
  end

let single_write t bufs =
  let data = Cstruct.copyv bufs in
  let len = String.length data in
  let rec go off =
    if off < len then begin
      let clen = min max_plaintext (len - off) in
      let chunk = String.sub data off clen in
      let send, ct = Noise_cipher_state.encrypt_with_ad t.send ~ad:"" chunk in
      t.send <- send;
      let b = Bytes.create 2 in
      Bytes.set_uint16_be b 0 (String.length ct);
      Eio.Buf_write.string t.w (Bytes.unsafe_to_string b);
      Eio.Buf_write.string t.w ct;
      go (off + clen)
    end
  in
  go 0;
  Eio.Buf_write.flush t.w;
  len

module Impl = struct
  type nonrec t = t

  let read_methods = []
  let single_read = single_read
  let single_write = single_write
  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
  let shutdown t _cmd = Eio.Buf_write.flush t.w
end

let handler = Eio.Flow.Pi.two_way (module Impl)

let make r w (session : Noise.session) =
  let t = { r; w; recv = session.recv; send = session.send; inbuf = ""; inpos = 0 } in
  Eio.Resource.T (t, handler)
