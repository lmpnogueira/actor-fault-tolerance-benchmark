package models

case class Params(test_type: TestType,
                  test_duration_seconds: Int,
                  num_supervisor: Int,
                  chats_per_sup: Int,
                  clients_per_server: Int,
                  msg_type: FaultMessageType,
                  fault_pause_ms: Int)