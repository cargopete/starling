(* starling — command-line entry point.

   Phase 0: derive and print a Peer ID. Grows into dial/listen in later phases. *)

let default_seed =
  (* A fixed development seed (0x01 x 32) — deterministic, NOT for real use. *)
  String.make 32 '\001'

let () =
  let seed =
    match Sys.argv with
    | [| _; "id"; hex |] -> Hex.to_string (`Hex hex)
    | _ -> default_seed
  in
  let k = Starling.Keys.of_seed seed in
  let id = Starling.Keys.peer_id k in
  Printf.printf "%s\n" (Starling.Peer_id.to_string id)
