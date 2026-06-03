open Starling

(* The whole node, end to end over real loopback TCP: a server listens; a client
   dials, upgrades (TCP -> Noise -> Yamux), then over separate streams runs
   /ipfs/ping/1.0.0 and /ipfs/id/1.0.0. This is the MVP, minus go-libp2p. *)
let mvp_over_tcp () =
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let server_id = Keys.of_seed (String.make 32 '\040') in
  let client_id = Keys.of_seed (String.make 32 '\041') in
  let listening =
    Eio.Net.listen ~sw ~reuse_addr:true ~backlog:4 net
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
  in
  let port =
    match Eio.Net.listening_addr listening with
    | `Tcp (_, p) -> p
    | `Unix _ -> Alcotest.fail "expected TCP"
  in
  let seen_peer = ref "" and rtt = ref (-1.0) and agent = ref "" and id_peer = ref "" in
  (* Server runs as a daemon: cancelled once the client fiber is done. *)
  Eio.Fiber.fork_daemon ~sw (fun () ->
      let flow, _addr = Eio.Net.accept ~sw listening in
      ignore
        (Upgrade.inbound ~sw ~clock ~identity:server_id flow (fun ~peer y ->
             seen_peer := Peer_id.to_string peer;
             Host.serve ~sw ~identity:server_id y));
      `Stop_daemon);
  (* Client. *)
  let ma = Multiaddr.of_string (Printf.sprintf "/ip4/127.0.0.1/tcp/%d" port) in
  let flow = Transport.connect ~sw ~net ma in
  ignore
    (Upgrade.outbound ~sw ~clock ~identity:client_id flow (fun ~peer:_ y ->
         (* ping on its own stream *)
         let s = Yamux.open_stream y in
         Eio.Buf_write.with_flow s (fun w ->
             let r = Eio.Buf_read.of_flow s ~max_size:65536 in
             match Multistream.dial r w ~proto:Ping.protocol_id with
             | Ok () -> rtt := Ping.ping ~clock r w
             | Error _ -> Alcotest.fail "client could not negotiate ping");
         (* identify on a fresh stream *)
         let s2 = Yamux.open_stream y in
         Eio.Buf_write.with_flow s2 (fun w ->
             let r = Eio.Buf_read.of_flow s2 ~max_size:65536 in
             match Multistream.dial r w ~proto:Identify.protocol_id with
             | Ok () ->
               let id = Identify.request r in
               agent := Option.value ~default:"" id.agent_version;
               id_peer := (match Identify.peer_id id with Some p -> Peer_id.to_string p | None -> "")
             | Error _ -> Alcotest.fail "client could not negotiate identify")));
  Alcotest.(check bool) "round-trip time was measured" true (!rtt >= 0.0);
  Alcotest.(check string) "server authenticated the client"
    (Peer_id.to_string (Keys.peer_id client_id)) !seen_peer;
  Alcotest.(check string) "identify agent version" "starling/0.1.0" !agent;
  Alcotest.(check string) "identify public key matches server peer id"
    (Peer_id.to_string (Keys.peer_id server_id)) !id_peer

(* A peer that connects over TCP and then says nothing must not pin the server:
   the handshake deadline fires and [inbound] returns [`Handshake_timeout]. *)
let handshake_timeout_on_silent_peer () =
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let clock = Eio.Stdenv.clock env in
  let server_id = Keys.of_seed (String.make 32 '\042') in
  let listening =
    Eio.Net.listen ~sw ~reuse_addr:true ~backlog:4 net
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
  in
  let port = match Eio.Net.listening_addr listening with `Tcp (_, p) -> p | _ -> 0 in
  let timed_out = ref false in
  Eio.Fiber.both
    (fun () ->
      let flow, _addr = Eio.Net.accept ~sw listening in
      match Upgrade.inbound ~sw ~clock ~timeout:0.1 ~identity:server_id flow (fun ~peer:_ _ -> ()) with
      | Error `Handshake_timeout -> timed_out := true
      | Error _ -> Alcotest.fail "expected a handshake timeout, got another error"
      | Ok () -> Alcotest.fail "silent peer should not complete the handshake")
    (fun () ->
      (* connect, then stay mute long enough for the deadline to fire *)
      let ma = Multiaddr.of_string (Printf.sprintf "/ip4/127.0.0.1/tcp/%d" port) in
      let _flow = Transport.connect ~sw ~net ma in
      Eio.Time.sleep clock 0.5);
  Alcotest.(check bool) "inbound timed out on a silent peer" true !timed_out

let () =
  Alcotest.run "mvp"
    [
      ("node", [ Alcotest.test_case "ping + identify over tcp" `Quick mvp_over_tcp ]);
      ( "limits",
        [ Alcotest.test_case "handshake timeout on silent peer" `Quick handshake_timeout_on_silent_peer ]
      );
    ]
