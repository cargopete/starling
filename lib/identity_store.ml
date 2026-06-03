(* Persistent host identity, stored as a raw 32-byte Ed25519 seed. The file
   holds a private key, so it is written 0o600 in a 0o700 directory. *)

let seed_len = 32

let default_path () =
  match Sys.getenv_opt "STARLING_IDENTITY" with
  | Some p -> p
  | None -> (
    match Sys.getenv_opt "HOME" with
    | Some home -> Filename.concat (Filename.concat home ".starling") "identity.key"
    | None -> failwith "identity: neither STARLING_IDENTITY nor HOME is set")

let read_file path =
  let ic = open_in_bin path in
  Fun.protect ~finally:(fun () -> close_in_noerr ic) (fun () ->
      really_input_string ic (in_channel_length ic))

(* Write [data] to [path] with mode 0o600, creating the parent dir 0o700. *)
let write_private path data =
  let dir = Filename.dirname path in
  if not (Sys.file_exists dir) then Unix.mkdir dir 0o700;
  let fd = Unix.openfile path [ O_WRONLY; O_CREAT; O_TRUNC ] 0o600 in
  Fun.protect ~finally:(fun () -> Unix.close fd) (fun () ->
      let b = Bytes.of_string data in
      let n = Unix.write fd b 0 (Bytes.length b) in
      if n <> Bytes.length b then failwith "identity: short write")

let load_or_create path =
  if Sys.file_exists path then begin
    let seed = read_file path in
    if String.length seed <> seed_len then
      failwith
        (Printf.sprintf "identity: %s is %d bytes, expected a %d-byte seed"
           path (String.length seed) seed_len);
    Keys.of_seed seed
  end
  else begin
    let k = Keys.generate () in
    write_private path (Keys.private_key_raw k);
    k
  end
