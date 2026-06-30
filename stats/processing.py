import csv
import os
import statistics
import threading
from collections import defaultdict
from datetime import datetime, timedelta

import matplotlib

matplotlib.use('Agg')
import matplotlib.pyplot as plt

import config
from config import ServerType, TestType

# Globals
counts = defaultdict(int)
connection_intervals = []
client_reconnection_times = []
lock = threading.Lock()

fault_injections = defaultdict(int)  # {(server_name, injection_count): timestamp}
detection_deltas = []  # All detection times in milliseconds
unmatched_detections = defaultdict(list)  # { (name, value): [timestamps] }


# Timeout Setup
def setup_timeout(timeout):
    def timeout_handler():
        print("Timeout reached!")
        finish()

    print(f"Set timeout to {timeout} seconds (safety)")
    timeout_timer = threading.Timer(timeout, timeout_handler)
    timeout_timer.daemon = True
    timeout_timer.start()
    return timeout_timer


# Message Handler
def handle_message(message):
    msg_datetime = datetime.fromtimestamp(int(message['timestamp']) / 1000)
    event_type = message['event']

    if event_type == ServerType.TEST_STARTED.value:
        handle_test_started(msg_datetime, message)
    elif event_type == ServerType.END_TEST.value:
        handle_test_ended(msg_datetime, message)

    if config.test_param['init_timestamp'] and config.test_param['end_timestamp']:
        if not config.test_param['test_initiated']:
            config.test_param['test_initiated'] = True
            config.test_param['timeout_initiated'] = True

        if config.test_param['init_timestamp'] <= msg_datetime <= config.test_param['end_timestamp']:
            process_event(message, msg_datetime)
        elif event_type != ServerType.END_TEST.value and msg_datetime > config.test_param['end_timestamp']:
            print("Received message outside valid time range. Finishing test...")
            finish()


def handle_test_started(msg_datetime, message):
    print(f"Received the TEST_STARTED event at {msg_datetime}")
    config.test_param['init_timestamp'] = msg_datetime
    config.test_param['init_timestamp_raw'] = message['timestamp']


def handle_test_ended(msg_datetime, message):
    print(f"Received the END_TEST event at {msg_datetime}")
    config.test_param['end_timestamp'] = msg_datetime - timedelta(milliseconds=1)
    config.test_param['end_timestamp_raw'] = message['timestamp'] + 1000


def process_event(message, msg_datetime):
    event = message['event']
    name = message['name']
    timestamp = int(message['timestamp'])
    value = int(message['value'])

    if event == ServerType.CLIENT_RECONNECTION_TIME.value:
        with lock:
            client_reconnection_times.append(message['value'])

    elif event == ServerType.CONNECTED_TIME.value:
        connected_duration = message['value']
        end_time = message['timestamp']
        start_time = end_time - connected_duration
        with lock:
            connection_intervals.append((start_time, end_time))

    elif event == ServerType.MESSAGE_RECEIVED.value:
        bucket = int((msg_datetime - config.test_param['init_timestamp']).total_seconds()) + 1
        with lock:
            counts[bucket] += 1

    elif event == ServerType.FAULT_INJECTED.value:
        with lock:
            key = (name, value)
            fault_injections[key] = timestamp

            # Check for any previously unmatched detections
            if key in unmatched_detections:
                for detection_time in unmatched_detections[key]:
                    detection_deltas.append(detection_time - timestamp)
                del unmatched_detections[key]  # Clear once matched


    elif event == ServerType.FAULT_DETECTED.value:
        with lock:
            key = (name, value)
            if key in fault_injections:
                detection_deltas.append(timestamp - fault_injections[key])
            else:
                unmatched_detections[key].append(timestamp)


def finish():
    print("\n== TEST COMPLETED ==")
    test_id = config.test_param['test_id']
    test_type = config.test_param['test_type']
    print(f"Test ID: {test_id}")
    print(f"Test Type: {test_type}")
    print("==\n")

    results_dir = os.path.join("results", test_type, test_id)
    os.makedirs(results_dir, exist_ok=True)

    if test_type == TestType.RECONNECTION_TIME.value:
        handle_reconnection_results(results_dir)
    elif test_type == TestType.THROUGHPUT.value:
        handle_throughput_results(results_dir)

    if detection_deltas:
        save_detection_stats(results_dir)
        plot_detection_chart(results_dir)

    print(f"\nResults saved in folder: {results_dir}")
    print("==\n")
    os._exit(0)


