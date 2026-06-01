module X = Mirage_crypto_ec.X25519

type keypair = { secret : X.secret; public : string }

let generate () =
  let secret, public = X.gen_key () in
  { secret; public }

let of_secret_bytes b =
  if String.length b <> 32 then invalid_arg "Noise_dh.of_secret_bytes: need 32 bytes";
  match X.secret_of_octets b with
  | Ok (secret, public) -> { secret; public }
  | Error _ -> invalid_arg "Noise_dh.of_secret_bytes: invalid scalar"

let public kp = kp.public

let dh kp ~remote_public =
  match X.key_exchange kp.secret remote_public with
  | Ok shared -> shared
  | Error _ -> failwith "Noise_dh.dh: X25519 key exchange failed"
