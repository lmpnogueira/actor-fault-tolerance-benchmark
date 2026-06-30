package injector

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"benchmarking/chatapp/actor/internal/utils"
	"log"
	"time"

	"github.com/asynkron/protoactor-go/actor"
	"github.com/asynkron/protoactor-go/scheduler"
)

// Messages
type askChatRef struct{}
type stopTest struct{}
type sendFaultMessage struct{}

type TriggerInjectorTest struct {
	Init time.Time
	End  time.Time
}

// Actor
type InjectorState struct {
	MsgType        messages.MessageType
	WaitMs         int
	ChatTopic      string
	Name           string
	TestType       messages.TestType
	Publisher      *actor.PID
	SupervisorChat *actor.PID
}

type InjectorActor struct {
	state            InjectorState
	remoteAddr       string
	main             *actor.PID
	discovery        *actor.PID
	started          bool
	chat             *actor.PID
	injectionCounter int
}

func NewInjectorActor(state InjectorState, remoteAddr string, main *actor.PID) actor.Actor {
	return &InjectorActor{
		state:            state,
		remoteAddr:       remoteAddr,
		main:             main,
		started:          false,
		discovery:        nil,
		chat:             nil,
		injectionCounter: 0,
	}
}

func (a *InjectorActor) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {

	case *actor.Started:
		log.Printf("[%s] Starting...", a.state.Name)
		discovery := actor.NewPID(a.remoteAddr, "discovery")
		a.discovery = discovery
		ctx.Send(ctx.Self(), &askChatRef{})

	case *askChatRef:
		if a.discovery != nil && a.chat == nil {
			log.Printf("[%s] Asking for chat topic: %s", a.state.Name, a.state.ChatTopic)
			ctx.Send(a.discovery, &messages.GetChatRef{Topic: a.state.ChatTopic, ReplyTo: utils.GetMessagePid(ctx.Self())})
		}

	case *messages.ChatRefResponse:
		a.chat = utils.GetProtoActorPid(msg.Ref)
		ctx.Watch(a.chat)
		if a.chat == nil {
			// Retry (security)
			scheduler := scheduler.NewTimerScheduler(ctx)
			scheduler.SendOnce(200*time.Millisecond, ctx.Self(), &askChatRef{})
		} else {
			if !a.started {
				ctx.Send(
					a.main,
					&messages.InjectorConnectedMain{
						Injector:   utils.GetMessagePid(ctx.Self()),
						Supervisor: utils.GetMessagePid(a.state.SupervisorChat),
						Topic:      a.state.ChatTopic,
					})
			}
		}

	case *messages.ChatNotFound:
		// log.Printf("[%s] Chat not found: %s. Retrying...", a.state.Name, msg.Topic)
		ctx.Send(ctx.Self(), &askChatRef{})

	case *messages.TriggerTest:
		log.Printf("[%s] Time test received: Start Date: %s, End Date: %s", a.state.Name, msg.Init, msg.End)

		if a.state.MsgType == messages.MessageType_NONE {
			ctx.Stop(ctx.Self())
			return
		}

		startDelay := max(time.Until(msg.Init.AsTime().Add(time.Duration(a.state.WaitMs)*time.Millisecond)), 0)
		stopDelay := max(time.Until(msg.End.AsTime()), 0)

		scheduler := scheduler.NewTimerScheduler(ctx)
		scheduler.SendOnce(startDelay, ctx.Self(), &sendFaultMessage{})
		scheduler.SendOnce(stopDelay, ctx.Self(), &stopTest{})
		a.started = true

	case *sendFaultMessage:
		if a.chat != nil {
			// log.Printf("[%s] Sending fault message", a.state.Name)
			ctx.Send(a.chat, &messages.PanicMessage{})

			if a.state.TestType == messages.TestType_DETECTION {
				event := messages.NewEvent(messages.EventType_FAULT_INJECTED, a.state.ChatTopic, int64(a.injectionCounter))
				ctx.Send(a.state.Publisher, &messages.PublishEvent{Event: event})
				a.injectionCounter = a.injectionCounter + 1
			}

		}
		scheduler := scheduler.NewTimerScheduler(ctx)
		scheduler.SendOnce(time.Duration(a.state.WaitMs)*time.Millisecond, ctx.Self(), &sendFaultMessage{})

	case *actor.Terminated:
		if msg.Who.Equal(a.chat) {
			// log.Printf("[%s] Chat terminated. Reconnecting...", a.state.Name)
			a.chat = nil
			ctx.Send(ctx.Self(), &askChatRef{})
		}

	case *stopTest:
		log.Printf("[%s] Stopping test.", a.state.Name)
		ctx.Stop(ctx.Self())
	}
}

// Utility
func max(a, b time.Duration) time.Duration {
	if a > b {
		return a
	}
	return b
}
