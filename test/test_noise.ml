open Starling

let hex s = Hex.show (Hex.of_string s)
let unhex h = Hex.to_string (`Hex h)

(* ---------------------------------------------- AEAD: RFC 8439 §2.8.2 vector *)
(* The gold-standard external anchor: confirms ChaCha20-Poly1305 in IETF mode
   (12-byte nonce) with associated data produces exactly the spec ciphertext+tag.
   This pins libp2p-Noise interop landmine #1 — the nonce mode. *)
let rfc8439_aead () =
  let key =
    Mirage_crypto.Chacha20.of_secret
      (unhex "808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
  in
  let nonce = unhex "070000004041424344454647" in
  let adata = unhex "50515253c0c1c2c3c4c5c6c7" in
  let pt =
    "Ladies and Gentlemen of the class of '99: If I could offer you only one \
     tip for the future, sunscreen would be it."
  in
  let out = Mirage_crypto.Chacha20.authenticate_encrypt ~key ~nonce ~adata pt in
  let expect =
    "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d6"
    ^ "3dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b36"
    ^ "92ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc"
    ^ "3ff4def08e4b7a9de576d26586cec64b6116"
    ^ "1ae10b594f09e26a7e902ecbd0600691"
  in
  Alcotest.(check string) "rfc8439 ciphertext+tag" expect (hex out)

(* --------------------------------------------------------------- CipherState *)
let cipherstate_roundtrip () =
  let key = String.make 32 '\042' in
  let enc = Noise_cipher_state.init key in
  let dec = Noise_cipher_state.init key in
  let ad = "associated" in
  let enc1, c1 = Noise_cipher_state.encrypt_with_ad enc ~ad "hello" in
  let _, c2 = Noise_cipher_state.encrypt_with_ad enc1 ~ad "hello" in
  Alcotest.(check bool) "nonce advanced -> ciphertext differs" true (c1 <> c2);
  (match Noise_cipher_state.decrypt_with_ad dec ~ad c1 with
  | Ok (_, pt) -> Alcotest.(check string) "decrypts" "hello" pt
  | Error _ -> Alcotest.fail "decrypt failed");
  let tampered = Bytes.of_string c1 in
  Bytes.set tampered 0 (Char.chr (Char.code (Bytes.get tampered 0) lxor 0x01));
  match Noise_cipher_state.decrypt_with_ad dec ~ad (Bytes.to_string tampered) with
  | Error `Decrypt_failed -> ()
  | Ok _ -> Alcotest.fail "tampered ciphertext was accepted"

let cipherstate_passthrough () =
  let _, ct = Noise_cipher_state.encrypt_with_ad Noise_cipher_state.empty ~ad:"x" "abc" in
  Alcotest.(check string) "empty key is identity" "abc" ct

(* ------------------------------------------------------------ SymmetricState *)
let protocol_name = "Noise_XX_25519_ChaChaPoly_SHA256"

let symmetric_initialize () =
  (* Exactly 32 bytes, so h is the name verbatim with no padding. *)
  Alcotest.(check int) "protocol name is 32 bytes" 32 (String.length protocol_name);
  let ss = Noise_symmetric_state.initialize ~protocol_name in
  Alcotest.(check string) "h = name (already 32 bytes)"
    (hex protocol_name)
    (hex (Noise_symmetric_state.handshake_hash ss));
  Alcotest.(check string) "ck = h initially"
    (hex (Noise_symmetric_state.handshake_hash ss))
    (hex (Noise_symmetric_state.chaining_key ss))

(* Drive two SymmetricStates through identical mixes, then confirm one can
   encrypt a payload the other decrypts, their handshake hashes stay in lock-step,
   and the split transport keys interoperate both directions. *)
let symmetric_two_party () =
  let init () =
    let s = Noise_symmetric_state.initialize ~protocol_name in
    let s = Noise_symmetric_state.mix_hash s "prologue" in
    Noise_symmetric_state.mix_key s (String.make 32 '\007')
  in
  let a = init () and b = init () in
  let a, ct = Noise_symmetric_state.encrypt_and_hash a "secret payload" in
  match Noise_symmetric_state.decrypt_and_hash b ct with
  | Error _ -> Alcotest.fail "handshake payload decrypt failed"
  | Ok (b, pt) ->
    Alcotest.(check string) "payload decrypts" "secret payload" pt;
    Alcotest.(check string) "handshake hashes match"
      (hex (Noise_symmetric_state.handshake_hash a))
      (hex (Noise_symmetric_state.handshake_hash b));
    (* split: (initiator->responder, responder->initiator) *)
    let a_send, a_recv = Noise_symmetric_state.split a in
    let b_recv, b_send = Noise_symmetric_state.split b in
    let _, t1 = Noise_cipher_state.encrypt_with_ad a_send ~ad:"" "ping" in
    (match Noise_cipher_state.decrypt_with_ad b_recv ~ad:"" t1 with
    | Ok (_, m) -> Alcotest.(check string) "transport i->r" "ping" m
    | Error _ -> Alcotest.fail "transport i->r failed");
    let _, t2 = Noise_cipher_state.encrypt_with_ad b_send ~ad:"" "pong" in
    match Noise_cipher_state.decrypt_with_ad a_recv ~ad:"" t2 with
    | Ok (_, m) -> Alcotest.(check string) "transport r->i" "pong" m
    | Error _ -> Alcotest.fail "transport r->i failed"

(* --------------------------------------------------------------------- HKDF *)
let hkdf_props () =
  let ck = String.make 32 '\001' in
  let o1, o2 = Noise_hkdf.hkdf2 ~ck ~ikm:"data" in
  Alcotest.(check int) "out1 is 32 bytes" 32 (String.length o1);
  Alcotest.(check int) "out2 is 32 bytes" 32 (String.length o2);
  Alcotest.(check bool) "out1 <> out2" true (o1 <> o2);
  let o1', o2' = Noise_hkdf.hkdf2 ~ck ~ikm:"data" in
  Alcotest.(check bool) "deterministic" true (o1 = o1' && o2 = o2');
  let h1, h2, _ = Noise_hkdf.hkdf3 ~ck ~ikm:"data" in
  Alcotest.(check bool) "hkdf3 first two outputs equal hkdf2's" true (h1 = o1 && h2 = o2)

let () =
  Alcotest.run "noise"
    [
      ("aead", [ Alcotest.test_case "rfc8439 vector" `Quick rfc8439_aead ]);
      ( "cipher_state",
        [
          Alcotest.test_case "roundtrip + tamper" `Quick cipherstate_roundtrip;
          Alcotest.test_case "passthrough (no key)" `Quick cipherstate_passthrough;
        ] );
      ( "symmetric_state",
        [
          Alcotest.test_case "initialize invariant" `Quick symmetric_initialize;
          Alcotest.test_case "two-party round-trip" `Quick symmetric_two_party;
        ] );
      ("hkdf", [ Alcotest.test_case "properties" `Quick hkdf_props ]);
    ]
