package main

// Emit a cross-implementation known-answer vector for the libp2p Noise pattern
// Noise_XX_25519_ChaChaPoly_SHA256, using flynn/noise — the very library
// go-libp2p drives. Fixed static + ephemeral keys (32 bytes of 0x01..0x04) and
// an empty prologue, exactly matching starling's handshake. The OCaml test pins
// this output and asserts starling reproduces every message byte-for-byte.

import (
	"bytes"
	"encoding/hex"
	"fmt"

	"github.com/flynn/noise"
)

func fixedKey(cs noise.CipherSuite, b byte) noise.DHKey {
	secret := bytes.Repeat([]byte{b}, 32)
	k, err := cs.GenerateKeypair(bytes.NewReader(secret))
	if err != nil {
		panic(err)
	}
	return k
}

func runNoiseKAT() {
	cs := noise.NewCipherSuite(noise.DH25519, noise.CipherChaChaPoly, noise.HashSHA256)
	iStatic := fixedKey(cs, 0x01)
	rStatic := fixedKey(cs, 0x03)

	// flynn ignores Config.EphemeralKeypair and derives the ephemeral from
	// Config.Random, so we feed the ephemeral secret (0x02 / 0x04) there to keep
	// the handshake deterministic.
	hsI, err := noise.NewHandshakeState(noise.Config{
		CipherSuite: cs, Pattern: noise.HandshakeXX, Initiator: true,
		StaticKeypair: iStatic, Random: bytes.NewReader(bytes.Repeat([]byte{0x02}, 32)),
	})
	if err != nil {
		panic(err)
	}
	hsR, err := noise.NewHandshakeState(noise.Config{
		CipherSuite: cs, Pattern: noise.HandshakeXX, Initiator: false,
		StaticKeypair: rStatic, Random: bytes.NewReader(bytes.Repeat([]byte{0x04}, 32)),
	})
	if err != nil {
		panic(err)
	}

	emit := func(name string, b []byte) { fmt.Printf("%s %s\n", name, hex.EncodeToString(b)) }

	// -> e
	msg1, _, _, err := hsI.WriteMessage(nil, nil)
	if err != nil {
		panic(err)
	}
	if _, _, _, err = hsR.ReadMessage(nil, msg1); err != nil {
		panic(err)
	}
	// <- e, ee, s, es
	msg2, _, _, err := hsR.WriteMessage(nil, []byte("noise-xx-msg2"))
	if err != nil {
		panic(err)
	}
	if _, _, _, err = hsI.ReadMessage(nil, msg2); err != nil {
		panic(err)
	}
	// -> s, se   (final message: transport cipher states returned)
	msg3, csI2R, _, err := hsI.WriteMessage(nil, []byte("noise-xx-msg3"))
	if err != nil {
		panic(err)
	}
	if _, _, _, err = hsR.ReadMessage(nil, msg3); err != nil {
		panic(err)
	}

	emit("i_static_pub", iStatic.Public)
	emit("r_static_pub", rStatic.Public)
	emit("msg1", msg1)
	emit("msg2", msg2)
	emit("msg3", msg3)
	emit("handshake_hash", hsI.ChannelBinding())
	// csI2R is the initiator->responder transport cipher; first Encrypt uses nonce 0.
	ct, err := csI2R.Encrypt(nil, nil, []byte("transport-test"))
	if err != nil {
		panic(err)
	}
	emit("transport_i2r", ct)
}
