import enum


class ServerType(enum.Enum):
    MESSAGE_RECEIVED = 'message_received'
    TEST_STARTED = 'test_started'
    END_TEST = 'end_info'
    CLIENT_RECONNECTION_TIME = 'client_reconnection_time'
    CONNECTED_TIME = 'connected_time'
    FAULT_INJECTED = 'fault_injected'
    FAULT_DETECTED = 'fault_detected'


class TestType(enum.Enum):
    RECONNECTION_TIME = 'reconnection_time'
    THROUGHPUT = 'throughput'
    DETECTION_TIME = 'detection_time'


test_param = {
}
