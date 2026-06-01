type component =
  | Ip4 of string
  | Ip6 of string
  | Tcp of int
  | P2p of Peer_id.t

type t = component list

let code_ip4 = 0x04
let code_tcp = 0x06
let code_ip6 = 0x29
let code_p2p = 0x01A5

let of_string s =
  if String.length s = 0 || s.[0] <> '/' then
    invalid_arg "Multiaddr.of_string: must start with '/'";
  (* Drop the leading empty segment from the initial '/'. *)
  let parts =
    String.split_on_char '/' s |> List.filter (fun p -> p <> "")
  in
  let rec go = function
    | [] -> []
    | "ip4" :: v :: rest -> Ip4 v :: go rest
    | "ip6" :: v :: rest -> Ip6 v :: go rest
    | "tcp" :: v :: rest -> Tcp (int_of_string v) :: go rest
    | "p2p" :: v :: rest -> P2p (Peer_id.of_string v) :: go rest
    | proto :: _ -> invalid_arg ("Multiaddr.of_string: unsupported /" ^ proto)
  in
  go parts

let component_to_string = function
  | Ip4 v -> "/ip4/" ^ v
  | Ip6 v -> "/ip6/" ^ v
  | Tcp p -> "/tcp/" ^ string_of_int p
  | P2p id -> "/p2p/" ^ Peer_id.to_string id

let to_string t = String.concat "" (List.map component_to_string t)

let port_to_bytes p =
  let b = Bytes.create 2 in
  Bytes.set_uint16_be b 0 p;
  Bytes.to_string b

let component_to_bytes c =
  let buf = Buffer.create 8 in
  (match c with
  | Ip4 v ->
    Varint.write buf code_ip4;
    Buffer.add_string buf (Ipaddr.V4.to_octets (Ipaddr.V4.of_string_exn v))
  | Ip6 v ->
    Varint.write buf code_ip6;
    Buffer.add_string buf (Ipaddr.V6.to_octets (Ipaddr.V6.of_string_exn v))
  | Tcp p ->
    Varint.write buf code_tcp;
    Buffer.add_string buf (port_to_bytes p)
  | P2p id ->
    Varint.write buf code_p2p;
    let mh = Peer_id.to_bytes id in
    Varint.write buf (String.length mh);
    Buffer.add_string buf mh);
  Buffer.contents buf

let to_bytes t = String.concat "" (List.map component_to_bytes t)

let of_bytes s =
  let len = String.length s in
  let rec go pos acc =
    if pos >= len then List.rev acc
    else begin
      let code, pos = Varint.read s pos in
      if code = code_ip4 then
        let v = Ipaddr.V4.to_string (Ipaddr.V4.of_octets_exn (String.sub s pos 4)) in
        go (pos + 4) (Ip4 v :: acc)
      else if code = code_ip6 then
        let v = Ipaddr.V6.to_string (Ipaddr.V6.of_octets_exn (String.sub s pos 16)) in
        go (pos + 16) (Ip6 v :: acc)
      else if code = code_tcp then
        let p = Bytes.get_uint16_be (Bytes.unsafe_of_string s) pos in
        go (pos + 2) (Tcp p :: acc)
      else if code = code_p2p then begin
        let mhlen, pos = Varint.read s pos in
        let mh = String.sub s pos mhlen in
        go (pos + mhlen) (P2p (Peer_id.of_bytes mh) :: acc)
      end
      else invalid_arg (Printf.sprintf "Multiaddr.of_bytes: unsupported code 0x%x" code)
    end
  in
  go 0 []

let tcp_endpoint t =
  let host =
    List.find_map
      (function Ip4 v | Ip6 v -> Some v | _ -> None)
      t
  in
  let port = List.find_map (function Tcp p -> Some p | _ -> None) t in
  match (host, port) with
  | Some h, Some p -> Some (h, p)
  | _ -> None
