module Ed = Mirage_crypto_ec.Ed25519

type t = { priv : Ed.priv; pub : Ed.pub }

let of_seed seed =
  if String.length seed <> 32 then invalid_arg "Keys.of_seed: need 32 bytes";
  match Ed.priv_of_octets seed with
  | Ok priv -> { priv; pub = Ed.pub_of_priv priv }
  | Error _ -> invalid_arg "Keys.of_seed: invalid scalar"

let generate ?g () =
  let priv, pub = Ed.generate ?g () in
  { priv; pub }

let public_key_raw t = Ed.pub_to_octets t.pub
let private_key_raw t = Ed.priv_to_octets t.priv
let public_key_proto t = Peer_id.marshal_ed25519_pubkey (public_key_raw t)
let peer_id t = Peer_id.of_ed25519_pubkey (public_key_raw t)
let sign t msg = Ed.sign ~key:t.priv msg

let verify ~raw_pub ~signature msg =
  match Ed.pub_of_octets raw_pub with
  | Ok pub -> Ed.verify ~key:pub signature ~msg
  | Error _ -> false