# Reconnection Logic
def handle_reconnection_results(results_dir):
    data = calculate_connected_percentage()
    write_reconnection_computed_csv(os.path.join(results_dir, f"reconnection_{config.test_param['test_id']}.csv"),
                                    data['perc_all_connected'], data['perc_not_all_connected'])
    write_reconnection_raw_csv(os.path.join(results_dir, f"reconnection_raw_{config.test_param['test_id']}.csv"))
    generate_connected_chart(os.path.join(results_dir, f"reconnection_{config.test_param['test_id']}.png"),
                             data['connected_per_millisecond'])
    write_graph_reconnection_csv(
        os.path.join(results_dir, f"reconnection_milli_graph_{config.test_param['test_id']}.csv"),
        data['connected_per_millisecond'])


def calculate_connected_percentage():
    if not connection_intervals:
        return {
            'connected_per_millisecond': {},
            'perc_all_connected': "0.00",
            'perc_not_all_connected': "100.00"
        }

    test_start = config.test_param['init_timestamp_raw']
    test_end = config.test_param['end_timestamp_raw']
    total_clients = int(config.test_param['chats_per_sup']) * int(config.test_param['num_supervisor']) * int(
        config.test_param['clients_per_server'])
    connected_deltas = defaultdict(int)

    for start, end in connection_intervals:
        start = max(start, test_start)
        end = min(end, test_end)
        if start >= end:
            continue
        connected_deltas[int(start - test_start)] += 1
        connected_deltas[int(end - test_start)] -= 1

    connected_per_millisecond = {}
    current_connected = 0
    for key in sorted(connected_deltas):
        current_connected += connected_deltas[key]
        connected_per_millisecond[key] = (current_connected / total_clients) * 100

    total_duration, full_connected_duration = 0, 0
    keys = sorted(connected_per_millisecond)
    for i in range(1, len(keys)):
        duration = keys[i] - keys[i - 1]
        percentage = connected_per_millisecond[keys[i - 1]]
        total_duration += duration
        if percentage >= 100.0:
            full_connected_duration += duration

    full_perc = (full_connected_duration / total_duration) * 100 if total_duration else 0
    return {
        'connected_per_millisecond': connected_per_millisecond,
        'perc_all_connected': f"{full_perc:.2f}",
        'perc_not_all_connected': f"{100 - full_perc:.2f}",
    }


# Throughput Logic
def handle_throughput_results(results_dir):
    write_throughput_csv(os.path.join(results_dir, f"throughput_{config.test_param['test_id']}.csv"))
    if counts:
        generate_throughput_chart(os.path.join(results_dir, f"throughput_{config.test_param['test_id']}.png"))


# File Writing Utilities
def write_throughput_csv(path):
    with lock, open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['test_id', 'test_type', 'init_timestamp', 'end_timestamp',
                         'num_supervisor', 'chats_per_sup', 'clients_per_server',
                         'fault_type', 'fault_pause', 'msg_per_second', 'second'])

        for sec in sorted(counts):
            writer.writerow([
                config.test_param['test_id'],
                config.test_param['test_type'],
                config.test_param['init_timestamp'].timestamp(),
                config.test_param['end_timestamp'].timestamp(),
                config.test_param['num_supervisor'],
                config.test_param['chats_per_sup'],
                config.test_param['clients_per_server'],
                config.test_param['fault_type'],
                config.test_param['fault_pause'],
                counts[sec],
                sec
            ])
            print(f"Second {sec:3d}: {counts[sec]} message(s)")


