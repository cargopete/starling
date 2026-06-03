let protocol_id = "/yamux/1.0.0"
let window_initial = 256 * 1024
let max_frame_data = 16384

(* Replenish the peer's send window once the application has consumed half the
   window's worth of bytes — frequent enough to keep a fast reader fed, rare
   enough not to flood the wire with tiny WindowUpdates. *)
let ack_threshold = window_initial / 2

(* Flags *)
let f_syn = 0x1
let f_ack = 0x2
let f_fin = 0x4
let f_rst = 0x8

type frame_type =
  | Data
  | Window_update
  | Ping
  | Go_away

type frame = {
  typ : frame_type;
  flags : int;
  stream_id : int;
  length : int;
  data : string;
}

let int_of_type = function Data -> 0 | Window_update -> 1 | Ping -> 2 | Go_away -> 3

let type_of_int = function
  | 0 -> Data
  | 1 -> Window_update
  | 2 -> Ping
  | 3 -> Go_away
  | n -> invalid_arg (Printf.sprintf "Yamux: unknown frame type %d" n)

let set_be32 b off v =
  Bytes.set_uint8 b off ((v lsr 24) land 0xff);
  Bytes.set_uint8 b (off + 1) ((v lsr 16) land 0xff);
  Bytes.set_uint8 b (off + 2) ((v lsr 8) land 0xff);
  Bytes.set_uint8 b (off + 3) (v land 0xff)

let get_be32 s off =
  (Char.code s.[off] lsl 24)
  lor (Char.code s.[off + 1] lsl 16)
  lor (Char.code s.[off + 2] lsl 8)
  lor Char.code s.[off + 3]

let encode f =
  let b = Bytes.create 12 in
  Bytes.set_uint8 b 0 0;
  (* version *)
  Bytes.set_uint8 b 1 (int_of_type f.typ);
  Bytes.set_uint16_be b 2 f.flags;
  set_be32 b 4 f.stream_id;
  set_be32 b 8 f.length;
  Bytes.unsafe_to_string b ^ f.data

let decode s =
  let typ = type_of_int (Char.code s.[1]) in
  let flags = (Char.code s.[2] lsl 8) lor Char.code s.[3] in
  let stream_id = get_be32 s 4 in
  let length = get_be32 s 8 in
  let data = if typ = Data && length > 0 then String.sub s 12 length else "" in
  { typ; flags; stream_id; length; data }

let read_frame r =
  let hdr = Eio.Buf_read.take 12 r in
  let typ = type_of_int (Char.code hdr.[1]) in
  let flags = (Char.code hdr.[2] lsl 8) lor Char.code hdr.[3] in
  let stream_id = get_be32 hdr 4 in
  let length = get_be32 hdr 8 in
  let data = if typ = Data && length > 0 then Eio.Buf_read.take length r else "" in
  { typ; flags; stream_id; length; data }

type st = {
  id : int;
  mutable in_leftover : string;
  mutable in_pos : int;
  mutable pending_ack : int;  (* bytes consumed by the app, not yet acked to the peer *)
  incoming : string option Eio.Stream.t;  (* None marks EOF *)
  mutable send_window : int;
  smutex : Eio.Mutex.t;
  win_cond : Eio.Condition.t;
  emit : frame -> unit;  (* serialised frame writer (closes over the session) *)
}

type session = {
  r : Eio.Buf_read.t;
  w : Eio.Buf_write.t;
  is_client : bool;
  mutable next_id : int;
  mutable closed : bool;  (* set once the read loop sees EOF / a transport error *)
  streams : (int, st) Hashtbl.t;
  accept_q : st option Eio.Stream.t;  (* None marks the muxer closed *)
  write_mutex : Eio.Mutex.t;
  id_mutex : Eio.Mutex.t;
}

let emit session frame =
  let bytes = encode frame in
  Eio.Mutex.use_rw ~protect:true session.write_mutex (fun () ->
      Eio.Buf_write.string session.w bytes;
      Eio.Buf_write.flush session.w)

let new_stream session id =
  {
    id;
    in_leftover = "";
    in_pos = 0;
    pending_ack = 0;
    incoming = Eio.Stream.create 256;
    send_window = window_initial;
    smutex = Eio.Mutex.create ();
    win_cond = Eio.Condition.create ();
    emit = (fun f -> emit session f);
  }

(* -------- stream as an Eio.Flow.two_way -------- *)

let rec stream_single_read st buf =
  let avail = String.length st.in_leftover - st.in_pos in
  if avail > 0 then begin
    let n = min (Cstruct.length buf) avail in
    Cstruct.blit_from_string st.in_leftover st.in_pos buf 0 n;
    st.in_pos <- st.in_pos + n;
    (* Real backpressure: the peer's send window is replenished only as the
       application drains data, so a slow reader throttles the sender instead
       of letting [incoming] grow without bound. *)
    st.pending_ack <- st.pending_ack + n;
    if st.pending_ack >= ack_threshold then begin
      st.emit { typ = Window_update; flags = 0; stream_id = st.id; length = st.pending_ack; data = "" };
      st.pending_ack <- 0
    end;
    n
  end
  else
    match Eio.Stream.take st.incoming with
    | None -> raise End_of_file
    | Some chunk ->
      st.in_leftover <- chunk;
      st.in_pos <- 0;
      stream_single_read st buf

