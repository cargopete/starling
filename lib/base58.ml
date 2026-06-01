let alphabet = "123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz"

(* Reverse lookup: ASCII byte -> base58 digit value, or -1 if not in alphabet. *)
let rev =
  let t = Array.make 128 (-1) in
  String.iteri (fun i c -> t.(Char.code c) <- i) alphabet;
  t

let encode (input : string) : string =
  let n = String.length input in
  let zeros = ref 0 in
  while !zeros < n && input.[!zeros] = '\000' do
    incr zeros
  done;
  (* ceil(log256 / log58) ~ 1.37 bytes of output per input byte. *)
  let size = ((n - !zeros) * 138 / 100) + 1 in
  let b58 = Bytes.make size '\000' in
  let length = ref 0 in
  for i = !zeros to n - 1 do
    let carry = ref (Char.code input.[i]) in
    let j = ref (size - 1) in
    while !carry <> 0 || !j > size - 1 - !length do
      carry := !carry + (256 * Char.code (Bytes.get b58 !j));
      Bytes.set b58 !j (Char.chr (!carry mod 58));
      carry := !carry / 58;
      decr j
    done;
    length := size - 1 - !j
  done;
  let buf = Buffer.create (size + !zeros) in
  for _ = 1 to !zeros do
    Buffer.add_char buf '1'
  done;
  let it = ref (size - !length) in
  while !it < size do
    Buffer.add_char buf alphabet.[Char.code (Bytes.get b58 !it)];
    incr it
  done;
  Buffer.contents buf

let decode (input : string) : string =
  let n = String.length input in
  let zeros = ref 0 in
  while !zeros < n && input.[!zeros] = '1' do
    incr zeros
  done;
  (* ceil(log58 / log256) ~ 0.733 bytes of output per input char. *)
  let size = ((n - !zeros) * 733 / 1000) + 1 in
  let b256 = Bytes.make size '\000' in
  let length = ref 0 in
  for i = !zeros to n - 1 do
    let c = input.[i] in
    let digit = if Char.code c < 128 then rev.(Char.code c) else -1 in
    if digit < 0 then invalid_arg "Base58.decode: invalid character";
    let carry = ref digit in
    let j = ref (size - 1) in
    while !carry <> 0 || !j > size - 1 - !length do
      carry := !carry + (58 * Char.code (Bytes.get b256 !j));
      Bytes.set b256 !j (Char.chr (!carry land 0xff));
      carry := !carry lsr 8;
      decr j
    done;
    length := size - 1 - !j
  done;
  let buf = Buffer.create (size + !zeros) in
  for _ = 1 to !zeros do
    Buffer.add_char buf '\000'
  done;
  let it = ref (size - !length) in
  while !it < size do
    Buffer.add_char buf (Bytes.get b256 !it);
    incr it
  done;
  Buffer.contents buf
