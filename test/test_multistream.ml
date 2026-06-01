open Starling

(* Run two fibers over a connected socket pair: a dialer on one end, an
   arbitrary responder on the other. Returns nothing; assertions live in [f]. *)
let over_pair dialer responder =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let a, b = Eio_unix.Net.socketpair_stream ~sw () in
  Eio.Fiber.both
    (fun () ->
      Eio.Buf_write.with_flow a (fun w ->
          let r = Eio.Buf_read.of_flow a ~max_size:65536 in
          dialer r w);
      (* signal EOF so a looping responder unblocks *)
      Eio.Flow.shutdown a `Send)
    (fun () ->
      Eio.Buf_write.with_flow b (fun w ->
          let r = Eio.Buf_read.of_flow b ~max_size:65536 in
          responder r w))

let negotiate_success () =
  let dres = ref (Error `Closed) in
  let lres = ref (Error `Closed) in
  over_pair
    (fun r w -> dres := Multistream.dial r w ~proto:"/noise")
    (fun r w -> lres := Multistream.listen r w ~supported:[ "/noise"; "/yamux/1.0.0" ]);
  Alcotest.(check bool) "dialer ok" true (!dres = Ok ());
  match !lres with
  | Ok p -> Alcotest.(check string) "listener selected /noise" "/noise" p
  | Error _ -> Alcotest.fail "listener did not select"

let negotiate_second_choice () =
  (* Dialer wants /yamux; listener supports it but not the first thing the dialer
     would ever try — here we just confirm a supported, non-first protocol works. *)
  let dres = ref (Error `Closed) in
  over_pair
    (fun r w -> dres := Multistream.dial r w ~proto:"/yamux/1.0.0")
    (fun r w -> ignore (Multistream.listen r w ~supported:[ "/yamux/1.0.0" ]));
  Alcotest.(check bool) "dialer ok on /yamux" true (!dres = Ok ())

let negotiate_unsupported () =
  let dres = ref (Ok ()) in
  over_pair
    (fun r w -> dres := Multistream.dial r w ~proto:"/mplex/6.7.0")
    (fun r w -> ignore (Multistream.listen r w ~supported:[ "/noise" ]));
  Alcotest.(check bool) "dialer sees unsupported" true (!dres = Error `Unsupported)

let framing_roundtrip () =
  (* write_message then read_message over the pair preserves content. *)
  let got = ref "" in
  over_pair
    (fun _r w ->
      Multistream.write_message w "/multistream/1.0.0";
      Multistream.write_message w "/noise";
      Eio.Buf_write.flush w)
    (fun r _w ->
      let a = Multistream.read_message r in
      let b = Multistream.read_message r in
      got := a ^ "|" ^ b);
  Alcotest.(check string) "framed messages" "/multistream/1.0.0|/noise" !got

(* End-to-end over real loopback TCP, exercising Transport.connect: bind :0,
   read the assigned port, then dial ourselves and negotiate /noise. *)
let transport_real_tcp () =
  Eio_main.run @@ fun env ->
  Eio.Switch.run @@ fun sw ->
  let net = Eio.Stdenv.net env in
  let listening =
    Eio.Net.listen ~sw ~reuse_addr:true ~backlog:1 net
      (`Tcp (Eio.Net.Ipaddr.V4.loopback, 0))
  in
  let port =
    match Eio.Net.listening_addr listening with
    | `Tcp (_, p) -> p
    | `Unix _ -> Alcotest.fail "expected a TCP address"
  in
  let dres = ref (Error `Closed) in
  let lres = ref (Error `Closed) in
  Eio.Fiber.both
    (fun () ->
      let flow, _addr = Eio.Net.accept ~sw listening in
      Eio.Buf_write.with_flow flow (fun w ->
          let r = Eio.Buf_read.of_flow flow ~max_size:65536 in
          lres := Multistream.listen r w ~supported:[ "/noise" ]))
    (fun () ->
      let ma = Multiaddr.of_string (Printf.sprintf "/ip4/127.0.0.1/tcp/%d" port) in
      let flow = Transport.connect ~sw ~net ma in
      Eio.Buf_write.with_flow flow (fun w ->
          let r = Eio.Buf_read.of_flow flow ~max_size:65536 in
          dres := Multistream.dial r w ~proto:"/noise");
      Eio.Flow.shutdown flow `Send);
  Alcotest.(check bool) "dial ok over tcp" true (!dres = Ok ());
  match !lres with
  | Ok p -> Alcotest.(check string) "listener selected" "/noise" p
  | Error _ -> Alcotest.fail "listener failed over tcp"

let () =
  Alcotest.run "multistream"
    [
      ( "negotiation",
        [
          Alcotest.test_case "success" `Quick negotiate_success;
          Alcotest.test_case "second choice" `Quick negotiate_second_choice;
          Alcotest.test_case "unsupported -> na" `Quick negotiate_unsupported;
          Alcotest.test_case "framing roundtrip" `Quick framing_roundtrip;
        ] );
      ( "transport",
        [ Alcotest.test_case "real loopback tcp" `Quick transport_real_tcp ] );
    ]
