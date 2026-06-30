"""Statistics collector for benchmark experiments."""

from __future__ import annotations

import argparse
import json
from pathlib import Path
import traceback

import pika
import yaml

import config
from processing import handle_message, setup_timeout


def load_config(config_file: Path) -> dict:
    """Load a benchmark configuration from a YAML file."""
    with config_file.open("r", encoding="utf-8") as stream:
        return yaml.safe_load(stream)


def consumer() -> None:
    """Consume benchmark events from RabbitMQ."""

    connection = pika.BlockingConnection(
        pika.ConnectionParameters(host="localhost")
    )

    channel = connection.channel()

    channel.queue_declare(
        queue="events_queue",
        durable=True,
    )

    def callback(ch, method, properties, body):
        try:
            message = json.loads(body)

            if message.get("test_id") == config.test_param["test_id"]:
                handle_message(message)
            else:
                print(
                    f"Ignored message with test_id "
                    f"{message.get('test_id')} "
                    f"(expecting {config.test_param['test_id']})"
                )

        except json.JSONDecodeError:
            print("Invalid JSON message received.")

        except Exception:
            print(traceback.format_exc())

    print("Waiting for benchmark events...")

    channel.basic_consume(
        queue="events_queue",
        on_message_callback=callback,
        auto_ack=True,
    )

    channel.start_consuming()


def parse_arguments():
    """Parse command-line arguments."""

    parser = argparse.ArgumentParser(
        description="Benchmark statistics collector."
    )

    parser.add_argument(
        "test_id",
        help="Benchmark execution identifier.",
    )

    parser.add_argument(
        "config_file",
        type=Path,
        help="Benchmark configuration file.",
    )

    return parser.parse_args()


def main() -> None:

    args = parse_arguments()

    benchmark = load_config(args.config_file)
    params = benchmark["params"]

    config.test_param = {
        "test_id": args.test_id,
        "test_type": params["test_type"],
        "num_supervisor": params["num_supervisor"],
        "chats_per_sup": params["chats_per_sup"],
        "clients_per_server": params["clients_per_server"],
        "fault_type": params["msg_type"],
        "fault_pause": params["fault_pause_ms"],
        "test_initiated": False,
        "timeout_initiated": False,
        "init_timestamp": None,
        "end_timestamp": None,
    }

    print("Starting benchmark with parameters")
    print("==================================")

    for key, value in config.test_param.items():
        print(f"{key}: {value}")

    print("==================================")

    # Safety net: guarantee the collector terminates even if no event ever
    # arrives after the test window (otherwise start_consuming() would block
    # forever and the experiment script would hang on `wait`).
    safety_timeout = int(params["test_duration_seconds"]) + 120
    setup_timeout(safety_timeout)

    consumer()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        print("Interrupted")