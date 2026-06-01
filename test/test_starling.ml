open Starling

let hex s = Hex.show (Hex.of_string s)
let unhex h = Hex.to_string (`Hex h)

(* ------------------------------------------------------------------ Varint *)

let varint_roundtrip () =
  List.iter
    (fun n ->
      let s = Varint.encode n in
      let v, pos = Varint.read s 0 in
      Alcotest.(check int) (Printf.sprintf "value %d" n) n v;
      Alcotest.(check int)
        (Printf.sprintf "consumed all of %d" n)
        (String.length s) pos)
    [ 0; 1; 127; 128; 255; 300; 16383; 16384; 0x01A5; 1_000_000; max_int ]

let varint_known () =
  (* unsigned-varint spec examples *)
  Alcotest.(check string) "1 -> 01" "01" (hex (Varint.encode 1));
  Alcotest.(check string) "127 -> 7f" "7f" (hex (Varint.encode 127));
  Alcotest.(check string) "128 -> 8001" "8001" (hex (Varint.encode 128));
  Alcotest.(check string) "255 -> ff01" "ff01" (hex (Varint.encode 255));
  Alcotest.(check string) "300 -> ac02" "ac02" (hex (Varint.encode 300))

(* ------------------------------------------------------------------ Base58 *)

let base58_known () =
  (* Well-known raw base58 vector. *)
  Alcotest.(check string)
    "\"Hello World!\" -> 2NEpo7TZRRrLZSi2U" "2NEpo7TZRRrLZSi2U"
    (Base58.encode "Hello World!");
  Alcotest.(check string) "empty -> empty" "" (Base58.encode "");
  (* Leading zero bytes become leading '1's. *)
  Alcotest.(check string) "0x00 -> 1" "1" (Base58.encode "\000");
  Alcotest.(check string) "0x0000 -> 11" "11" (Base58.encode "\000\000")

let base58_roundtrip () =
  List.iter
    (fun s ->
      Alcotest.(check string) ("roundtrip " ^ hex s) s (Base58.decode (Base58.encode s)))
    [ ""; "\000"; "\000\000abc"; "Hello World!"; unhex "deadbeef"; unhex "00112233445566778899" ]

(* --------------------------------------------------------------- Multihash *)

let multihash_sha256_empty () =
  (* sha256("") well-known digest, wrapped as multihash 0x12 0x20 <digest>. *)
  let mh = Multihash.sha256_of "" in
  Alcotest.(check int) "code = sha2-256" Multihash.sha2_256 mh.code;
  Alcotest.(check string)
    "sha256 empty digest"
    "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"
    (hex mh.digest);
  Alcotest.(check string)
    "multihash bytes"
    ("1220" ^ "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
    (hex (Multihash.to_bytes mh))

let multihash_identity () =
  let mh = Multihash.identity_of "abc" in
  Alcotest.(check string) "identity bytes" ("0003" ^ hex "abc") (hex (Multihash.to_bytes mh));
  let back = Multihash.of_bytes (Multihash.to_bytes mh) in
  Alcotest.(check int) "code roundtrip" Multihash.identity back.code;
  Alcotest.(check string) "digest roundtrip" "abc" back.digest

(* --------------------------------------------------------------- Multiaddr *)

let multiaddr_known_binary () =
  let ma = Multiaddr.of_string "/ip4/127.0.0.1/tcp/4001" in
  (* /ip4 = 04, 127.0.0.1 = 7f000001 ; /tcp = 06, 4001 = 0x0fa1 *)
  Alcotest.(check string)
    "/ip4/127.0.0.1/tcp/4001 binary" "047f000001060fa1"
    (hex (Multiaddr.to_bytes ma))

let multiaddr_roundtrip () =
  List.iter
    (fun s ->
      let ma = Multiaddr.of_string s in
      Alcotest.(check string) ("string roundtrip " ^ s) s (Multiaddr.to_string ma);
      let ma' = Multiaddr.of_bytes (Multiaddr.to_bytes ma) in
      Alcotest.(check string) ("binary roundtrip " ^ s) s (Multiaddr.to_string ma'))
    [
      "/ip4/127.0.0.1/tcp/4001";
      "/ip6/::1/tcp/9000";
      "/ip4/0.0.0.0/tcp/0";
    ]

let multiaddr_endpoint () =
  let ma = Multiaddr.of_string "/ip4/10.0.0.5/tcp/4001" in
  match Multiaddr.tcp_endpoint ma with
  | Some (h, p) ->
    Alcotest.(check string) "host" "10.0.0.5" h;
    Alcotest.(check int) "port" 4001 p
  | None -> Alcotest.fail "expected an endpoint"

(* ----------------------------------------------------------------- Peer ID *)

(* A fixed Ed25519 seed gives a deterministic Peer ID. We anchor on the
   structural invariants that prove the protobuf -> multihash -> base58 layering
   is correct: Ed25519 identity-multihash Peer IDs always render "12D3Koo...". *)
let fixed_seed = unhex "0101010101010101010101010101010101010101010101010101010101010101"

let peer_id_ed25519_prefix () =
  let k = Keys.of_seed fixed_seed in
  let id = Keys.peer_id k in
  let s = Peer_id.to_string id in
  Alcotest.(check bool)
    (Printf.sprintf "Ed25519 peer id %s starts with 12D3Koo" s)
    true
    (String.length s >= 7 && String.sub s 0 7 = "12D3Koo")

let peer_id_structure () =
  let k = Keys.of_seed fixed_seed in
  let id = Keys.peer_id k in
  (* base58 text round-trips to the same bytes *)
  Alcotest.(check bool) "text roundtrip" true
    (Peer_id.equal id (Peer_id.of_string (Peer_id.to_string id)));
  (* the multihash is an identity multihash wrapping the marshalled pubkey *)
  let mh = Peer_id.to_multihash id in
  Alcotest.(check int) "identity multihash" Multihash.identity mh.code;
  Alcotest.(check string)
    "wraps marshalled pubkey" (Keys.public_key_proto k) mh.digest

let keys_sign_verify () =
  let k = Keys.of_seed fixed_seed in
  let msg = "noise-libp2p-static-key:hello" in
  let sg = Keys.sign k msg in
  Alcotest.(check bool) "valid signature" true
    (Keys.verify ~raw_pub:(Keys.public_key_raw k) ~signature:sg msg);
  Alcotest.(check bool) "rejects tampered message" false
    (Keys.verify ~raw_pub:(Keys.public_key_raw k) ~signature:sg (msg ^ "!"))

let () =
  Alcotest.run "starling"
    [
      ( "varint",
        [
          Alcotest.test_case "roundtrip" `Quick varint_roundtrip;
          Alcotest.test_case "known vectors" `Quick varint_known;
        ] );
      ( "base58",
        [
          Alcotest.test_case "known vectors" `Quick base58_known;
          Alcotest.test_case "roundtrip" `Quick base58_roundtrip;
        ] );
      ( "multihash",
        [
          Alcotest.test_case "sha256 empty" `Quick multihash_sha256_empty;
          Alcotest.test_case "identity" `Quick multihash_identity;
        ] );
      ( "multiaddr",
        [
          Alcotest.test_case "known binary" `Quick multiaddr_known_binary;
          Alcotest.test_case "roundtrip" `Quick multiaddr_roundtrip;
          Alcotest.test_case "tcp endpoint" `Quick multiaddr_endpoint;
        ] );
      ( "peer_id",
        [
          Alcotest.test_case "ed25519 prefix" `Quick peer_id_ed25519_prefix;
          Alcotest.test_case "structure" `Quick peer_id_structure;
          Alcotest.test_case "sign/verify" `Quick keys_sign_verify;
        ] );
    ]
