(* A Peer ID is just the multihash bytes; we keep them and render lazily. *)
type t = string

(* libp2p crypto.proto (proto2):
     enum KeyType { RSA=0; Ed25519=1; Secp256k1=2; ECDSA=3; }
     message PublicKey { required KeyType Type = 1; required bytes Data = 2; }
   Hand-encoded: field 1 is a varint (wire type 0, tag 0x08); field 2 is a
   length-delimited bytes (wire type 2, tag 0x12). *)
let marshal_ed25519_pubkey raw =
  let buf = Buffer.create (4 + String.length raw) in
  Pbuf.varint_field buf 1 1;
  (* KeyType.Ed25519 = 1 *)
  Pbuf.bytes_field buf 2 raw;
  Buffer.contents buf

let ed25519_raw_of_proto s =
  match Pbuf.fields s with
  | exception _ -> None
  | fs -> (
    match (Pbuf.find_varint 1 fs, Pbuf.find_bytes 2 fs) with
    | Some 1, Some raw when String.length raw = 32 -> Some raw
    | _ -> None)

(* Per spec: serialized keys <= 42 bytes use the identity multihash so the key
   is recoverable from the Peer ID; larger keys (RSA) use sha2-256. *)
let of_marshalled_key marshalled =
  let mh =
    if String.length marshalled <= 42 then Multihash.identity_of marshalled
    else Multihash.sha256_of marshalled
  in
  Multihash.to_bytes mh

let of_ed25519_pubkey raw = of_marshalled_key (marshal_ed25519_pubkey raw)
let to_multihash t = Multihash.of_bytes t
let to_bytes t = t
let of_bytes s = s
let to_string t = Base58.encode t
let of_string s = Base58.decode s
let equal = String.equal
