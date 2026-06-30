package chat

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"benchmarking/chatapp/actor/internal/utils"
	"log"
	"time"

	"github.com/asynkron/protoactor-go/actor"
	"github.com/asynkron/protoactor-go/scheduler"
)

// Self messages

type registrationDiscovery struct{}

type processOrganic struct{}

// Actor

type ChatActor struct {
	name          string
	supervisor    *actor.PID
	clients       map[string]*actor.PID
	injector      *actor.PID
	discovery     *actor.PID
	discoveryAddr string
}

func NewChatActor(name string, discovery, supervisor *actor.PID) actor.Actor {
	return &ChatActor{
		name:          name,
		clients:       make(map[string]*actor.PID),
		injector:      nil,
		discovery:     discovery,
		discoveryAddr: discovery.Address,
		supervisor:    supervisor,
	}
}

func (a *ChatActor) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {

	case *actor.Started:
		log.Printf("[%s] Starting ...", a.name)
		ctx.Send(ctx.Self(), &registrationDiscovery{})

	case *registrationDiscovery:
		a.discovery = actor.NewPID(a.discoveryAddr, "discovery")
		// log.Printf("[%s] Discovery pid: %v", a.name, a.discovery)
		ctx.Send(
			a.discovery,
			&messages.RegisterChat{
				Topic:     a.name,
				RefServer: utils.GetMessagePid(ctx.Self()),
			},
		)

	case *messages.ConnectClient:
		// log.Printf("[%s] Connecting client: %s", a.name, msg.Username)
		pid := utils.GetProtoActorPid(msg.ReplyTo)

		if _, exists := a.clients[msg.Username]; exists {
			ctx.Send(pid, &messages.RegistrationFailed{Reason: "already registered"})
		} else {
			a.clients[msg.Username] = pid
			ctx.Send(pid, &messages.ClientRegistered{
				Server:     utils.GetMessagePid(ctx.Self()),
				Supervisor: utils.GetMessagePid(a.supervisor),
			},
			)
		}

	case *messages.OrganicMessage:
		scheduler := scheduler.NewTimerScheduler(ctx)
		scheduler.SendOnce(200*time.Millisecond, ctx.Self(), &processOrganic{})

	case *processOrganic:
		for _, client := range a.clients {
			ctx.Send(client, &messages.ReceiveMessage{From: utils.GetMessagePid(ctx.Self())})
		}

	case *messages.PanicMessage:
		panic("simulated failure")

	case *messages.ChatRegistered:
		// log.Printf("[%s] Successfully registered", a.name)

	case *messages.RegistrationFailed:
		// log.Printf("[%s] Registration failed. Reason %s. Retrying ...", a.name, msg.Reason)
		scheduler := scheduler.NewTimerScheduler(ctx)
		scheduler.SendOnce(5*time.Millisecond, ctx.Self(), &registrationDiscovery{})

	case *messages.TriggerTest:
		log.Printf("[%s] Time test received: Start Date: %s, End Date: %s", a.name, msg.Init, msg.End)
		stopDelay := max(time.Until(msg.End.AsTime()), 0)

		scheduler := scheduler.NewTimerScheduler(ctx)
		scheduler.SendOnce(stopDelay, ctx.Self(), &stop{})

	case *stop:
		ctx.Stop(ctx.Self())
	}
}
