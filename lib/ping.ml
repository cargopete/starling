let protocol_id = "/ipfs/ping/1.0.0"
let size = 32

let ping ~clock r w =
  let payload = Mirage_crypto_rng.generate size in
  let t0 = Eio.Time.now clock in
  Eio.Buf_write.string w payload;
  Eio.Buf_write.flush w;
  let echo = Eio.Buf_read.take size r in
  let t1 = Eio.Time.now clock in
  if not (String.equal echo payload) then failwith "Ping: echo did not match";
  t1 -. t0

let handle r w =
  let rec loop () =
    match Eio.Buf_read.take size r with
    | exception End_of_file -> ()
    | payload ->
      Eio.Buf_write.string w payload;
      Eio.Buf_write.flush w;
      loop ()
  in
  loop ()
