(** The library's [Logs] source, ["starling"]. A binary installs a reporter and
    sets the level; with no reporter these calls are no-ops. *)

val src : Logs.src

include Logs.LOG
