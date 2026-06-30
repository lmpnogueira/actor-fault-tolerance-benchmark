package orchestrator

import (
	"benchmarking/chatapp/actor/internal/discovery"
	"benchmarking/chatapp/actor/internal/models"
	"benchmarking/chatapp/actor/internal/protos/messages"
	"benchmarking/chatapp/actor/internal/publisher"
	"benchmarking/chatapp/actor/internal/utils"
	"fmt"
	"log"
	"log/slog"
	"strconv"
	"time"

	"github.com/asynkron/protoactor-go/actor"
	"github.com/asynkron/protoactor-go/remote"
)

const SetupCoolDownSeconds = 20

// Self Messages
type MainGuardianCommand interface{}

type createChats struct{}

type createClients struct{}

type createFaultInjectors struct{}

type initTest struct{}

// Internal Types

type PIDKey struct {
	Address string
	Id      string
}

func toPIDKey(pid *actor.PID) PIDKey {
	return PIDKey{Address: pid.Address, Id: pid.Id}
}

func (k PIDKey) toActorPID() *actor.PID {
	return actor.NewPID(k.Address, k.Id)
}

type InitGuardianParams struct {
	TestID           string
	TestType         messages.TestType
	TestDuration     int
	MsgType          string
	FaultPauseMs     int
	NumSup           int
	NumChatsPerSup   int
	ClientsPerServer int
	Discovery        *actor.PID
}

type mainGuardianParams struct {
	remoteAddr         string
	TestID             string
	TestType           messages.TestType
	TestDuration       int
	MsgType            string
	FaultPauseMs       int
	NumSup             int
	NumChatsPerSup     int
	TotalChats         int
	ClientsPerServer   int
	TotalClients       int
	ClientBaseRate     int
	ClientCeilRate     int
	CreatedChats       int
	ConnectedClients   int
	ConnectedInjectors int
	Discovery          *actor.PID
	Publisher          *actor.PID
	ClientsNodePid     *actor.PID
	ChatsNodePid       *actor.PID
	ClientsNodeAddress string
	ChatsNodeAddress   string
}

type GroupState struct {
	Chat     *messages.ChatInfo
	Topic    string
	Clients  []*actor.PID
	Injector *actor.PID
}

// Actor
type MainGuardianActor struct {
	params mainGuardianParams
	groups map[PIDKey][]*GroupState // sup -> group
	system *actor.ActorSystem
}

func NewMainGuardianActor(params InitGuardianParams, remoteAddr string, system *actor.ActorSystem) actor.Actor {
	totalChats := params.NumChatsPerSup * params.NumSup
	totalClients := totalChats * params.ClientsPerServer

	internalParams := &mainGuardianParams{
		remoteAddr:         remoteAddr,
		TestID:             params.TestID,
		TestType:           params.TestType,
		TestDuration:       params.TestDuration,
		MsgType:            params.MsgType,
		FaultPauseMs:       params.FaultPauseMs,
		NumSup:             params.NumSup,
		NumChatsPerSup:     params.NumChatsPerSup,
		ClientsPerServer:   params.ClientsPerServer,
		TotalChats:         totalChats,
		TotalClients:       totalClients,
		Discovery:          params.Discovery,
		ChatsNodeAddress:   "192.168.1.70:9001",
		ClientsNodeAddress: "192.168.1.70:9002",
	}

	return &MainGuardianActor{
		params: *internalParams,
		groups: make(map[PIDKey][]*GroupState),
		system: system,
	}
}

