type value =
  | Varint of int
  | Bytes of string

let key field wire = (field lsl 3) lor wire

let varint_field buf field v =
  Varint.write buf (key field 0);
  Varint.write buf v

let bytes_field buf field s =
  Varint.write buf (key field 2);
  Varint.write buf (String.length s);
  Buffer.add_string buf s

let fields s =
  let len = String.length s in
  let rec go pos acc =
    if pos >= len then List.rev acc
    else
      let tag, pos = Varint.read s pos in
      let field = tag lsr 3 and wire = tag land 0x7 in
      match wire with
      | 0 ->
        let v, pos = Varint.read s pos in
        go pos ((field, Varint v) :: acc)
      | 2 ->
        let l, pos = Varint.read s pos in
        if pos + l > len then invalid_arg "Pbuf: truncated length-delimited field";
        go (pos + l) ((field, Bytes (String.sub s pos l)) :: acc)
      | 5 -> go (pos + 4) acc (* fixed32 — skip *)
      | 1 -> go (pos + 8) acc (* fixed64 — skip *)
      | _ -> invalid_arg "Pbuf: unsupported wire type"
  in
  go 0 []

let find_bytes n fields =
  List.find_map (function f, Bytes b when f = n -> Some b | _ -> None) fields

let find_varint n fields =
  List.find_map (function f, Varint v when f = n -> Some v | _ -> None) fields