def write_graph_reconnection_csv(path, connected_time):
    with lock, open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['test_id', 'test_type', 'init_timestamp', 'end_timestamp',
                         'num_supervisor', 'chats_per_sup', 'clients_per_server',
                         'fault_type', 'fault_pause', 'clients_connected', 'milisecond'])
        for ms in sorted(connected_time):
            writer.writerow([
                config.test_param['test_id'],
                config.test_param['test_type'],
                config.test_param['init_timestamp'].timestamp(),
                config.test_param['end_timestamp'].timestamp(),
                config.test_param['num_supervisor'],
                config.test_param['chats_per_sup'],
                config.test_param['clients_per_server'],
                config.test_param['fault_type'],
                config.test_param['fault_pause'],
                connected_time[ms],
                ms
            ])


def write_reconnection_computed_csv(path, all_perc, left_perc):
    with lock, open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        header = ['test_id', 'test_type', 'init_timestamp', 'end_timestamp',
                  'num_supervisor', 'chats_per_sup', 'clients_per_server',
                  'fault_type', 'fault_pause', 'mean',
                  'median', 'min', 'max', 'q1', 'q3', 'perc_full', 'perc_none', 'total_reconnections']
        writer.writerow(header)

        if client_reconnection_times:
            mean_time = int(sum(client_reconnection_times) / len(client_reconnection_times))
            median_time = int(statistics.median(client_reconnection_times))
            min_time = min(client_reconnection_times)
            max_time = max(client_reconnection_times)

            # Calculate Q1 and Q3 using statistics.quantiles
            try:
                q1_time = int(statistics.quantiles(client_reconnection_times, n=4)[0])
                q3_time = int(statistics.quantiles(client_reconnection_times, n=4)[2])
            except Exception:
                q1_time, q3_time = 0, 0
        else:
            mean_time = median_time = q1_time = q3_time = min_time = max_time = 0

        writer.writerow([
            config.test_param['test_id'],
            config.test_param['test_type'],
            config.test_param['init_timestamp'].timestamp(),
            config.test_param['end_timestamp'].timestamp(),
            config.test_param['num_supervisor'],
            config.test_param['chats_per_sup'],
            config.test_param['clients_per_server'],
            config.test_param['fault_type'],
            config.test_param['fault_pause'],
            mean_time,
            median_time,
            min_time,
            max_time,
            q1_time,
            q3_time,
            all_perc,
            left_perc,
            len(client_reconnection_times)
        ])
        print(f"Total reconnection messages: {len(client_reconnection_times)}")


def write_reconnection_raw_csv(path):
    with lock, open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['test_id', 'test_type', 'init_timestamp', 'end_timestamp',
                         'num_supervisor', 'chats_per_sup', 'clients_per_server',
                         'fault_type', 'fault_pause', 'reconnection_time'])
        for time in client_reconnection_times:
            writer.writerow([
                config.test_param['test_id'],
                config.test_param['test_type'],
                config.test_param['init_timestamp'].timestamp(),
                config.test_param['end_timestamp'].timestamp(),
                config.test_param['num_supervisor'],
                config.test_param['chats_per_sup'],
                config.test_param['clients_per_server'],
                config.test_param['fault_type'],
                config.test_param['fault_pause'],
                time
            ])


# Charts
def generate_throughput_chart(path):
    with lock:
        seconds = sorted(counts)
        values = [counts[sec] for sec in seconds]

    plt.figure(figsize=(12, 6))
    plt.plot(seconds, values, marker='o')
    plt.title(f"Throughput Over Time (Test ID: {config.test_param['test_id']})")
    plt.xlabel("Second")
    plt.ylabel("Messages per Second")
    plt.grid(True)
    plt.tight_layout()
    plt.savefig(path)
    plt.close()


