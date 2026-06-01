type t = {
  protocol_version : string option;
  agent_version : string option;
  public_key : string option;
  listen_addrs : string list;
  protocols : string list;
  observed_addr : string option;
}

let protocol_id = "/ipfs/id/1.0.0"

let empty =
  {
    protocol_version = None;
    agent_version = None;
    public_key = None;
    listen_addrs = [];
    protocols = [];
    observed_addr = None;
  }

let encode t =
  let buf = Buffer.create 256 in
  Option.iter (fun v -> Pbuf.bytes_field buf 1 v) t.public_key;
  List.iter (fun a -> Pbuf.bytes_field buf 2 a) t.listen_addrs;
  List.iter (fun p -> Pbuf.bytes_field buf 3 p) t.protocols;
  Option.iter (fun v -> Pbuf.bytes_field buf 4 v) t.observed_addr;
  Option.iter (fun v -> Pbuf.bytes_field buf 5 v) t.protocol_version;
  Option.iter (fun v -> Pbuf.bytes_field buf 6 v) t.agent_version;
  Buffer.contents buf

let decode s =
  match Pbuf.fields s with
  | exception _ -> empty
  | fs ->
    let all n =
      List.filter_map (function f, Pbuf.Bytes b when f = n -> Some b | _ -> None) fs
    in
    let one n = match all n with x :: _ -> Some x | [] -> None in
    {
      public_key = one 1;
      listen_addrs = all 2;
      protocols = all 3;
      observed_addr = one 4;
      protocol_version = one 5;
      agent_version = one 6;
    }

let peer_id t =
  match t.public_key with
  | None -> None
  | Some proto -> (
    match Peer_id.ed25519_raw_of_proto proto with
    | Some raw -> Some (Peer_id.of_ed25519_pubkey raw)
    | None -> None)

let respond w t =
  let body = encode t in
  Eio.Buf_write.string w (Varint.encode (String.length body));
  Eio.Buf_write.string w body;
  Eio.Buf_write.flush w

(* Read an unsigned-varint from a buffered reader. *)
let read_varint r =
  let rec go shift acc =
    let b = Char.code (Eio.Buf_read.any_char r) in
    let acc = acc lor ((b land 0x7f) lsl shift) in
    if b land 0x80 = 0 then acc else go (shift + 7) acc
  in
  go 0 0

let request r =
  let len = read_varint r in
  decode (Eio.Buf_read.take len r)
