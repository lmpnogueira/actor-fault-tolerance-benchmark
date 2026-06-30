package client

import (
	"benchmarking/chatapp/actor/internal/injector"
	"benchmarking/chatapp/actor/internal/protos/messages"
	"benchmarking/chatapp/actor/internal/utils"
	"fmt"
	"log/slog"

	"github.com/asynkron/protoactor-go/actor"
	"github.com/asynkron/protoactor-go/remote"
)

type ClientsOrchestrator struct {
	system *actor.ActorSystem
}

func (c *ClientsOrchestrator) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {
	case *messages.CreateClient:
		strategy := actor.NewOneForOneStrategy(0, 0, func(_ any) actor.Directive {
			return actor.StopDirective
		})
		props := actor.
			PropsFromProducer(func() actor.Actor {
				state := &ClientState{
					TestID:     msg.TestId,
					supervisor: utils.GetProtoActorPid(msg.SupervisorPid),
					TestType:   msg.TestType,
					Username:   msg.Name,
					ChatTopic:  msg.ChatTopic,
				}

				return NewClientActor(
					state,
					msg.DiscoveryPid.Address,
					utils.GetProtoActorPid(msg.MainPid),
					utils.GetProtoActorPid(msg.PublisherPid),
					utils.GetProtoActorPid(msg.DiscoveryPid),
				)
			}).
			Configure(actor.WithSupervisor(strategy))

		c.system.Root.Spawn(props)

	case *messages.CreateInjector:
		strategy := actor.NewOneForOneStrategy(0, 0, func(_ any) actor.Directive {
			return actor.StopDirective
		})
		props := actor.
			PropsFromProducer(func() actor.Actor {
				state := injector.InjectorState{
					MsgType:        msg.MsgType,
					WaitMs:         int(msg.WaitMs),
					ChatTopic:      msg.ChatTopic,
					Name:           msg.Name,
					TestType:       msg.TestType,
					Publisher:      utils.GetProtoActorPid(msg.PublisherPid),
					SupervisorChat: utils.GetProtoActorPid(msg.SupervisorPid),
				}

				return injector.NewInjectorActor(
					state,
					msg.DiscoveryPid.Address,
					utils.GetProtoActorPid(msg.MainPid),
				)
			}).
			Configure(actor.WithSupervisor(strategy))

		c.system.Root.Spawn(props)
	}
}

func spawnClientsOrchestrator(system *actor.ActorSystem) *actor.PID {
	props := actor.PropsFromProducer(func() actor.Actor { return &ClientsOrchestrator{system: system} })
	pid, err := system.Root.SpawnNamed(props, "manager")
	if err != nil {
		panic(fmt.Sprintf("error initiating manager: %v", err))
	}
	return pid
}

func StartChatsOrchestrator() {
	slog.Info("Initiating Client Node Manager ...")
	host := "192.168.1.70"
	port := 9002

	system := actor.NewActorSystem()
	remoteConfig := remote.Configure(host, port)
	r := remote.NewRemote(system, remoteConfig)
	r.Start()

	pid := spawnClientsOrchestrator(system)
	slog.Info("Initiated correctly!",
		slog.String("host", host),
		slog.Int("port", port),
		slog.String("address", pid.Address),
	)

	select {}
}
