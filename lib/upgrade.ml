(* The full connection upgrade: TCP flow -> Noise -> /yamux -> a live muxer.

   Continuation-passing, because the encrypted writer is scoped to an
   [Eio.Buf_write.with_flow] block: [k] runs with the session live, and its
   result is returned. No .mli — the flow argument is an Eio resource whose
   row-typed capabilities are unpleasant to spell (see {!Transport}). *)

type error =
  [ `Handshake_failed
  | `Bad_payload
  | `Bad_signature
  | `Noise_negotiation
  | `Yamux_negotiation
  | `Handshake_timeout
  ]

let max_size = 1 lsl 20

(* A peer that connects and then stalls must not pin a fiber and a socket
   forever, so every negotiation/handshake step runs under a deadline. *)
let default_timeout = 15.0

(* Run [f] with a deadline that is disarmed the instant [f] returns: the sleeper
   and [f] race, and whichever finishes first cancels the other. [f] must not
   block on the live session (that is [k]'s job, which runs unbounded after). *)
let with_deadline ~clock seconds (f : unit -> ('a, error) result) : ('a, error) result =
  Eio.Fiber.first
    (fun () ->
      Eio.Time.sleep clock seconds;
      Error `Handshake_timeout)
    f

let outbound ~sw ~clock ?(timeout = default_timeout) ~identity flow k =
  Eio.Buf_write.with_flow flow @@ fun w ->
  let r = Eio.Buf_read.of_flow flow ~max_size in
  let secure () =
    match Multistream.dial r w ~proto:Noise.protocol_id with
    | Error _ -> Error `Noise_negotiation
    | Ok () -> (
      match Noise.run_initiator ~identity r w with
      | Error e -> Error (e :> error)
      | Ok session -> Ok session)
  in
  match with_deadline ~clock timeout secure with
  | Error _ as e -> e
  | Ok session -> (
    let sf = Secure_flow.make r w session in
    Eio.Buf_write.with_flow sf @@ fun w2 ->
    let r2 = Eio.Buf_read.of_flow sf ~max_size in
    let muxer () =
      match Multistream.dial r2 w2 ~proto:Yamux.protocol_id with
      | Error _ -> Error `Yamux_negotiation
      | Ok () -> Ok ()
    in
    match with_deadline ~clock timeout muxer with
    | Error _ as e -> e
    | Ok () ->
      let y = Yamux.create ~sw ~is_client:true r2 w2 in
      let result = k ~peer:session.remote_peer y in
      Yamux.shutdown y;  (* politely GoAway now that our work is done *)
      Ok result)

let inbound ~sw ~clock ?(timeout = default_timeout) ~identity flow k =
  Eio.Buf_write.with_flow flow @@ fun w ->
  let r = Eio.Buf_read.of_flow flow ~max_size in
  let secure () =
    match Multistream.listen r w ~supported:[ Noise.protocol_id ] with
    | Error _ -> Error `Noise_negotiation
    | Ok _ -> (
      match Noise.run_responder ~identity r w with
      | Error e -> Error (e :> error)
      | Ok session -> Ok session)
  in
  match with_deadline ~clock timeout secure with
  | Error _ as e -> e
  | Ok session -> (
    let sf = Secure_flow.make r w session in
    Eio.Buf_write.with_flow sf @@ fun w2 ->
    let r2 = Eio.Buf_read.of_flow sf ~max_size in
    let muxer () =
      match Multistream.listen r2 w2 ~supported:[ Yamux.protocol_id ] with
      | Error _ -> Error `Yamux_negotiation
      | Ok _ -> Ok ()
    in
    match with_deadline ~clock timeout muxer with
    | Error _ as e -> e
    | Ok () ->
      let y = Yamux.create ~sw ~is_client:false r2 w2 in
      Ok (k ~peer:session.remote_peer y))
