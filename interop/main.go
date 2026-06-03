// A minimal go-libp2p node for interop-testing starling.
//
//	go run . listen [port]  -> serve ping + identify, print full multiaddr
//	go run . dial <ma>      -> dial a starling node, ping it
//
// Security: Noise. Muxer: Yamux. Exactly starling's MVP stack.
package main

import (
	"context"
	"fmt"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/libp2p/go-libp2p"
	"github.com/libp2p/go-libp2p/core/host"
	"github.com/libp2p/go-libp2p/core/peer"
	"github.com/libp2p/go-libp2p/p2p/protocol/ping"
	"github.com/libp2p/go-libp2p/p2p/security/noise"
	yamux "github.com/libp2p/go-libp2p/p2p/muxer/yamux"
	"github.com/multiformats/go-multiaddr"
)

func mkHost(port string) host.Host {
	h, err := libp2p.New(
		libp2p.ListenAddrStrings("/ip4/127.0.0.1/tcp/"+port),
		libp2p.Security(noise.ID, noise.New),
		libp2p.Muxer(yamux.ID, yamux.DefaultTransport),
		libp2p.Ping(true),
	)
	if err != nil {
		panic(err)
	}
	return h
}

func runListen(port string) {
	h := mkHost(port)
	defer h.Close()
	for _, a := range h.Addrs() {
		fmt.Printf("go-libp2p listening on %s/p2p/%s\n", a, h.ID())
	}
	fmt.Println("waiting for connections (ctrl-c to stop)...")
	c := make(chan os.Signal, 1)
	signal.Notify(c, syscall.SIGINT, syscall.SIGTERM)
	<-c
}

func runDial(ma string) {
	h := mkHost("0")
	defer h.Close()
	addr, err := multiaddr.NewMultiaddr(ma)
	if err != nil {
		panic(err)
	}
	info, err := peer.AddrInfoFromP2pAddr(addr)
	if err != nil {
		panic(err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
	defer cancel()
	if err := h.Connect(ctx, *info); err != nil {
		fmt.Println("connect failed:", err)
		os.Exit(1)
	}
	fmt.Println("connected to", info.ID)
	res := <-ping.Ping(ctx, h, info.ID)
	if res.Error != nil {
		fmt.Println("ping failed:", res.Error)
		os.Exit(1)
	}
	fmt.Printf("ping: %v\n", res.RTT)
}

func main() {
	if len(os.Args) < 2 {
		fmt.Println("usage: go run . [listen [port] | dial <multiaddr>]")
		os.Exit(2)
	}
	switch os.Args[1] {
	case "listen":
		port := "4101"
		if len(os.Args) > 2 {
			port = os.Args[2]
		}
		runListen(port)
	case "dial":
		if len(os.Args) < 3 {
			fmt.Println("dial needs a multiaddr")
			os.Exit(2)
		}
		runDial(os.Args[2])
	default:
		fmt.Println("unknown subcommand")
		os.Exit(2)
	}
}