func (a *MainGuardianActor) Receive(ctx actor.Context) {
	switch msg := ctx.Message().(type) {

	case *actor.Started:
		slog.Info("[MainGuardian] Starting...")

		// creating discovery
		props := actor.PropsFromProducer(func() actor.Actor {
			return discovery.NewDiscoveryActor()
		})
		discoveryPid, err := a.system.Root.SpawnNamed(props, "discovery")
		if err != nil {
			panic(fmt.Sprintf("discovery not correctly initiated: %v", err))
		}
		a.params.Discovery = discoveryPid
		slog.Info("[MainGuardian] Discovery created!", slog.String("pid", discoveryPid.Address))

		// creating publisher
		props = actor.PropsFromProducer(func() actor.Actor {
			return publisher.NewPublisherActor(a.params.TestID)
		})
		publisherPid, err := a.system.Root.SpawnNamed(props, "publisher")
		if err != nil {
			panic(fmt.Sprintf("publisher not correctly initiated: %v", err))
		}
		slog.Info("[MainGuardian] Publisher created!", slog.String("pid", publisherPid.Address))
		a.params.Publisher = publisherPid

		// obtain pids of chats and clients' nodes managers
		clientsManagerPid := actor.NewPID(a.params.ClientsNodeAddress, "manager")
		chatManagerPid := actor.NewPID(a.params.ChatsNodeAddress, "manager")

		// todo:  check communication

		slog.Info("[MainGuardian] Client's node manager connected!", slog.String("pid", clientsManagerPid.Address))
		slog.Info("[MainGuardian] Chat's node manager connected!", slog.String("pid", chatManagerPid.Address))
		a.params.ChatsNodePid = chatManagerPid
		a.params.ClientsNodePid = clientsManagerPid

		ctx.Send(ctx.Self(), &createChats{})

	case *createChats:
		log.Println("[MainGuardian] Creating supervisors and chats...")
		for i := 1; i <= a.params.NumSup; i++ {
			name := "sup_" + strconv.Itoa(i)

			createChatMsg := &messages.CreateSupChat{
				Name:         name,
				ChatsNumber:  int32(a.params.NumChatsPerSup),
				PublisherPid: utils.GetMessagePid(a.params.Publisher),
				DiscoveryPid: utils.GetMessagePid(a.params.Discovery),
				Sender:       utils.GetMessagePid(ctx.Self()),
			}

			ctx.Send(a.params.ChatsNodePid, createChatMsg)
		}

	case *messages.ServerGroup:
		groupStates := []*GroupState{}
		for _, chat := range msg.Chats {
			groupStates = append(
				groupStates,
				&GroupState{Chat: chat, Topic: chat.Topic, Clients: []*actor.PID{}},
			)
		}
		supPID := utils.GetProtoActorPid(msg.Supervisor)
		a.groups[toPIDKey(supPID)] = groupStates

		a.params.CreatedChats += len(msg.Chats)
		if a.params.CreatedChats == a.params.TotalChats {
			log.Printf("[MainGuardian] All %d chats created", a.params.TotalChats)
			ctx.Send(ctx.Self(), &createClients{})
		}

	case *createClients:
		log.Println("[MainGuardian] Creating clients...")
		for supervisor, groupStates := range a.groups {
			for _, group := range groupStates {
				for i := 1; i <= a.params.ClientsPerServer; i++ {
					name := fmt.Sprintf("client_%d_%s", i, group.Chat.Topic)

					createClientMsg := &messages.CreateClient{
						Name:          name,
						TestId:        a.params.TestID,
						TestType:      a.params.TestType,
						ChatTopic:     group.Chat.Topic,
						SupervisorPid: utils.GetMessagePid(supervisor.toActorPID()),
						MainPid:       utils.GetMessagePid(ctx.Self()),
						PublisherPid:  utils.GetMessagePid(a.params.Publisher),
						DiscoveryPid:  utils.GetMessagePid(a.params.Discovery),
					}

					ctx.Send(a.params.ClientsNodePid, createClientMsg)
				}
			}
		}

	case *messages.ClientConnected:
		supPID := utils.GetProtoActorPid(msg.Supervisor)
		groupStates, ok := a.groups[toPIDKey(supPID)]

		if !ok {
			slog.Error("[MainGuardian] Client connected but supervisor not previously registered")
			return
		}

		for _, group := range groupStates {
			if group.Chat.Topic == msg.Chat.Topic {
				pid := utils.GetProtoActorPid(msg.Client)
				group.Clients = append(group.Clients, pid)
				break
			}
		}
		a.params.ConnectedClients++
		if a.params.ConnectedClients == a.params.TotalClients {
			log.Println("[MainGuardian] All clients connected.")
			ctx.Send(ctx.Self(), &createFaultInjectors{})
		}

	case *createFaultInjectors:
		log.Println("[MainGuardian] Creating fault injectors...")
		for supervisor, groupStates := range a.groups {
			for _, group := range groupStates {
				name := "injector_" + group.Chat.Topic

				createInjectorMsg := &messages.CreateInjector{
					Name:          name,
					TestId:        a.params.TestID,
					TestType:      a.params.TestType,
					ChatTopic:     group.Chat.Topic,
					MsgType:       utils.GetMessageType(a.params.MsgType),
					WaitMs:        int32(a.params.FaultPauseMs),
					MainPid:       utils.GetMessagePid(ctx.Self()),
					PublisherPid:  utils.GetMessagePid(a.params.Publisher),
					DiscoveryPid:  utils.GetMessagePid(a.params.Discovery),
					ChatPid:       group.Chat.Pid,
					SupervisorPid: utils.GetMessagePid(supervisor.toActorPID()),
				}

				ctx.Send(a.params.ClientsNodePid, createInjectorMsg)
			}
		}

	case *messages.InjectorConnectedMain:
		a.params.ConnectedInjectors++
		supervisor := utils.GetProtoActorPid(msg.Supervisor)
		injector := utils.GetProtoActorPid(msg.Injector)

		if groupState, ok := a.groups[toPIDKey(supervisor)]; ok {
			log.Printf("[MainGuardian] Injected created. %v", msg)
			for _, group := range groupState {
				if group.Topic == msg.Topic {
					group.Injector = injector
				}
			}
		}

		if a.params.ConnectedInjectors == a.params.TotalChats {
			log.Println("[MainGuardian] All injectors connected.")
			ctx.Send(ctx.Self(), &initTest{})
		}

	case *initTest:
		initTime := time.Now().Add(SetupCoolDownSeconds * time.Second)
		endTime := initTime.Add(time.Duration(a.params.TestDuration+1) * time.Second)
		log.Printf("[MainGuardian] Test running from %s to %s", initTime, endTime)
		a.system.Root.ActorSystem().Shutdown()

		ctx.Send(a.params.Publisher, &messages.PublishEvent{
			Event: messages.NewEventComplete(initTime.UnixMilli(), messages.EventType_TEST_STARTED, "main_guardian", -1),
		})
		ctx.Send(a.params.Publisher, &messages.PublishEvent{
			Event: messages.NewEventComplete(endTime.UnixMilli(), messages.EventType_END_INFO, "main_guardian", -1),
		})

		initTimeProto := utils.ToProtoTimestamp(initTime)
		endTimeProto := utils.ToProtoTimestamp(endTime)

		for supervisor, groupStates := range a.groups {
			a.system.Root.Send(supervisor.toActorPID(), &messages.TriggerTest{Init: initTimeProto, End: endTimeProto})
			for _, group := range groupStates {
				ctx.Send(utils.GetProtoActorPid(group.Chat.Pid), &messages.TriggerTest{Init: initTimeProto, End: endTimeProto})
				ctx.Send(group.Injector, &messages.TriggerTest{Init: initTimeProto, End: endTimeProto})

				for _, client := range group.Clients {
					ctx.Send(client, &messages.TriggerTest{Init: initTimeProto, End: endTimeProto})
				}
			}
		}
	}

}

