package discovery

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"benchmarking/chatapp/actor/internal/utils"
	"log"

	"github.com/asynkron/protoactor-go/actor"
)

// Actor

type DiscoveryActor struct {
	chats map[string]*actor.PID
}

func NewDiscoveryActor() actor.Actor {
	return &DiscoveryActor{
		chats: make(map[string]*actor.PID),
	}
}

func (a *DiscoveryActor) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {

	case *actor.Started:
		log.Printf("[Discovery] Starting ...")

	case *messages.RegisterChat:
		// log.Printf("[Discovery] Registering: %v", msg.Topic)
		chatPid := utils.GetProtoActorPid(msg.RefServer)

		if _, exists := a.chats[msg.Topic]; exists {
			ctx.Send(chatPid, &messages.RegistrationFailed{Reason: "Already registered."})
		} else {
			ctx.Send(chatPid, &messages.ChatRegistered{})
			a.chats[msg.Topic] = chatPid
			ctx.Watch(chatPid)
		}

	case *messages.GetChatRef:
		// log.Printf("[Discovery] Being asked about chat: %v", msg.Topic)
		clientPid := utils.GetProtoActorPid(msg.ReplyTo)

		if ref, ok := a.chats[msg.Topic]; ok {
			ctx.Send(clientPid, &messages.ChatRefResponse{Ref: utils.GetMessagePid(ref)})
		} else {
			ctx.Send(clientPid, &messages.ChatNotFound{Topic: msg.Topic})
		}

	case *actor.Terminated:
		// log.Printf("[Discovery] Chat terminated %v", msg)
		for name, pid := range a.chats {
			if pid.Equal(msg.Who) {
				delete(a.chats, name)
				break
			}
		}
	}
}
