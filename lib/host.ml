(* Server-side protocol dispatch over a live Yamux session: accept streams, run
   multistream-select on each, and route to the ping / identify handlers.
   No .mli — the stream argument is an Eio flow resource (see {!Transport}). *)

let agent_version = "starling/0.1.0"
let max_size = 1 lsl 16

let supported = [ Ping.protocol_id; Identify.protocol_id ]

(* This host's Identify message. *)
let identify_of identity =
  {
    Identify.empty with
    public_key = Some (Keys.public_key_proto identity);
    agent_version = Some agent_version;
    protocols = supported;
  }

let handle_stream ~identity stream =
  Eio.Buf_write.with_flow stream @@ fun w ->
  let r = Eio.Buf_read.of_flow stream ~max_size in
  match Multistream.listen r w ~supported with
  | Error _ -> ()
  | Ok proto ->
    if String.equal proto Ping.protocol_id then Ping.handle r w
    else if String.equal proto Identify.protocol_id then Identify.respond w (identify_of identity)
    else ()

(* Serve a session forever: one daemon fiber per accepted stream. Handlers are
   daemons so a long-lived one (e.g. the ping echo loop) does not keep the
   connection's switch from tearing down. *)
let serve ~sw ~identity y =
  let rec loop () =
    let stream = Yamux.accept_stream y in
    Eio.Fiber.fork_daemon ~sw (fun () ->
        (try handle_stream ~identity stream with End_of_file | Failure _ -> ());
        `Stop_daemon);
    loop ()
  in
  loop ()
