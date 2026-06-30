package models

import upickle.default.*

enum EventType(val value: String)derives ReadWriter:

  case ReceivedMessage extends EventType("message_received")
  case TestStarted extends EventType("test_started")
  case EndInfo extends EventType("end_info")
  case ClientReconnectionTime extends EventType("client_reconnection_time")
  case ConnectedTime extends EventType("connected_time")
  case FaultInjected extends EventType("fault_injected")
  case FaultDetected extends EventType("fault_detected")
