(lang dune 3.0)

(name starling)

(generate_opam_files true)

(source
 (github cargopete/starling))

(authors "Pete <petkopavlovski@gmail.com>")

(maintainers "Pete <petkopavlovski@gmail.com>")

(license MIT)

(package
 (name starling)
 (synopsis "A native libp2p node in OCaml")
 (description
  "starling is a from-scratch libp2p implementation in OCaml: TCP, multistream-select, Noise XX, Yamux, Identify and ping. A murmuration of peers, no leader.")
 (depends
  ocaml
  dune
  eio
  eio_main
  mirage-crypto
  mirage-crypto-ec
  mirage-crypto-rng
  mirage-crypto-rng-eio
  digestif
  ocaml-protoc-plugin
  base58
  hex
  ipaddr
  domain-name
  cstruct
  (alcotest :with-test)
  (qcheck-core :with-test)
  (qcheck-alcotest :with-test)))
