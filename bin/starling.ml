(* starling — command-line entry point.

   Subcommands:
     starling                   print a Peer ID from a default dev seed
     starling id <hex-seed>     derive a Peer ID from a 32-byte Ed25519 seed
     starling dial <multiaddr>  connect and negotiate /noise (Phase 1 milestone) *)

open Starling

let default_seed = String.make 32 '\001'

let print_id seed =
  let k = Keys.of_seed seed in
  Printf.printf "%s\n" (Peer_id.to_string (Keys.peer_id k))

let dial addr =
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let identity = Keys.generate () in
  Printf.printf "local peer: %s\n%!" (Peer_id.to_string (Keys.peer_id identity));
  let ma = Multiaddr.of_string addr in
  let flow = Transport.connect ~sw ~net:(Eio.Stdenv.net env) ma in
  Eio.Buf_write.with_flow flow @@ fun w ->
  let r = Eio.Buf_read.of_flow flow ~max_size:65536 in
  match Multistream.dial r w ~proto:"/noise" with
  | Error `Unsupported -> Printf.printf "peer does not support /noise\n"
  | Error (`Protocol_mismatch h) -> Printf.printf "not a multistream peer (got %S)\n" h
  | Error (`Unexpected s) -> Printf.printf "unexpected reply: %S\n" s
  | Error `Closed -> Printf.printf "peer closed during negotiation\n"
  | Ok () -> (
    Printf.printf "negotiated /noise; starting handshake...\n%!";
    match Noise.run_initiator ~identity r w with
    | Error `Handshake_failed -> Printf.printf "noise handshake failed\n"
    | Error `Bad_payload -> Printf.printf "peer sent a malformed identity payload\n"
    | Error `Bad_signature -> Printf.printf "peer identity signature did not verify\n"
    | Ok sess -> (
      Printf.printf "established Noise with %s\n%!" (Peer_id.to_string sess.remote_peer);
      let sf = Secure_flow.make r w sess in
      Eio.Buf_write.with_flow sf @@ fun w2 ->
      let r2 = Eio.Buf_read.of_flow sf ~max_size:1048576 in
      match Multistream.dial r2 w2 ~proto:Yamux.protocol_id with
      | Error _ -> Printf.printf "could not negotiate %s\n" Yamux.protocol_id
      | Ok () ->
        let _y = Yamux.create ~sw ~is_client:true r2 w2 in
        Printf.printf "negotiated %s — muxer up\n" Yamux.protocol_id))

let usage () =
  prerr_endline "usage: starling [id <hex-seed> | dial <multiaddr>]";
  exit 2

let () =
  match Sys.argv with
  | [| _ |] -> print_id default_seed
  | [| _; "id" |] -> print_id default_seed
  | [| _; "id"; hex |] -> print_id (Hex.to_string (`Hex hex))
  | [| _; "dial"; addr |] -> dial addr
  | _ -> usage ()