(* Reserve up to [want] bytes of send-window, blocking if exhausted. *)
let rec reserve st want =
  match
    Eio.Mutex.use_rw ~protect:true st.smutex (fun () ->
        if st.send_window <= 0 then None
        else begin
          let c = min want st.send_window in
          st.send_window <- st.send_window - c;
          Some c
        end)
  with
  | Some c -> c
  | None ->
    Eio.Condition.await_no_mutex st.win_cond;
    reserve st want

let stream_single_write st bufs =
  let data = Cstruct.copyv bufs in
  let len = String.length data in
  let rec go off =
    if off < len then begin
      let granted = reserve st (min max_frame_data (len - off)) in
      let chunk = String.sub data off granted in
      st.emit { typ = Data; flags = 0; stream_id = st.id; length = granted; data = chunk };
      go (off + granted)
    end
  in
  go 0;
  len

let stream_shutdown st = function
  | `Send | `All ->
    st.emit { typ = Data; flags = f_fin; stream_id = st.id; length = 0; data = "" }
  | `Receive -> ()

module Stream_impl = struct
  type t = st

  let read_methods = []
  let single_read = stream_single_read
  let single_write = stream_single_write
  let copy t ~src = Eio.Flow.Pi.simple_copy ~single_write t ~src
  let shutdown = stream_shutdown
end

let stream_handler = Eio.Flow.Pi.two_way (module Stream_impl)
let to_flow (st : st) : Eio.Flow.two_way_ty Eio.Resource.t = Eio.Resource.T (st, stream_handler)

type stream = Eio.Flow.two_way_ty Eio.Resource.t

(* -------- read loop -------- *)

let handle session f =
  match f.typ with
  | Ping ->
    if f.flags land f_syn <> 0 then
      emit session { typ = Ping; flags = f_ack; stream_id = 0; length = f.length; data = "" }
  | Go_away -> Log.debug (fun m -> m "yamux: peer sent GoAway (code %d)" f.length)
  | Window_update | Data ->
    let st =
      match Hashtbl.find_opt session.streams f.stream_id with
      | Some st -> Some st
      | None ->
        if f.flags land f_syn <> 0 then begin
          let st = new_stream session f.stream_id in
          Hashtbl.replace session.streams f.stream_id st;
          emit session
            { typ = Window_update; flags = f_ack; stream_id = f.stream_id; length = 0; data = "" };
          Eio.Stream.add session.accept_q (Some st);
          Some st
        end
        else None
    in
    (match st with
    | None -> ()
    | Some st ->
      (match f.typ with
      | Window_update ->
        Eio.Mutex.use_rw ~protect:true st.smutex (fun () ->
            st.send_window <- st.send_window + f.length);
        Eio.Condition.broadcast st.win_cond
      | Data ->
        (* Just queue the data; the window is replenished on consumption (see
           [stream_single_read]), which is what gives us real flow control. *)
        if String.length f.data > 0 then Eio.Stream.add st.incoming (Some f.data)
      | _ -> ());
      if f.flags land f_fin <> 0 then Eio.Stream.add st.incoming None;
      if f.flags land f_rst <> 0 then begin
        Eio.Stream.add st.incoming None;
        Hashtbl.remove session.streams st.id
      end)

let read_loop session () =
  (* Tear the muxer down once: signal EOF to every open stream and wake any
     fiber blocked in [accept_stream]. Idempotent via [session.closed]. *)
  let close () =
    if not session.closed then begin
      session.closed <- true;
      Log.debug (fun m -> m "yamux: muxer closed, signalling EOF to %d stream(s)"
                            (Hashtbl.length session.streams));
      Hashtbl.iter (fun _ st -> Eio.Stream.add st.incoming None) session.streams;
      Eio.Stream.add session.accept_q None
    end
  in
  let rec loop () =
    match read_frame session.r with
    | f -> handle session f; loop ()
    (* End_of_file is a clean peer close; any other exception is a transport
       fault (connection reset, write failure during replenish, ...). Either
       way this one connection is finished — never let it escape and fell the
       whole node. *)
    | exception _ -> ()
  in
  (try loop () with _ -> ());
  close ();
  `Stop_daemon

let create ~sw ~is_client r w =
  let session =
    {
      r;
      w;
      is_client;
      next_id = (if is_client then 1 else 2);
      closed = false;
      streams = Hashtbl.create 16;
      accept_q = Eio.Stream.create 64;
      write_mutex = Eio.Mutex.create ();
      id_mutex = Eio.Mutex.create ();
    }
  in
  Eio.Fiber.fork_daemon ~sw (read_loop session);
  session

let open_stream session =
  let id =
    Eio.Mutex.use_rw ~protect:true session.id_mutex (fun () ->
        let id = session.next_id in
        session.next_id <- id + 2;
        id)
  in
  let st = new_stream session id in
  Hashtbl.replace session.streams id st;
  emit session { typ = Data; flags = f_syn; stream_id = id; length = 0; data = "" };
  to_flow st

(* Blocks for the next inbound stream. Raises [End_of_file] once the muxer has
   closed, so server accept loops terminate instead of hanging forever. *)
let accept_stream session =
  match Eio.Stream.take session.accept_q with
  | None ->
    Eio.Stream.add session.accept_q None;  (* re-arm so concurrent acceptors also see EOF *)
    raise End_of_file
  | Some st -> to_flow st

(* Politely tell the peer we are done (yamux GoAway, normal code 0) before the
   connection is torn down. Best-effort: the socket may already be gone. *)
let shutdown session =
  if not session.closed then
    try emit session { typ = Go_away; flags = 0; stream_id = 0; length = 0; data = "" }
    with _ -> ()
