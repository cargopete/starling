type t = { identity_key : string; identity_sig : string }

let encode ~identity_key ~identity_sig =
  let buf = Buffer.create 128 in
  Pbuf.bytes_field buf 1 identity_key;
  Pbuf.bytes_field buf 2 identity_sig;
  Buffer.contents buf

let decode s =
  match Pbuf.fields s with
  | exception _ -> None
  | fs -> (
    match (Pbuf.find_bytes 1 fs, Pbuf.find_bytes 2 fs) with
    | Some identity_key, Some identity_sig -> Some { identity_key; identity_sig }
    | _ -> None)
