package utils

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"time"

	"github.com/asynkron/protoactor-go/actor"
	"google.golang.org/protobuf/types/known/timestamppb"
)

func GetProtoActorPid(pid *messages.ActorPid) *actor.PID {
	return actor.NewPID(pid.Address, pid.Id)
}

func GetMessagePid(pid *actor.PID) *messages.ActorPid {
	return &messages.ActorPid{Address: pid.Address, Id: pid.Id}
}

func GetMessageType(msgType string) messages.MessageType {
	if msgType == "none" {
		return *messages.MessageType_NONE.Enum()
	} else if msgType == "error" {
		return *messages.MessageType_ERROR.Enum()
	} else {
		panic("invalid msg type")
	}
}

func ToProtoTimestamp(t time.Time) *timestamppb.Timestamp {
	return timestamppb.New(t)
}
