(* TCP transport over Eio.

   Deliberately no .mli: the connection type is an Eio flow whose row-typed
   capability set ([< `Flow | `R | `W | `Close | ... ]) is unpleasant to spell
   in a signature and adds nothing — dune infers and generalises it across the
   library boundary. The meaningful contract lives in {!Multistream} and the
   upcoming Noise/Yamux layers, which speak in terms of [Eio.Buf_read]/[Buf_write]. *)

let ipaddr_to_eio = function
  | Ipaddr.V4 v4 -> Eio.Net.Ipaddr.of_raw (Ipaddr.V4.to_octets v4)
  | Ipaddr.V6 v6 -> Eio.Net.Ipaddr.of_raw (Ipaddr.V6.to_octets v6)

(* [connect ~sw ~net ma] opens a TCP connection to the /ip + /tcp endpoint of
   [ma], returning the raw duplex flow. Raises [Invalid_argument] if [ma] lacks
   a usable endpoint. *)
let connect ~sw ~net ma =
  match Multiaddr.tcp_endpoint ma with
  | None -> invalid_arg "Transport.connect: multiaddr needs /ip4|/ip6 and /tcp"
  | Some (host, port) ->
    let ip =
      match Ipaddr.of_string host with
      | Ok ip -> ip
      | Error _ -> invalid_arg ("Transport.connect: bad host " ^ host)
    in
    Eio.Net.connect ~sw net (`Tcp (ipaddr_to_eio ip, port))
