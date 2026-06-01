type t = { code : int; digest : string }

let identity = 0x00
let sha2_256 = 0x12

let identity_of data = { code = identity; digest = data }

let sha256_of data =
  let digest = Digestif.SHA256.(to_raw_string (digest_string data)) in
  { code = sha2_256; digest }

let to_bytes t =
  let buf = Buffer.create (2 + String.length t.digest) in
  Varint.write buf t.code;
  Varint.write buf (String.length t.digest);
  Buffer.add_string buf t.digest;
  Buffer.contents buf

let of_bytes s =
  let code, pos = Varint.read s 0 in
  let len, pos = Varint.read s pos in
  if String.length s - pos <> len then
    invalid_arg "Multihash.of_bytes: length prefix mismatch";
  { code; digest = String.sub s pos len }
