let write buf n =
  if n < 0 then invalid_arg "Varint.write: negative";
  let rec go n =
    if n < 0x80 then Buffer.add_char buf (Char.chr n)
    else begin
      Buffer.add_char buf (Char.chr (0x80 lor (n land 0x7f)));
      go (n lsr 7)
    end
  in
  go n

let encode n =
  let buf = Buffer.create 4 in
  write buf n;
  Buffer.contents buf

let read s pos =
  let len = String.length s in
  let rec go shift pos acc =
    if pos >= len then invalid_arg "Varint.read: truncated";
    let byte = Char.code s.[pos] in
    let acc = acc lor ((byte land 0x7f) lsl shift) in
    if byte land 0x80 = 0 then (acc, pos + 1)
    else if shift >= 56 then invalid_arg "Varint.read: overflow"
    else go (shift + 7) (pos + 1) acc
  in
  go 0 pos 0
