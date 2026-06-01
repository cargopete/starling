module Ss = Noise_symmetric_state

type role =
  | Initiator
  | Responder

type t = {
  ss : Ss.t;
  s : Noise_dh.keypair;  (* local static *)
  e : Noise_dh.keypair option;  (* local ephemeral *)
  re : string option;  (* remote ephemeral public *)
  rs : string option;  (* remote static public *)
}

type error =
  [ `Truncated
  | `Decrypt
  ]

let protocol_name = "Noise_XX_25519_ChaChaPoly_SHA256"
let dhlen = 32
let tag = 16

let create _role ~static ?ephemeral () =
  let ss = Ss.initialize ~protocol_name in
  (* libp2p uses an empty prologue. *)
  let ss = Ss.mix_hash ss "" in
  { ss; s = static; e = ephemeral; re = None; rs = None }

let ephemeral t = match t.e with Some e -> e | None -> Noise_dh.generate ()

(* -> e *)
let write_msg1 t ~payload =
  let e = ephemeral t in
  let ss = Ss.mix_hash t.ss (Noise_dh.public e) in
  let ss, enc = Ss.encrypt_and_hash ss payload in
  ({ t with e = Some e; ss }, Noise_dh.public e ^ enc)

let read_msg1 t buf =
  if String.length buf < dhlen then Error `Truncated
  else
    let re = String.sub buf 0 dhlen in
    let ss = Ss.mix_hash t.ss re in
    let rest = String.sub buf dhlen (String.length buf - dhlen) in
    match Ss.decrypt_and_hash ss rest with
    | Error _ -> Error `Decrypt
    | Ok (ss, payload) -> Ok ({ t with re = Some re; ss }, payload)

(* <- e, ee, s, es *)
let write_msg2 t ~payload =
  let e = ephemeral t in
  let re = Option.get t.re in
  let ss = Ss.mix_hash t.ss (Noise_dh.public e) in
  let ss = Ss.mix_key ss (Noise_dh.dh e ~remote_public:re) in
  (* ee *)
  let ss, enc_s = Ss.encrypt_and_hash ss (Noise_dh.public t.s) in
  (* s *)
  let ss = Ss.mix_key ss (Noise_dh.dh t.s ~remote_public:re) in
  (* es: static · re *)
  let ss, enc_p = Ss.encrypt_and_hash ss payload in
  ({ t with e = Some e; ss }, Noise_dh.public e ^ enc_s ^ enc_p)

let read_msg2 t buf =
  let len = String.length buf in
  if len < dhlen + dhlen + tag then Error `Truncated
  else
    let re = String.sub buf 0 dhlen in
    let ss = Ss.mix_hash t.ss re in
    let e = Option.get t.e in
    let ss = Ss.mix_key ss (Noise_dh.dh e ~remote_public:re) in
    (* ee *)
    let enc_s = String.sub buf dhlen (dhlen + tag) in
    match Ss.decrypt_and_hash ss enc_s with
    | Error _ -> Error `Decrypt
    | Ok (ss, rs) ->
      let ss = Ss.mix_key ss (Noise_dh.dh e ~remote_public:rs) in
      (* es: e · rs *)
      let off = dhlen + dhlen + tag in
      let rest = String.sub buf off (len - off) in
      (match Ss.decrypt_and_hash ss rest with
      | Error _ -> Error `Decrypt
      | Ok (ss, payload) -> Ok ({ t with re = Some re; rs = Some rs; ss }, payload))

(* -> s, se *)
let write_msg3 t ~payload =
  let ss, enc_s = Ss.encrypt_and_hash t.ss (Noise_dh.public t.s) in
  let re = Option.get t.re in
  let ss = Ss.mix_key ss (Noise_dh.dh t.s ~remote_public:re) in
  (* se: static · re *)
  let ss, enc_p = Ss.encrypt_and_hash ss payload in
  ({ t with ss }, enc_s ^ enc_p)

let read_msg3 t buf =
  let len = String.length buf in
  if len < dhlen + tag then Error `Truncated
  else
    let enc_s = String.sub buf 0 (dhlen + tag) in
    match Ss.decrypt_and_hash t.ss enc_s with
    | Error _ -> Error `Decrypt
    | Ok (ss, rs) ->
      let e = Option.get t.e in
      let ss = Ss.mix_key ss (Noise_dh.dh e ~remote_public:rs) in
      (* se: e · rs *)
      let off = dhlen + tag in
      let rest = String.sub buf off (len - off) in
      (match Ss.decrypt_and_hash ss rest with
      | Error _ -> Error `Decrypt
      | Ok (ss, payload) -> Ok ({ t with rs = Some rs; ss }, payload))

let remote_static t = t.rs
let handshake_hash t = Ss.handshake_hash t.ss
let split t = Ss.split t.ss
