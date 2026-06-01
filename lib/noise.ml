module Hs = Noise_handshake

type session = {
  send : Noise_cipher_state.t;
  recv : Noise_cipher_state.t;
  remote_peer : Peer_id.t;
  handshake_hash : string;
}

type error =
  [ `Handshake_failed
  | `Bad_payload
  | `Bad_signature
  ]

let sig_prefix = "noise-libp2p-static-key:"

let make_payload ~identity ~static =
  let identity_key = Keys.public_key_proto identity in
  let identity_sig = Keys.sign identity (sig_prefix ^ Noise_dh.public static) in
  Noise_payload.encode ~identity_key ~identity_sig

let verify_payload payload ~remote_static =
  match Noise_payload.decode payload with
  | None -> Error `Bad_payload
  | Some p -> (
    match Peer_id.ed25519_raw_of_proto p.identity_key with
    | None -> Error `Bad_payload
    | Some raw_pub ->
      if Keys.verify ~raw_pub ~signature:p.identity_sig (sig_prefix ^ remote_static)
      then Ok (Peer_id.of_ed25519_pubkey raw_pub)
      else Error `Bad_signature)

(* Noise transport framing: 2-byte big-endian length prefix. *)
let write_frame w msg =
  let b = Bytes.create 2 in
  Bytes.set_uint16_be b 0 (String.length msg);
  Eio.Buf_write.string w (Bytes.unsafe_to_string b);
  Eio.Buf_write.string w msg;
  Eio.Buf_write.flush w

let read_frame r =
  let hdr = Eio.Buf_read.take 2 r in
  let len = (Char.code hdr.[0] lsl 8) lor Char.code hdr.[1] in
  Eio.Buf_read.take len r

(* DH failures raise [Failure]; truncated reads raise [End_of_file]; both mean a
   failed handshake. *)
let guard f =
  try f () with End_of_file | Failure _ -> Error `Handshake_failed

let run_initiator ~identity ?static r w =
  guard @@ fun () ->
  let static = match static with Some s -> s | None -> Noise_dh.generate () in
  let hs = Hs.create Hs.Initiator ~static () in
  let hs, m1 = Hs.write_msg1 hs ~payload:"" in
  write_frame w m1;
  match Hs.read_msg2 hs (read_frame r) with
  | Error _ -> Error `Handshake_failed
  | Ok (hs, payload2) -> (
    match Hs.remote_static hs with
    | None -> Error `Handshake_failed
    | Some rs -> (
      match verify_payload payload2 ~remote_static:rs with
      | Error e -> Error (e :> error)
      | Ok remote_peer ->
        let payload3 = make_payload ~identity ~static in
        let hs, m3 = Hs.write_msg3 hs ~payload:payload3 in
        write_frame w m3;
        let send, recv = Hs.split hs in
        Ok { send; recv; remote_peer; handshake_hash = Hs.handshake_hash hs }))

let run_responder ~identity ?static r w =
  guard @@ fun () ->
  let static = match static with Some s -> s | None -> Noise_dh.generate () in
  let hs = Hs.create Hs.Responder ~static () in
  match Hs.read_msg1 hs (read_frame r) with
  | Error _ -> Error `Handshake_failed
  | Ok (hs, _payload1) -> (
    let payload2 = make_payload ~identity ~static in
    let hs, m2 = Hs.write_msg2 hs ~payload:payload2 in
    write_frame w m2;
    match Hs.read_msg3 hs (read_frame r) with
    | Error _ -> Error `Handshake_failed
    | Ok (hs, payload3) -> (
      match Hs.remote_static hs with
      | None -> Error `Handshake_failed
      | Some rs -> (
        match verify_payload payload3 ~remote_static:rs with
        | Error e -> Error (e :> error)
        | Ok remote_peer ->
          (* responder: c1 is initiator→responder (our recv), c2 is ours to send *)
          let c1, c2 = Hs.split hs in
          Ok { send = c2; recv = c1; remote_peer; handshake_hash = Hs.handshake_hash hs })))
