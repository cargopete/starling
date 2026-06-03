(* The library's logging source. Binaries install a reporter (see the CLI);
   when none is installed these are no-ops, so linking the library never forces
   logging on a consumer. *)

let src = Logs.Src.create "starling" ~doc:"starling libp2p node"

include (val Logs.src_log src : Logs.LOG)
