(** The libp2p [NoiseHandshakePayload] (proto2), carried encrypted in XX
    messages 2 and 3:

    {[
      message NoiseHandshakePayload {
        optional bytes identity_key = 1;   // marshalled PublicKey protobuf
        optional bytes identity_sig = 2;   // sig over "noise-libp2p-static-key:" ‖ static_pub
        // field 4 = NoiseExtensions — omitted for the MVP
      }
    ]} *)

type t = {
  identity_key : string;  (** marshalled Ed25519 [PublicKey] protobuf *)
  identity_sig : string;  (** Ed25519 signature binding the Noise static key *)
}

(** [encode ~identity_key ~identity_sig] is the wire bytes (no extensions). *)
val encode : identity_key:string -> identity_sig:string -> string

(** [decode s] parses the payload, or [None] if either field is missing. *)
val decode : string -> t option
