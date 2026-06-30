package client

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"benchmarking/chatapp/actor/internal/utils"
	"time"

	"log"

	"github.com/asynkron/protoactor-go/actor"
	"github.com/asynkron/protoactor-go/scheduler"
)

//  Messages

type askChatRef struct{}
type processSend struct{}
type stopTest struct{}

// Actor

type ClientState struct {
	TestID         string
	TestType       messages.TestType
	supervisor     *actor.PID
	Username       string
	ChatTopic      string
	Started        bool
	DisconnectedAt time.Time
	ConnectedAt    time.Time
}

type ClientActor struct {
	state          *ClientState
	remoteAddr     string
	main           *actor.PID
	publisher      *actor.PID
	discovery      *actor.PID
	chat           *actor.PID
	detectionCount int
}

func NewClientActor(state *ClientState, remoteAddr string, main, publisher, discovery *actor.PID) actor.Actor {
	return &ClientActor{
		state:          state,
		remoteAddr:     remoteAddr,
		main:           main,
		publisher:      publisher,
		discovery:      discovery,
		chat:           nil,
		detectionCount: 0,
	}
}

func (a *ClientActor) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {

	case *actor.Started:
		log.Printf("[%s] Starting ...", a.state.Username)
		discovery := actor.NewPID(a.remoteAddr, "discovery")
		log.Printf("[%s] Discovery pid: %v", a.state.Username, discovery)
		a.discovery = discovery
		ctx.Send(ctx.Self(), &askChatRef{})

	case *askChatRef:
		if a.discovery != nil && a.chat == nil {
			log.Printf("[%s] Asking chat topic %s ...", a.state.Username, a.state.ChatTopic)
			ctx.Send(
				a.discovery,
				&messages.GetChatRef{
					Topic:   a.state.ChatTopic,
					ReplyTo: utils.GetMessagePid(ctx.Self()),
				},
			)
		}

	case *messages.ChatNotFound:
		// log.Printf("[%s] Chat not found. Retrying ...", a.state.Username)
		ctx.Send(ctx.Self(), &askChatRef{})

	case *messages.ChatRefResponse:
		// log.Printf("[%s] Chat found: %s", a.state.Username, a.state.ChatTopic)

		if a.chat == nil { // Not connected yet
			ctx.Send(
				utils.GetProtoActorPid(msg.Ref),
				&messages.ConnectClient{
					Username: a.state.Username,
					ReplyTo:  utils.GetMessagePid(ctx.Self()),
				},
			)
			// Retry (security)
			scheduler := scheduler.NewTimerScheduler(ctx)
			scheduler.SendOnce(200*time.Millisecond, ctx.Self(), &askChatRef{})
		}

	case *messages.ClientRegistered:
		// log.Printf("[%s] Registered", a.state.Username)
		a.chat = utils.GetProtoActorPid(msg.Server)
		ctx.Watch(a.chat)

		if !a.state.Started {
			ctx.Send(
				a.main,
				&messages.ClientConnected{
					Client: utils.GetMessagePid(ctx.Self()),
					Chat: &messages.ChatInfo{
						Topic: a.state.ChatTopic,
						Pid:   utils.GetMessagePid(a.chat),
					},
					Supervisor: utils.GetMessagePid(a.state.supervisor),
				},
			)
		}

		if !a.state.DisconnectedAt.IsZero() && a.state.TestType == messages.TestType_RECONNECTION {
			diff := time.Since(a.state.DisconnectedAt).Milliseconds()
			ctx.Send(a.publisher, &messages.PublishEvent{
				Event: messages.NewEventComplete(
					time.Now().UnixMilli(),
					messages.EventType_CLIENT_RECONNECTION_TIME,
					a.state.Username,
					int64(diff),
				)})
		}

		a.state.ConnectedAt = time.Now()
		a.state.DisconnectedAt = time.Time{}

	case *messages.RegistrationFailed:
		ctx.Send(ctx.Self(), &askChatRef{})

	case *messages.TriggerTest:
		log.Printf("[%s] Time test received: Start Date: %s, End Date: %s", a.state.Username, msg.Init, msg.End)

		if a.state.TestType == messages.TestType_THROUGHPUT {
			startDelay := max(time.Until(msg.Init.AsTime()), 0)
			scheduler := scheduler.NewTimerScheduler(ctx)
			scheduler.SendOnce(startDelay, ctx.Self(), &processSend{})
		}
		stopDelay := max(time.Until(msg.End.AsTime()), 0)
		scheduler := scheduler.NewTimerScheduler(ctx)
		scheduler.SendOnce(stopDelay, ctx.Self(), &stopTest{})

		a.state.Started = true

	case *processSend:
		if a.state.TestType == messages.TestType_THROUGHPUT && a.chat != nil {
			ctx.Send(a.chat, &messages.OrganicMessage{Content: "ping"})
		}
		scheduler := scheduler.NewTimerScheduler(ctx)
		scheduler.SendOnce(200*time.Millisecond, ctx.Self(), &processSend{})

	case *messages.ReceiveMessage:
		if a.state.TestType == messages.TestType_THROUGHPUT {
			ctx.Send(a.publisher, &messages.PublishEvent{
				Event: messages.NewEvent(messages.EventType_MESSAGE_RECEIVED, a.state.Username, -1),
			})
		}

	case *actor.Terminated:
		// log.Printf("[%s] Chat terminated ...", a.state.Username)
		if !a.state.ConnectedAt.IsZero() && a.state.TestType == messages.TestType_RECONNECTION {
			diff := time.Since(a.state.ConnectedAt).Milliseconds()
			event := messages.NewEventComplete(
				time.Now().UnixMilli(),
				messages.EventType_CONNECTED_TIME,
				a.state.Username,
				int64(diff),
			)
			ctx.Send(a.publisher, &messages.PublishEvent{Event: event})
		}

		if a.state.TestType == messages.TestType_DETECTION {
			event := messages.NewEvent(
				messages.EventType_FAULT_DETECTED,
				a.state.ChatTopic,
				int64(a.detectionCount),
			)
			ctx.Send(a.publisher, &messages.PublishEvent{Event: event})
			a.detectionCount = a.detectionCount + 1
		}

		a.state.DisconnectedAt = time.Now()
		a.state.ConnectedAt = time.Time{}
		a.chat = nil

		ctx.Send(ctx.Self(), &askChatRef{})

	case *stopTest:
		log.Printf("[%s] Client stopping ...", a.state.Username)
		ts := time.Now().Add(1 * time.Second).UnixMilli()
		if !a.state.ConnectedAt.IsZero() && a.state.TestType == messages.TestType_RECONNECTION {
			diff := time.Since(a.state.ConnectedAt).Milliseconds()
			event := messages.NewEventComplete(
				time.Now().UnixMilli(),
				messages.EventType_CONNECTED_TIME,
				a.state.Username,
				int64(diff),
			)
			ctx.Send(a.publisher, &messages.PublishEvent{Event: event})
		} else {
			event := messages.NewEventComplete(
				ts,
				messages.EventType_MESSAGE_RECEIVED,
				a.state.Username,
				-1,
			)
			ctx.Send(a.publisher, &messages.PublishEvent{Event: event})
		}
		ctx.Stop(ctx.Self())
	}
}
