import os
import copy
import yaml


def _generate_config_files(values, base_config, param_name, filename_pattern, output_dir="generated_configs"):
    """
    Generic helper to create a series of YAML config files.

    :param values: list of parameter values to vary.
    :param base_config: dict, base configuration.
    :param param_name: key inside base_config["params"] to set.
    :param filename_pattern: string pattern for filenames, e.g. "reconnection_time_config_chats_{}"
    :param output_dir: directory to place generated files.
    """
    os.makedirs(output_dir, exist_ok=True)
    for v in values:
        config = copy.deepcopy(base_config)
        config["params"][param_name] = v
        filename = os.path.join(output_dir, f"{filename_pattern.format(v)}.yml")
        with open(filename, "w") as file:
            yaml.dump(config, file, default_flow_style=False)
        print(f"Generated {filename}")


# ---------------------------------------------------------------------------
# Reconnection time
# ---------------------------------------------------------------------------

def reconnection_time_chats():
    base_config = {
        "params": {
            "test_type": "reconnection_time",
            "test_duration_seconds": 60,
            "num_supervisor": 1,
            "chats_per_sup": 1,
            "clients_per_server": 5,
            "msg_type": "error",
            "fault_pause_ms": 5000,
            "client_base_rate": 100,
            "client_ceil_rate": 400,
        }
    }
    chats_values = [5, 100, 200, 300, 400, 500, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000]
    _generate_config_files(chats_values, base_config, "chats_per_sup",
                           "reconnection_time_config_chats_{}")


def reconnection_time_clients():
    base_config = {
        "params": {
            "test_type": "reconnection_time",
            "test_duration_seconds": 60,
            "num_supervisor": 1,
            "chats_per_sup": 1,
            "clients_per_server": 60000,
            "msg_type": "error",
            "fault_pause_ms": 5000,
            "client_base_rate": 100,
            "client_ceil_rate": 400,
        }
    }
    clients_values = [5, 100, 500, 1000, 2000, 3000, 4000, 5000, 10000, 20000, 30000, 40000, 50000]
    _generate_config_files(clients_values, base_config, "clients_per_server",
                           "reconnection_time_clients_{}")


def reconnection_time_fault_pause():
    base_config = {
        "params": {
            "test_type": "reconnection_time",
            "test_duration_seconds": 60,
            "num_supervisor": 1,
            "chats_per_sup": 5000,
            "clients_per_server": 5,
            "msg_type": "error",
            "fault_pause_ms": 5000,
            "client_base_rate": 100,
            "client_ceil_rate": 400,
        }
    }
    fault_pause_ms_values = [
        300, 500, 1000, 3000, 5000, 8000, 10000,
        20000, 30000, 40000, 50000, 60000, 61000,
    ]
    _generate_config_files(fault_pause_ms_values, base_config, "fault_pause_ms",
                           "reconnection_time_{}")


# ---------------------------------------------------------------------------
# Throughput
# ---------------------------------------------------------------------------

def throughput_fault_pause():
    base_config = {
        "params": {
            "test_type": "throughput",
            "test_duration_seconds": 60,
            "num_supervisor": 1,
            "chats_per_sup": 256,
            "clients_per_server": 5,
            "msg_type": "error",
            "fault_pause_ms": 5000,
            "client_base_rate": 100,
            "client_ceil_rate": 400,
        }
    }
    fault_pause_ms_values = [
        300, 500, 1000, 3000, 5000, 8000, 10000,
        20000, 30000, 40000, 50000, 60000,
    ]
    _generate_config_files(fault_pause_ms_values, base_config, "fault_pause_ms",
                           "throughput_fault_pause_ms_{}")


# ---------------------------------------------------------------------------
# Detection time
# ---------------------------------------------------------------------------

def detection_time_chats():
    base_config = {
        "params": {
            "test_type": "detection_time",
            "test_duration_seconds": 60,
            "num_supervisor": 1,
            "chats_per_sup": 1,
            "clients_per_server": 5,
            "msg_type": "error",
            "fault_pause_ms": 5000,
            "client_base_rate": 100,
            "client_ceil_rate": 400,
        }
    }
    chats_values = [5, 100, 200, 300, 400, 500, 1000, 2000, 3000, 4000, 5000, 6000, 7000, 8000, 9000]
    _generate_config_files(chats_values, base_config, "chats_per_sup",
                           "detection_time_config_chats_{}")


def detection_time_clients():
    base_config = {
        "params": {
            "test_type": "detection_time",
            "test_duration_seconds": 60,
            "num_supervisor": 1,
            "chats_per_sup": 1,
            "clients_per_server": 60000,
            "msg_type": "error",
            "fault_pause_ms": 5000,
            "client_base_rate": 100,
            "client_ceil_rate": 400,
        }
    }
    clients_values = [5, 100, 500, 1000, 2000, 3000, 4000, 5000, 10000, 20000, 30000, 40000, 50000]
    _generate_config_files(clients_values, base_config, "clients_per_server",
                           "detection_time_clients_{}")


def detection_time_fault_pause():
    base_config = {
        "params": {
            "test_type": "detection_time",
            "test_duration_seconds": 60,
            "num_supervisor": 1,
            "chats_per_sup": 5000,
            "clients_per_server": 5,
            "msg_type": "error",
            "fault_pause_ms": 5000,
            "client_base_rate": 100,
            "client_ceil_rate": 400,
        }
    }
    fault_pause_ms_values = [
        300, 500, 1000, 3000, 5000, 8000, 10000,
        20000, 30000, 40000, 50000, 60000, 61000,
    ]
    _generate_config_files(fault_pause_ms_values, base_config, "fault_pause_ms",
                           "detection_time_fault_pause_{}")


if __name__ == "__main__":
    reconnection_time_chats()
    reconnection_time_clients()
    # reconnection_time_fault_pause()
    throughput_fault_pause()
    detection_time_chats()
    detection_time_clients()
    # detection_time_fault_pause()