def generate_connected_chart(path, percentage_data, stats=None):
    with lock:
        if isinstance(percentage_data, dict):
            ms = sorted(percentage_data)
            perc = [percentage_data[k] for k in ms]
        elif isinstance(percentage_data, float):
            ms = [0]
            perc = [percentage_data]
        else:
            raise TypeError("percentage_data must be a dict or a float")

    if not ms:
        plt.figure(figsize=(12, 6))
        plt.text(0.5, 0.5, 'No connection data available',
                 horizontalalignment='center',
                 verticalalignment='center',
                 fontsize=14, alpha=0.6)
        plt.axis('off')
        plt.savefig(path)
        plt.close()
        return

    sec = [k / 1000 for k in ms]

    plt.figure(figsize=(12, 6))
    plt.plot(sec, perc, linestyle='-', color='b', linewidth=2, alpha=0.8, label='Connected Clients (%)')

    # Detect local minima
    local_mins = [i for i in range(1, len(perc) - 1) if perc[i] < perc[i - 1] and perc[i] < perc[i + 1]]
    if perc and len(perc) > 1 and perc[0] < perc[1]: local_mins.insert(0, 0)
    if perc and len(perc) > 1 and perc[-1] < perc[-2]: local_mins.append(len(perc) - 1)

    for i in local_mins:
        plt.plot(sec[i], perc[i], 'o', color='darkred', markersize=6)
        plt.text(sec[i], perc[i], f'{perc[i]:.1f}%', fontsize=9, ha='right', va='bottom', color='darkred')

    plt.title(f"Connected Clients Over Time (Test ID: {config.test_param['test_id']})")
    plt.xlabel("Time Since Start (s)")
    plt.ylabel("Connected Clients (%)")
    plt.ylim(0, 110)
    plt.axhline(y=100, color='r', linestyle='--', alpha=0.7)

    if max(sec) > 60:
        plt.gca().xaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f"{int(x // 60)}:{int(x % 60):02d}"))
    else:
        plt.gca().xaxis.set_major_formatter(plt.FuncFormatter(lambda x, _: f"{x:.1f}s"))

    if stats and 'mean_time' in stats:
        plt.text(0.97, 0.97, (
            f"Statistics (ms):\nMean: {stats['mean_time']}\nMedian: {stats['median_time']}\n"
            f"Min: {stats['min_time']}\nMax: {stats['max_time']}"),
                 transform=plt.gca().transAxes, fontsize=9, verticalalignment='top',
                 horizontalalignment='right', bbox=dict(boxstyle='round,pad=0.5', facecolor='white', alpha=0.8))

    plt.grid(True, alpha=0.3)
    plt.legend()
    plt.tight_layout()
    plt.savefig(path)
    plt.close()


def save_detection_stats(results_dir):
    mean_time = int(statistics.mean(detection_deltas)) if detection_deltas else 0
    median_time = int(statistics.median(detection_deltas)) if detection_deltas else 0
    min_time = min(detection_deltas) if detection_deltas else 0
    max_time = max(detection_deltas) if detection_deltas else 0

    try:
        q1_time = int(statistics.quantiles(detection_deltas, n=4)[0])
        q3_time = int(statistics.quantiles(detection_deltas, n=4)[2])
    except Exception:
        q1_time = q3_time = 0

    path = os.path.join(results_dir, f"detection_stats_{config.test_param['test_id']}.csv")
    with open(path, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow([
            "test_id", "test_type", "init_ts", "end_ts",
            "num_supervisor", "chats_per_sup", "clients_per_server", "fault_type", "fault_pause",
            "mean", "median", "min", "max", "q1", "q3", "detections_count"
        ])
        writer.writerow([
            config.test_param['test_id'],
            config.test_param['test_type'],
            config.test_param['init_timestamp'].timestamp(),
            config.test_param['end_timestamp'].timestamp(),
            config.test_param['num_supervisor'],
            config.test_param['chats_per_sup'],
            config.test_param['clients_per_server'],
            config.test_param['fault_type'],
            config.test_param['fault_pause'],
            mean_time,
            median_time,
            min_time,
            max_time,
            q1_time,
            q3_time,
            len(detection_deltas),
        ])


def plot_detection_chart(results_dir):
    path = os.path.join(results_dir, f"detection_plot_{config.test_param['test_id']}.png")
    if not detection_deltas:
        return

    mean_time = statistics.mean(detection_deltas)

    plt.figure(figsize=(10, 5))
    plt.hist(detection_deltas, bins=20, color='steelblue', edgecolor='black')

    # Plot vertical line at mean
    plt.axvline(mean_time, color='red', linestyle='dashed', linewidth=2, label=f'Mean = {mean_time:.2f} ms')

    plt.title("Detection Time Distribution")
    plt.xlabel("Detection Time (ms)")
    plt.ylabel("Frequency")
    plt.grid(True)
    plt.legend()
    plt.tight_layout()
    plt.savefig(path)
    plt.close()
