module Aead = Mirage_crypto.Chacha20

type t = { k : string option; n : int64 }

let empty = { k = None; n = 0L }
let init k = { k = Some k; n = 0L }
let has_key t = Option.is_some t.k

(* Noise §12.3: 96-bit nonce = 32 zero bits ‖ little-endian uint64(n). *)
let nonce_bytes n =
  let b = Bytes.create 12 in
  Bytes.fill b 0 4 '\000';
  Bytes.set_int64_le b 4 n;
  Bytes.unsafe_to_string b

let encrypt_with_ad t ~ad pt =
  match t.k with
  | None -> (t, pt)
  | Some k ->
    let key = Aead.of_secret k in
    let ct = Aead.authenticate_encrypt ~key ~nonce:(nonce_bytes t.n) ~adata:ad pt in
    ({ t with n = Int64.add t.n 1L }, ct)

let decrypt_with_ad t ~ad ct =
  match t.k with
  | None -> Ok (t, ct)
  | Some k -> (
    let key = Aead.of_secret k in
    match Aead.authenticate_decrypt ~key ~nonce:(nonce_bytes t.n) ~adata:ad ct with
    | Some pt -> Ok ({ t with n = Int64.add t.n 1L }, pt)
    | None -> Error `Decrypt_failed)
