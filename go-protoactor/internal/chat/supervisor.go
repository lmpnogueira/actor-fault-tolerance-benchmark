package chat

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"benchmarking/chatapp/actor/internal/utils"
	"fmt"
	"log"
	"time"

	"github.com/asynkron/protoactor-go/actor"
	"github.com/asynkron/protoactor-go/scheduler"
)

type stop struct{}

type SupChat struct {
	children  map[string]*actor.PID
	chatsNum  int
	main      *actor.PID
	name      string
	Discovery *actor.PID
}

func NewSupChat(main *actor.PID, chatsNum int, name string, publisher, discovery *actor.PID) actor.Actor {
	return &SupChat{
		main:      main,
		chatsNum:  chatsNum,
		children:  make(map[string]*actor.PID),
		name:      name,
		Discovery: discovery,
	}
}

func (s *SupChat) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {

	case *actor.Started:
		log.Printf("[%s] Started", s.name)
		ctx.Send(ctx.Self(), &messages.CreateServers{Count: int32(s.chatsNum)})

	case *messages.CreateServers:
		log.Printf("[%s] Creating %d chats…", s.name, msg.Count)

		chats := make([]*messages.ChatInfo, 0, msg.Count)
		for i := range msg.Count {
			name := fmt.Sprintf("%s_chat_%d", s.name, i)
			childProps := actor.PropsFromProducer(func() actor.Actor {
				return NewChatActor(name, s.Discovery, ctx.Self())
			})
			pid := ctx.Spawn(childProps)
			chats = append(chats, &messages.ChatInfo{Topic: name, Pid: utils.GetMessagePid(pid)})
			ctx.Watch(pid)
			s.children[name] = pid
			log.Printf("[%s] Spawned %s → %v", s.name, name, pid)
		}

		ctx.Send(s.main, &messages.ServerGroup{
			Supervisor: utils.GetMessagePid(ctx.Self()),
			Chats:      chats,
		})

	case *actor.Terminated:
		log.Printf("[%s] someone terminated : %v", s.name, msg)

		crashed := msg.Who
		var crashedName string
		for name, pid := range s.children {
			if pid.Equal(crashed) {
				crashedName = name
				delete(s.children, name)
				break
			}
		}
		if crashedName != "" {
			log.Printf("[%s] %s terminated; respawning…", s.name, crashedName)
			strategy := actor.NewOneForOneStrategy(0, 0, func(_ any) actor.Directive {
				return actor.StopDirective
			})
			props := actor.
				PropsFromProducer(func() actor.Actor { return NewChatActor(crashedName, s.Discovery, ctx.Self()) }).
				Configure(actor.WithSupervisor(strategy))

			newPid := ctx.Spawn(props)
			ctx.Watch(newPid)
			s.children[crashedName] = newPid
			log.Printf("[%s] respawned %s → %v", s.name, crashedName, newPid)
		}

	case *messages.TriggerTest:
		log.Printf("[%s] Time test received: Start Date: %s, End Date: %s", s.name, msg.Init, msg.End)
		stopDelay := max(time.Until(msg.End.AsTime()), 0)

		scheduler := scheduler.NewTimerScheduler(ctx)
		scheduler.SendOnce(stopDelay, ctx.Self(), &stop{})

	case *stop:
		log.Printf("[%s] Stopping all chats", s.name)
		for name, pid := range s.children {
			log.Printf("[%s] Stopping %s", s.name, name)
			ctx.Stop(pid)
		}
		ctx.Stop(ctx.Self())
	}
}
