module Cs = Noise_cipher_state

type t = { ck : string; h : string; cs : Cs.t }

let sha256 s = Digestif.SHA256.(to_raw_string (digest_string s))

let initialize ~protocol_name =
  let h =
    if String.length protocol_name <= 32 then
      protocol_name ^ String.make (32 - String.length protocol_name) '\000'
    else sha256 protocol_name
  in
  { ck = h; h; cs = Cs.empty }

let mix_hash t data = { t with h = sha256 (t.h ^ data) }

let mix_key t ikm =
  let ck, temp_k = Noise_hkdf.hkdf2 ~ck:t.ck ~ikm in
  { t with ck; cs = Cs.init temp_k }

let encrypt_and_hash t pt =
  let cs, ct = Cs.encrypt_with_ad t.cs ~ad:t.h pt in
  let t = mix_hash { t with cs } ct in
  (t, ct)

let decrypt_and_hash t ct =
  match Cs.decrypt_with_ad t.cs ~ad:t.h ct with
  | Error _ as e -> e
  | Ok (cs, pt) ->
    let t = mix_hash { t with cs } ct in
    Ok (t, pt)

let split t =
  let temp_k1, temp_k2 = Noise_hkdf.hkdf2 ~ck:t.ck ~ikm:"" in
  (Cs.init temp_k1, Cs.init temp_k2)

let handshake_hash t = t.h
let chaining_key t = t.ck
