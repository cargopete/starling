open Starling

let hex s = Hex.show (Hex.of_string s)
let seed b = String.make 32 b
let pid_of k = Peer_id.to_string (Keys.peer_id k)

(* Deterministic full XX with fixed keys: exercises every pure step, the libp2p
   payload + signature, mutual Peer-ID recovery, channel binding, and the split
   transport keys — no RNG, so it could later be pinned to a published vector. *)
let in_memory () =
  let i_static = Noise_dh.of_secret_bytes (seed '\001') in
  let i_eph = Noise_dh.of_secret_bytes (seed '\002') in
  let r_static = Noise_dh.of_secret_bytes (seed '\003') in
  let r_eph = Noise_dh.of_secret_bytes (seed '\004') in
  let i_id = Keys.of_seed (seed '\010') in
  let r_id = Keys.of_seed (seed '\020') in
  let hi = Noise_handshake.(create Initiator ~static:i_static ~ephemeral:i_eph ()) in
  let hr = Noise_handshake.(create Responder ~static:r_static ~ephemeral:r_eph ()) in
  (* msg1 = initiator ephemeral public (empty payload, no key yet) *)
  let hi, m1 = Noise_handshake.write_msg1 hi ~payload:"" in
  Alcotest.(check string) "msg1 is the ephemeral public key"
    (hex (Noise_dh.public i_eph)) (hex m1);
  let hr, _ = Result.get_ok (Noise_handshake.read_msg1 hr m1) in
  (* msg2: responder sends its identity payload *)
  let hr, m2 = Noise_handshake.write_msg2 hr ~payload:(Noise.make_payload ~identity:r_id ~static:r_static) in
  let hi, got2 = Result.get_ok (Noise_handshake.read_msg2 hi m2) in
  (match Noise.verify_payload got2 ~remote_static:(Option.get (Noise_handshake.remote_static hi)) with
  | Ok pid -> Alcotest.(check string) "initiator authenticates responder" (pid_of r_id) (Peer_id.to_string pid)
  | Error _ -> Alcotest.fail "responder payload failed to verify");
  (* msg3: initiator sends its identity payload *)
  let hi, m3 = Noise_handshake.write_msg3 hi ~payload:(Noise.make_payload ~identity:i_id ~static:i_static) in
  let hr, got3 = Result.get_ok (Noise_handshake.read_msg3 hr m3) in
  (match Noise.verify_payload got3 ~remote_static:(Option.get (Noise_handshake.remote_static hr)) with
  | Ok pid -> Alcotest.(check string) "responder authenticates initiator" (pid_of i_id) (Peer_id.to_string pid)
  | Error _ -> Alcotest.fail "initiator payload failed to verify");
  Alcotest.(check string) "both sides agree on the handshake hash"
    (hex (Noise_handshake.handshake_hash hi)) (hex (Noise_handshake.handshake_hash hr));
  (* transport keys interoperate both directions *)
  let i_send, i_recv = Noise_handshake.split hi in
  let r_recv, r_send = Noise_handshake.split hr in
  let _, ct = Noise_cipher_state.encrypt_with_ad i_send ~ad:"" "ping" in
  (match Noise_cipher_state.decrypt_with_ad r_recv ~ad:"" ct with
  | Ok (_, m) -> Alcotest.(check string) "transport i->r" "ping" m
  | Error _ -> Alcotest.fail "transport i->r failed");
  let _, ct2 = Noise_cipher_state.encrypt_with_ad r_send ~ad:"" "pong" in
  match Noise_cipher_state.decrypt_with_ad i_recv ~ad:"" ct2 with
  | Ok (_, m) -> Alcotest.(check string) "transport r->i" "pong" m
  | Error _ -> Alcotest.fail "transport r->i failed"

(* The same handshake driven over a real Eio socket pair via the Noise driver —
   exactly the path a go-libp2p dial will exercise. *)
let over_socketpair () =
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let a, b = Eio_unix.Net.socketpair_stream ~sw () in
  let i_id = Keys.of_seed (seed '\011') in
  let r_id = Keys.of_seed (seed '\021') in
  let is = ref None and rs = ref None in
  Eio.Fiber.both
    (fun () ->
      Eio.Buf_write.with_flow a (fun w ->
          let r = Eio.Buf_read.of_flow a ~max_size:65536 in
          is := Some (Noise.run_initiator ~identity:i_id r w)))
    (fun () ->
      Eio.Buf_write.with_flow b (fun w ->
          let r = Eio.Buf_read.of_flow b ~max_size:65536 in
          rs := Some (Noise.run_responder ~identity:r_id r w)));
  match (!is, !rs) with
  | Some (Ok isess), Some (Ok rsess) ->
    Alcotest.(check string) "initiator learned responder's Peer ID"
      (pid_of r_id) (Peer_id.to_string isess.remote_peer);
    Alcotest.(check string) "responder learned initiator's Peer ID"
      (pid_of i_id) (Peer_id.to_string rsess.remote_peer);
    Alcotest.(check string) "channel binding agrees"
      (hex isess.handshake_hash) (hex rsess.handshake_hash);
    let _, ct = Noise_cipher_state.encrypt_with_ad isess.send ~ad:"" "hello" in
    (match Noise_cipher_state.decrypt_with_ad rsess.recv ~ad:"" ct with
    | Ok (_, m) -> Alcotest.(check string) "transport i->r" "hello" m
    | Error _ -> Alcotest.fail "transport i->r failed");
    let _, ct2 = Noise_cipher_state.encrypt_with_ad rsess.send ~ad:"" "world" in
    (match Noise_cipher_state.decrypt_with_ad isess.recv ~ad:"" ct2 with
    | Ok (_, m) -> Alcotest.(check string) "transport r->i" "world" m
    | Error _ -> Alcotest.fail "transport r->i failed")
  | _ -> Alcotest.fail "handshake did not complete"

let () =
  Alcotest.run "noise_handshake"
    [
      ( "xx",
        [
          Alcotest.test_case "in-memory (fixed keys)" `Quick in_memory;
          Alcotest.test_case "over socketpair (driver)" `Quick over_socketpair;
        ] );
    ]
