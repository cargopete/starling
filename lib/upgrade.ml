(* The full connection upgrade: TCP flow -> Noise -> /yamux -> a live muxer.

   Continuation-passing, because the encrypted writer is scoped to an
   [Eio.Buf_write.with_flow] block: [k] runs with the session live, and its
   result is returned. No .mli — the flow argument is an Eio resource whose
   row-typed capabilities are unpleasant to spell (see {!Transport}). *)

type error =
  [ `Handshake_failed
  | `Bad_payload
  | `Bad_signature
  | `Yamux_negotiation
  ]

let max_size = 1 lsl 20

let outbound ~sw ~identity flow k =
  Eio.Buf_write.with_flow flow @@ fun w ->
  let r = Eio.Buf_read.of_flow flow ~max_size in
  match Noise.run_initiator ~identity r w with
  | Error e -> Error (e :> error)
  | Ok session -> (
    let sf = Secure_flow.make r w session in
    Eio.Buf_write.with_flow sf @@ fun w2 ->
    let r2 = Eio.Buf_read.of_flow sf ~max_size in
    match Multistream.dial r2 w2 ~proto:Yamux.protocol_id with
    | Error _ -> Error `Yamux_negotiation
    | Ok () ->
      let y = Yamux.create ~sw ~is_client:true r2 w2 in
      Ok (k ~peer:session.remote_peer y))

let inbound ~sw ~identity flow k =
  Eio.Buf_write.with_flow flow @@ fun w ->
  let r = Eio.Buf_read.of_flow flow ~max_size in
  match Noise.run_responder ~identity r w with
  | Error e -> Error (e :> error)
  | Ok session -> (
    let sf = Secure_flow.make r w session in
    Eio.Buf_write.with_flow sf @@ fun w2 ->
    let r2 = Eio.Buf_read.of_flow sf ~max_size in
    match Multistream.listen r2 w2 ~supported:[ Yamux.protocol_id ] with
    | Error _ -> Error `Yamux_negotiation
    | Ok _ ->
      let y = Yamux.create ~sw ~is_client:false r2 w2 in
      Ok (k ~peer:session.remote_peer y))
