package models

import (
	"benchmarking/chatapp/actor/internal/protos/messages"
	"fmt"
	"os"
	"time"

	"gopkg.in/yaml.v3"
)

type TestType string

const (
	Throughput    TestType = "throughput"
	Reconnection  TestType = "reconnection_time"
	DetectionTime TestType = "detection_time"
)

// String returns the string representation of TestType
func (t TestType) String() string {
	return string(t)
}

// UnmarshalYAML ensures only valid enum values are accepted for TestType
func (t *TestType) UnmarshalYAML(value *yaml.Node) error {
	var s string
	if err := value.Decode(&s); err != nil {
		return err
	}

	switch s {
	case string(Throughput), string(Reconnection), string(DetectionTime):
		*t = TestType(s)
		return nil
	default:
		return fmt.Errorf("invalid test_type: %s", s)
	}
}

func (t TestType) ToProto() messages.TestType {
	switch t {
	case Throughput:
		return messages.TestType_THROUGHPUT
	case Reconnection:
		return messages.TestType_RECONNECTION
	case DetectionTime:
		return messages.TestType_DETECTION
	default:
		panic("error on TestType")
	}
}

type Params struct {
	TestType         TestType `yaml:"test_type"`
	TestDurationSecs int      `yaml:"test_duration_seconds"`
	NumSupervisor    int      `yaml:"num_supervisor"`
	ChatsPerSup      int      `yaml:"chats_per_sup"`
	ClientsPerServer int      `yaml:"clients_per_server"`
	MsgType          string   `yaml:"msg_type"`
	FaultPauseMs     int      `yaml:"fault_pause_ms"`
}

type Config struct {
	Params Params `yaml:"params"`
}

func (params *Params) Print(testId string) {
	fmt.Println("################## TEST [Go] ##################")
	fmt.Printf("Test id: %s\n", testId)
	fmt.Printf("Test type: %s\n", params.TestType)
	fmt.Printf("Test duration: %d seconds\n", params.TestDurationSecs)
	fmt.Printf("Number of supervisors: %d\n", params.NumSupervisor)
	fmt.Printf("Chats per supervisor: %d\n", params.ChatsPerSup)
	fmt.Printf("Clients per server: %d\n", params.ClientsPerServer)
	fmt.Printf("Message type: %s\n", params.MsgType)
	fmt.Printf("Fault pause (ms): %d\n", params.FaultPauseMs)
	fmt.Println("###################################################")
}

func LoadParams(filename string) (*Params, error) {
	data, err := os.ReadFile(filename)
	if err != nil {
		return nil, err
	}

	config := &Config{}
	if err := yaml.Unmarshal(data, config); err != nil {
		return nil, err
	}
	return &config.Params, nil
}

type TestInfo struct {
	InitTime time.Time
	EndTime  time.Time
}
