(** Yamux stream multiplexing ([/yamux/1.0.0]) over a single duplex byte stream
    (here, the Noise {!Secure_flow}).

    A 12-byte big-endian frame header carries a type, flags, stream id, and
    length. A background daemon fiber reads frames and demultiplexes them to
    per-stream queues; each stream is itself an {!Eio.Flow.two_way}, so
    {!Multistream} and protocol handlers (ping, identify) compose over it.

    Flow control: streams start with a 256 KiB window; the window is replenished
    as the application {e consumes} data (real read-side backpressure — a slow
    reader throttles the sender), and we honour the peer's windows when sending. *)

val protocol_id : string
(** ["/yamux/1.0.0"] *)

type session
(** A live multiplexed connection. *)

(** A bidirectional stream — an Eio flow. *)
type stream = Eio.Flow.two_way_ty Eio.Resource.t

(** Keep-alive configuration. [sleep] is a clock-backed delay supplied by the
    caller (e.g. [Eio.Time.sleep clock]); [interval] is the gap between probes
    and [timeout] how long to wait for each pong, both in seconds. *)
type keepalive = { sleep : float -> unit; interval : float; timeout : float }

(** [create ~sw ?keepalive ~is_client r w] starts a session over [r]/[w] and
    forks the read-loop as a daemon on [sw]. The connection initiator passes
    [is_client:true] (odd stream ids); the listener [false] (even ids).

    With [?keepalive] set, a daemon periodically pings the peer and reaps the
    connection if a pong does not arrive in time — so a peer that completes the
    handshake then goes silent cannot pin a fiber and fd indefinitely. *)
val create :
  sw:Eio.Switch.t ->
  ?keepalive:keepalive ->
  is_client:bool ->
  Eio.Buf_read.t ->
  Eio.Buf_write.t ->
  session

(** Open a new outbound stream (sends SYN). *)
val open_stream : session -> stream

(** Accept the next inbound stream (blocks until a peer opens one).
    Raises [End_of_file] once the muxer has closed (peer disconnect or
    transport fault), so accept loops terminate rather than block forever. *)
val accept_stream : session -> stream

(** Send a yamux GoAway (normal, code 0) to tell the peer we are closing down.
    Best-effort — does nothing if the muxer is already closed. *)
val shutdown : session -> unit

(** {2 Frame codec — exposed for testing} *)

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

(** Encode a frame (12-byte header followed by [data] for [Data] frames). *)
val encode : frame -> string

(** Decode a frame from a complete buffer (header + any data). *)
val decode : string -> frame
