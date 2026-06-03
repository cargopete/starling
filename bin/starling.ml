(* starling — command-line entry point.

   Subcommands:
     starling                   print a Peer ID from a default dev seed
     starling id <hex-seed>     derive a Peer ID from a 32-byte Ed25519 seed
     starling listen <port>     run a node: serve ping + identify
     starling dial <multiaddr>  dial a node, ping it, and fetch its identify *)

open Starling

let default_seed = String.make 32 '\001'

let print_id seed =
  let k = Keys.of_seed seed in
  Printf.printf "%s\n" (Peer_id.to_string (Keys.peer_id k))

(* Open a stream, negotiate [proto], and run [f] over its reader/writer. *)
let with_stream y proto f =
  let s = Yamux.open_stream y in
  Eio.Buf_write.with_flow s @@ fun w ->
  let r = Eio.Buf_read.of_flow s ~max_size:65536 in
  match Multistream.dial r w ~proto with
  | Ok () -> f r w
  | Error _ -> Printf.printf "peer does not support %s\n%!" proto

let dial addr =
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let clock = Eio.Stdenv.clock env in
  let identity = Keys.generate () in
  Printf.printf "local peer: %s\n%!" (Peer_id.to_string (Keys.peer_id identity));
  let ma = Multiaddr.of_string addr in
  let flow = Transport.connect ~sw ~net:(Eio.Stdenv.net env) ma in
  let result =
    Upgrade.outbound ~sw ~identity flow (fun ~peer y ->
        Printf.printf "established session with %s\n%!" (Peer_id.to_string peer);
        with_stream y Ping.protocol_id (fun r w ->
            let rtt = Ping.ping ~clock r w in
            Printf.printf "ping: %.3f ms\n%!" (rtt *. 1000.));
        with_stream y Identify.protocol_id (fun r _w ->
            let id = Identify.request r in
            Printf.printf "identify: agent=%s protocols=[%s]\n%!"
              (Option.value ~default:"?" id.agent_version)
              (String.concat ", " id.protocols)))
  in
  match result with
  | Ok () -> ()
  | Error _ -> Printf.printf "connection upgrade failed\n"

let listen port =
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let identity = Keys.generate () in
  let net = Eio.Stdenv.net env in
  let socket =
    Eio.Net.listen ~sw ~reuse_addr:true ~backlog:8 net
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
  in
  Printf.printf "starling listening on /ip4/127.0.0.1/tcp/%d/p2p/%s\n%!" port
    (Peer_id.to_string (Keys.peer_id identity));
  (* [run_server] forks each connection into its own switch and closes the
     socket when the handler returns; [on_error] swallows per-connection faults
     so one peer can never fell the listener. *)
  Eio.Net.run_server socket
    ~on_error:(fun exn ->
      Printf.eprintf "connection error: %s\n%!" (Printexc.to_string exn))
    (fun flow _addr ->
      Eio.Switch.run @@ fun csw ->
      ignore
        (Upgrade.inbound ~sw:csw ~identity flow (fun ~peer y ->
             Printf.printf "peer connected: %s\n%!" (Peer_id.to_string peer);
             Host.serve ~sw:csw ~identity y)))

let usage () =
  prerr_endline "usage: starling [id <hex-seed> | listen <port> | dial <multiaddr>]";
  exit 2

let () =
  match Sys.argv with
  | [| _ |] -> print_id default_seed
  | [| _; "id" |] -> print_id default_seed
  | [| _; "id"; hex |] -> print_id (Hex.to_string (`Hex hex))
  | [| _; "listen"; port |] -> listen (int_of_string port)
  | [| _; "dial"; addr |] -> dial addr
  | _ -> usage ()
