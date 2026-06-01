open Starling

(* ------------------------------------------------------------- frame codec *)

let codec_known () =
  Alcotest.(check string) "Data+SYN stream 1"
    "000000010000000100000000"
    Yamux.(Hex.show (Hex.of_string (encode { typ = Data; flags = 0x1; stream_id = 1; length = 0; data = "" })));
  Alcotest.(check string) "WindowUpdate+ACK stream 2 delta 5"
    "000100020000000200000005"
    Yamux.(Hex.show (Hex.of_string (encode { typ = Window_update; flags = 0x2; stream_id = 2; length = 5; data = "" })))

let codec_roundtrip () =
  let f = Yamux.{ typ = Data; flags = 0x1; stream_id = 7; length = 5; data = "hello" } in
  let g = Yamux.decode (Yamux.encode f) in
  Alcotest.(check int) "stream id" 7 g.Yamux.stream_id;
  Alcotest.(check int) "length" 5 g.Yamux.length;
  Alcotest.(check string) "data" "hello" g.Yamux.data;
  Alcotest.(check int) "flags" 0x1 g.Yamux.flags

(* ---------------------------------------------- plain yamux over socketpair *)

let with_pair f =
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let a, b = Eio_unix.Net.socketpair_stream ~sw () in
  Eio.Buf_write.with_flow a @@ fun wa ->
  Eio.Buf_write.with_flow b @@ fun wb ->
  let ra = Eio.Buf_read.of_flow a ~max_size:1048576 in
  let rb = Eio.Buf_read.of_flow b ~max_size:1048576 in
  let client = Yamux.create ~sw ~is_client:true ra wa in
  let server = Yamux.create ~sw ~is_client:false rb wb in
  f ~sw ~client ~server

let stream_exchange () =
  let result = ref "" in
  with_pair (fun ~sw:_ ~client ~server ->
      Eio.Fiber.both
        (fun () ->
          let s = Yamux.open_stream client in
          Eio.Buf_write.with_flow s (fun w ->
              Eio.Buf_write.string w "ping";
              Eio.Buf_write.flush w);
          let r = Eio.Buf_read.of_flow s ~max_size:1024 in
          result := Eio.Buf_read.take 4 r)
        (fun () ->
          let s = Yamux.accept_stream server in
          let r = Eio.Buf_read.of_flow s ~max_size:1024 in
          let msg = Eio.Buf_read.take 4 r in
          Eio.Buf_write.with_flow s (fun w ->
              Eio.Buf_write.string w (if msg = "ping" then "pong" else "????");
              Eio.Buf_write.flush w)));
  Alcotest.(check string) "stream round-trip" "pong" !result

(* A payload bigger than one frame / forcing window updates. *)
let large_payload () =
  let payload = String.init 100_000 (fun i -> Char.chr (i mod 251)) in
  let got = ref "" in
  with_pair (fun ~sw:_ ~client ~server ->
      Eio.Fiber.both
        (fun () ->
          let s = Yamux.open_stream client in
          Eio.Buf_write.with_flow s (fun w ->
              Eio.Buf_write.string w payload;
              Eio.Buf_write.flush w))
        (fun () ->
          let s = Yamux.accept_stream server in
          let r = Eio.Buf_read.of_flow s ~max_size:200_000 in
          got := Eio.Buf_read.take 100_000 r));
  Alcotest.(check int) "length" 100_000 (String.length !got);
  Alcotest.(check bool) "content intact" true (String.equal !got payload)

(* ----------------------- the whole stack: Noise -> Secure_flow -> Yamux ---- *)

let full_stack () =
  Mirage_crypto_rng_unix.use_default ();
  Eio_main.run @@ fun _env ->
  Eio.Switch.run @@ fun sw ->
  let a, b = Eio_unix.Net.socketpair_stream ~sw () in
  let i_id = Keys.of_seed (String.make 32 '\030') in
  let r_id = Keys.of_seed (String.make 32 '\031') in
  let result = ref "" in
  Eio.Fiber.both
    (fun () ->
      Eio.Buf_write.with_flow a @@ fun w ->
      let r = Eio.Buf_read.of_flow a ~max_size:1048576 in
      match Noise.run_initiator ~identity:i_id r w with
      | Error _ -> Alcotest.fail "initiator handshake failed"
      | Ok session ->
        let sf = Secure_flow.make r w session in
        Eio.Buf_write.with_flow sf @@ fun w2 ->
        let r2 = Eio.Buf_read.of_flow sf ~max_size:1048576 in
        (match Multistream.dial r2 w2 ~proto:Yamux.protocol_id with
        | Error _ -> Alcotest.fail "client failed to negotiate yamux"
        | Ok () ->
          let y = Yamux.create ~sw ~is_client:true r2 w2 in
          let s = Yamux.open_stream y in
          Eio.Buf_write.with_flow s (fun stw ->
              Eio.Buf_write.string stw "ping";
              Eio.Buf_write.flush stw);
          let str = Eio.Buf_read.of_flow s ~max_size:1024 in
          result := Eio.Buf_read.take 4 str))
    (fun () ->
      Eio.Buf_write.with_flow b @@ fun w ->
      let r = Eio.Buf_read.of_flow b ~max_size:1048576 in
      match Noise.run_responder ~identity:r_id r w with
      | Error _ -> Alcotest.fail "responder handshake failed"
      | Ok session ->
        let sf = Secure_flow.make r w session in
        Eio.Buf_write.with_flow sf @@ fun w2 ->
        let r2 = Eio.Buf_read.of_flow sf ~max_size:1048576 in
        (match Multistream.listen r2 w2 ~supported:[ Yamux.protocol_id ] with
        | Error _ -> Alcotest.fail "server failed to negotiate yamux"
        | Ok _ ->
          let y = Yamux.create ~sw ~is_client:false r2 w2 in
          let s = Yamux.accept_stream y in
          let str = Eio.Buf_read.of_flow s ~max_size:1024 in
          let msg = Eio.Buf_read.take 4 str in
          Eio.Buf_write.with_flow s (fun stw ->
              Eio.Buf_write.string stw (if msg = "ping" then "pong" else "????");
              Eio.Buf_write.flush stw)));
  Alcotest.(check string) "stream round-trip over Noise + Yamux" "pong" !result

let () =
  Alcotest.run "yamux"
    [
      ( "codec",
        [
          Alcotest.test_case "known frames" `Quick codec_known;
          Alcotest.test_case "roundtrip" `Quick codec_roundtrip;
        ] );
      ( "streams",
        [
          Alcotest.test_case "exchange" `Quick stream_exchange;
          Alcotest.test_case "large payload" `Quick large_payload;
        ] );
      ("integration", [ Alcotest.test_case "noise + secure_flow + yamux" `Quick full_stack ]);
    ]
