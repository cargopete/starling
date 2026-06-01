(* A Peer ID is just the multihash bytes; we keep them and render lazily. *)
type t = string

(* libp2p crypto.proto (proto2):
     enum KeyType { RSA=0; Ed25519=1; Secp256k1=2; ECDSA=3; }
     message PublicKey { required KeyType Type = 1; required bytes Data = 2; }
   Hand-encoded: field 1 is a varint (wire type 0, tag 0x08); field 2 is a
   length-delimited bytes (wire type 2, tag 0x12). *)
let marshal_ed25519_pubkey raw =
  let buf = Buffer.create (4 + String.length raw) in
  Buffer.add_char buf '\x08';
  (* tag: field 1, varint *)
  Buffer.add_char buf '\x01';
  (* KeyType.Ed25519 = 1 *)
  Buffer.add_char buf '\x12';
  (* tag: field 2, length-delimited *)
  Varint.write buf (String.length raw);
  Buffer.add_string buf raw;
  Buffer.contents buf

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
