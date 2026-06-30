package messages

import (
	"encoding/json"
	"time"
)

func NewEventComplete(timestamp int64, eventType EventType, name string, value int64) *Event {
	return &Event{
		Timestamp: timestamp,
		Event:     eventType,
		Value:     value,
		Name:      name,
	}
}

func NewEvent(eventType EventType, name string, value int64) *Event {
	return NewEventComplete(
		time.Now().UnixMilli(),
		eventType,
		name,
		value,
	)
}

// String maps EventType to the custom lowercase names you want.
func (e EventType) DomainString() string {
	switch e {
	case EventType_MESSAGE_RECEIVED:
		return "message_received"
	case EventType_TEST_STARTED:
		return "test_started"
	case EventType_END_INFO:
		return "end_info"
	case EventType_CLIENT_RECONNECTION_TIME:
		return "client_reconnection_time"
	case EventType_CONNECTED_TIME:
		return "connected_time"
	case EventType_FAULT_INJECTED:
		return "fault_injected"
	case EventType_FAULT_DETECTED:
		return "fault_detected"
	default:
		return "unspecified"
	}
}

// MarshalJSON makes encoding/json use the string instead of the numeric value.
func (e EventType) MarshalJSON() ([]byte, error) {
	return json.Marshal(e.DomainString())
}

// MarshalJSON for Event guarantees that every field is always present in the
// emitted JSON. The protobuf-generated struct tags use `omitempty`, which would
// otherwise drop value==0 (the first fault-injection/detection round, counter 0)
// and break the (name, value) matching performed by the statistics component.
func (e *Event) MarshalJSON() ([]byte, error) {
	return json.Marshal(struct {
		TestID    string `json:"test_id"`
		Timestamp int64  `json:"timestamp"`
		Event     string `json:"event"`
		Value     int64  `json:"value"`
		Name      string `json:"name"`
	}{
		TestID:    e.GetTestId(),
		Timestamp: e.GetTimestamp(),
		Event:     e.GetEvent().DomainString(),
		Value:     e.GetValue(),
		Name:      e.GetName(),
	})
}
