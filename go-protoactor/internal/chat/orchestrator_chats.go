package chat

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"benchmarking/chatapp/actor/internal/utils"
	"fmt"
	"log/slog"

	"github.com/asynkron/protoactor-go/actor"
	"github.com/asynkron/protoactor-go/remote"
)

type ChatsOrchestrator struct {
	system *actor.ActorSystem
}

func (c *ChatsOrchestrator) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {
	case *messages.CreateSupChat:
		slog.Info("CreateChatSupervisor message", slog.Any("msg", msg))
		strategy := actor.NewOneForOneStrategy(0, 0, func(_ any) actor.Directive {
			return actor.StopDirective
		})
		props := actor.
			PropsFromProducer(func() actor.Actor {
				return NewSupChat(
					utils.GetProtoActorPid(msg.Sender),
					int(msg.ChatsNumber),
					msg.Name,
					utils.GetProtoActorPid(msg.PublisherPid),
					utils.GetProtoActorPid(msg.DiscoveryPid),
				)
			}).
			Configure(actor.WithSupervisor(strategy))

		c.system.Root.Spawn(props)
	}
}

func spawnChatsOrchestrator(system *actor.ActorSystem) *actor.PID {
	props := actor.PropsFromProducer(func() actor.Actor { return &ChatsOrchestrator{system: system} })
	pid, err := system.Root.SpawnNamed(props, "manager")
	if err != nil {
		panic(fmt.Sprintf("error initiating manager: %v", err))
	}
	return pid
}

func StartChatsOrchestrator() {
	slog.Info("Initiating Chat Node Manager ...")
	host := "192.168.1.70"
	port := 9001

	system := actor.NewActorSystem()
	remoteConfig := remote.Configure(host, port)
	r := remote.NewRemote(system, remoteConfig)
	r.Start()

	pid := spawnChatsOrchestrator(system)
	slog.Info("Initiated correctly!",
		slog.String("host", host),
		slog.Int("port", port),
		slog.String("address", pid.Address),
	)

	select {}
}