func spawnClientsOrchestrator(system *actor.ActorSystem, params *models.Params, testId string) *actor.PID {
	props := actor.PropsFromProducer(func() actor.Actor {
		params := &InitGuardianParams{
			TestID:           testId,
			TestType:         params.TestType.ToProto(),
			TestDuration:     params.TestDurationSecs,
			MsgType:          params.MsgType,
			FaultPauseMs:     params.FaultPauseMs,
			NumSup:           params.NumSupervisor,
			NumChatsPerSup:   params.ChatsPerSup,
			ClientsPerServer: params.ClientsPerServer,
		}
		return NewMainGuardianActor(*params, system.Address(), system)
	})

	pid, err := system.Root.SpawnNamed(props, "orchestrator")
	if err != nil {
		panic(fmt.Sprintf("error initiating main orchestrator: %v", err))
	}
	return pid
}

func StartMainOrchestrator(params *models.Params, testId string) {
	slog.Info("Initiating Main Node Manager ...")
	host := "192.168.1.70"
	port := 9000

	system := actor.NewActorSystem()
	remoteConfig := remote.Configure(host, port)
	r := remote.NewRemote(system, remoteConfig)
	r.Start()

	pid := spawnClientsOrchestrator(system, params, testId)
	slog.Info("Initiated correctly!",
		slog.String("host", host),
		slog.Int("port", port),
		slog.String("address", pid.Address),
	)

	select {}
}
