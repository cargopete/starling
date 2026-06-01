let protocol_id = "/multistream/1.0.0"

type error =
  [ `Protocol_mismatch of string
  | `Unsupported
  | `Unexpected of string
  | `Closed
  ]

(* Read an unsigned-varint from the buffered reader, one byte at a time. *)
let read_varint r =
  let rec go shift acc =
    let b = Char.code (Eio.Buf_read.any_char r) in
    let acc = acc lor ((b land 0x7f) lsl shift) in
    if b land 0x80 = 0 then acc
    else if shift >= 56 then failwith "Multistream: varint overflow"
    else go (shift + 7) acc
  in
  go 0 0

let write_message w msg =
  let line = msg ^ "\n" in
  Eio.Buf_write.string w (Varint.encode (String.length line));
  Eio.Buf_write.string w line

let read_message r =
  let len = read_varint r in
  let s = Eio.Buf_read.take len r in
  if len > 0 && s.[len - 1] = '\n' then String.sub s 0 (len - 1) else s

let send w msg =
  write_message w msg;
  Eio.Buf_write.flush w

let dial r w ~proto =
  write_message w protocol_id;
  send w proto;
  let their_header = read_message r in
  if not (String.equal their_header protocol_id) then
    Error (`Protocol_mismatch their_header)
  else
    let reply = read_message r in
    if String.equal reply proto then Ok ()
    else if String.equal reply "na" then Error `Unsupported
    else Error (`Unexpected reply)

let listen r w ~supported =
  send w protocol_id;
  let their_header = read_message r in
  if not (String.equal their_header protocol_id) then
    Error (`Protocol_mismatch their_header)
  else
    let rec loop () =
      match read_message r with
      | exception End_of_file -> Error `Closed
      | proposal ->
        if List.mem proposal supported then begin
          send w proposal;
          Ok proposal
        end
        else begin
          send w "na";
          loop ()
        end
    in
    loop ()
