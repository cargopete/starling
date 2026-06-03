open Starling

(* A scratch path under the system temp dir, unique-ish per test. *)
let tmp name = Filename.concat (Filename.get_temp_dir_name ()) ("starling-idtest-" ^ name)

let persists_across_reload () =
  let path = tmp "persist.key" in
  (try Sys.remove path with _ -> ());
  let k1 = Identity_store.load_or_create path in
  let k2 = Identity_store.load_or_create path in
  Alcotest.(check string)
    "same peer id on reload"
    (Peer_id.to_string (Keys.peer_id k1))
    (Peer_id.to_string (Keys.peer_id k2));
  Sys.remove path

let creates_32_byte_seed () =
  let path = tmp "seed.key" in
  (try Sys.remove path with _ -> ());
  ignore (Identity_store.load_or_create path);
  let ic = open_in_bin path in
  let len = in_channel_length ic in
  close_in ic;
  Alcotest.(check int) "seed is 32 bytes" 32 len;
  Sys.remove path

let perms_are_0600 () =
  let path = tmp "perms.key" in
  (try Sys.remove path with _ -> ());
  ignore (Identity_store.load_or_create path);
  let st = Unix.stat path in
  Alcotest.(check int) "mode is 0o600" 0o600 (st.st_perm land 0o777);
  Sys.remove path

let rejects_bad_length () =
  let path = tmp "bad.key" in
  let oc = open_out_bin path in
  output_string oc "too short";
  close_out oc;
  (try
     ignore (Identity_store.load_or_create path);
     Alcotest.fail "expected a failure on a non-32-byte seed"
   with Failure _ -> ());
  Sys.remove path

let () =
  Mirage_crypto_rng_unix.use_default ();
  Alcotest.run "identity_store"
    [
      ( "persistence",
        [
          Alcotest.test_case "stable peer id across reload" `Quick persists_across_reload;
          Alcotest.test_case "seed is 32 bytes" `Quick creates_32_byte_seed;
          Alcotest.test_case "private key file is 0600" `Quick perms_are_0600;
          Alcotest.test_case "rejects malformed seed" `Quick rejects_bad_length;
        ] );
    ]
