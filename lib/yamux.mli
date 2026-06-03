(** Yamux stream multiplexing ([/yamux/1.0.0]) over a single duplex byte stream
    (here, the Noise {!Secure_flow}).

    A 12-byte big-endian frame header carries a type, flags, stream id, and
    length. A background daemon fiber reads frames and demultiplexes them to
    per-stream queues; each stream is itself an {!Eio.Flow.two_way}, so
    {!Multistream} and protocol handlers (ping, identify) compose over it.

    Flow control: streams start with a 256 KiB window; on receiving data we
    immediately return a window update of the same size (a deliberate MVP
    simplification — no read-side backpressure), and we honour the peer's
    windows when sending. *)

val protocol_id : string
(** ["/yamux/1.0.0"] *)

type session
(** A live multiplexed connection. *)

(** A bidirectional stream — an Eio flow. *)
type stream = Eio.Flow.two_way_ty Eio.Resource.t

(** [create ~sw ~is_client r w] starts a session over [r]/[w] and forks the
    read-loop as a daemon on [sw]. The connection initiator passes
    [is_client:true] (odd stream ids); the listener [false] (even ids). *)
val create :
  sw:Eio.Switch.t ->
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
