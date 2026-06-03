(* starling — command-line entry point.

   Subcommands:
     starling                   print a Peer ID from a default dev seed
     starling id <hex-seed>     derive a Peer ID from a 32-byte Ed25519 seed
     starling listen <port>     run a node: serve ping + identify
     starling dial <multiaddr>  dial a node, ping it, and fetch its identify *)

open Starling

(* Install a Logs reporter for the node's operational output. Level comes from
   [$STARLING_LOG] (debug | info | warning | error | quiet), default info.
   The dial command's results stay on stdout — they are the command's answer,
   not log lines. *)
let setup_log () =
  Fmt_tty.setup_std_outputs ();
  Logs.set_reporter (Logs_fmt.reporter ());
  let level =
    match Sys.getenv_opt "STARLING_LOG" with
    | Some "debug" -> Some Logs.Debug
    | Some ("warn" | "warning") -> Some Logs.Warning
    | Some "error" -> Some Logs.Error
    | Some "quiet" -> None
    | _ -> Some Logs.Info
  in
  Logs.set_level level

(* A peer hanging up — reset, broken pipe, EOF, an aborted final flush — is a
   normal event, not a fault; log it calmly so genuine errors still stand out. *)
let contains_sub ~needle haystack =
  let nl = String.length needle and hl = String.length haystack in
  let rec go i = i + nl <= hl && (String.sub haystack i nl = needle || go (i + 1)) in
  nl = 0 || go 0

let report_conn_error exn =
  let s = Printexc.to_string exn in
  let benign m = contains_sub ~needle:m s in
  if
    benign "Connection reset" || benign "Connection_reset" || benign "Broken pipe"
    || benign "Flush_aborted" || benign "End_of_file"
  then Log.info (fun m -> m "peer disconnected")
  else Log.warn (fun m -> m "connection error: %s" s)

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
  let identity = Identity_store.(load_or_create (default_path ())) in
  Printf.printf "local peer: %s\n%!" (Peer_id.to_string (Keys.peer_id identity));
  let ma = Multiaddr.of_string addr in
  let flow = Transport.connect ~sw ~net:(Eio.Stdenv.net env) ma in
  let result =
    Upgrade.outbound ~sw ~clock ~identity flow (fun ~peer y ->
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
  let identity = Identity_store.(load_or_create (default_path ())) in
  let clock = Eio.Stdenv.clock env in
  let net = Eio.Stdenv.net env in
  let socket =
    Eio.Net.listen ~sw ~reuse_addr:true ~backlog:8 net
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, port))
  in
  Log.app (fun m ->
      m "listening on /ip4/127.0.0.1/tcp/%d/p2p/%s" port
        (Peer_id.to_string (Keys.peer_id identity)));
  (* [run_server] forks each connection into its own switch and closes the
     socket when the handler returns; [on_error] keeps per-connection faults
     from felling the listener, and [max_connections] caps the fiber/fd
     footprint a flood of dials can demand. *)
  let keepalive = Yamux.{ sleep = Eio.Time.sleep clock; interval = 30.; timeout = 15. } in
  Eio.Net.run_server socket ~max_connections:256
    ~on_error:report_conn_error
    (fun flow _addr ->
      Eio.Switch.run @@ fun csw ->
      ignore
        (Upgrade.inbound ~sw:csw ~clock ~keepalive ~identity flow (fun ~peer y ->
             Log.info (fun m -> m "peer connected: %s" (Peer_id.to_string peer));
             Host.serve ~sw:csw ~identity y)))

let usage () =
  prerr_endline "usage: starling [id <hex-seed> | listen <port> | dial <multiaddr>]";
  exit 2

let () =
  setup_log ();
  match Sys.argv with
  | [| _ |] -> print_id default_seed
  | [| _; "id" |] -> print_id default_seed
  | [| _; "id"; hex |] -> print_id (Hex.to_string (`Hex hex))
  | [| _; "listen"; port |] -> listen (int_of_string port)
  | [| _; "dial"; addr |] -> dial addr
  | _ -> usage ()
