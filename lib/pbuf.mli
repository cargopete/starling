(** A minimal protobuf (proto2/proto3 wire) helper — just enough for libp2p's
    handful of small messages. We hand-roll rather than pull a codegen toolchain
    for three two-field messages. *)

(** A decoded field value. *)
type value =
  | Varint of int
  | Bytes of string

(** [varint_field buf n v] appends field number [n] (wire type 0) with value [v]. *)
val varint_field : Buffer.t -> int -> int -> unit

(** [bytes_field buf n s] appends field number [n] (wire type 2) with bytes [s]. *)
val bytes_field : Buffer.t -> int -> string -> unit

(** [fields s] decodes all top-level fields as [(field_number, value)] pairs.
    Fixed32/Fixed64 fields are skipped; raises [Invalid_argument] on an unknown
    wire type or a truncated message. *)
val fields : string -> (int * value) list

(** [find_bytes n fields] is the first [Bytes] value for field number [n]. *)
val find_bytes : int -> (int * value) list -> string option

(** [find_varint n fields] is the first [Varint] value for field number [n]. *)
val find_varint : int -> (int * value) list -> int option
