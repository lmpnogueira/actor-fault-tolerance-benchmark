import os
import csv
import statistics

# Constants
ELIXIR_PATH = "./../elixir/scripts/results"
SCALA_PATH = "./../scala-akka/scripts/results"
GO_PROTOACTOR_PATH = "./../go-protoactor/scripts/results"
OUTPUT_DIR = "./results"

# Headers and Mappings
AGGR_THROUGHPUT_HEADER = ['test_id', 'test_type', 'init_timestamp', 'end_timestamp', 'num_supervisor',
                          'chats_per_sup', 'clients_per_server', 'fault_type', 'fault_pause', 'mean',
                          'min', 'max', 'moda', 'median', 'q1', 'q3', 'total_seconds', 'lang']
AGGR_THROUGHPUT_MAPPING = {name: index for index, name in enumerate(AGGR_THROUGHPUT_HEADER)}

THROUGHPUT_HEADER = ['test_id', 'test_type', 'init_timestamp', 'end_timestamp', 'num_supervisor',
                     'chats_per_sup', 'clients_per_server', 'fault_type', 'fault_pause', 'msg_per_second',
                     'second']
THROUGHPUT_MAPPING = {name: index for index, name in enumerate(THROUGHPUT_HEADER)}

RECONNECTION_HEADER = ['test_id', 'test_type', 'init_timestamp', 'end_timestamp', 'num_supervisor',
                       'chats_per_sup', 'clients_per_server', 'fault_type', 'fault_pause', 'mean',
                       'median', 'min', 'max', 'q1', 'q3', 'perc_full', 'perc_none', 'total_reconnections']
RECONNECTION_MAPPING = {name: index for index, name in enumerate(RECONNECTION_HEADER)}

RECONNECTION_COMPUTED_HEADER = ['test_id', 'test_type', 'init_timestamp', 'end_timestamp', 'num_supervisor',
                                'chats_per_sup', 'clients_per_server', 'fault_type', 'fault_pause',
                                'mean', 'median', 'min', 'max', 'q1', 'q3', 'perc_full', 'perc_none',
                                'total_reconnections', 'lang']
RECONNECTION_COMPUTED_MAPPING = {name: index for index, name in enumerate(RECONNECTION_COMPUTED_HEADER)}

AGGR_DETECTIONS_HEADER = ['test_id', 'test_type', 'init_timestamp', 'end_timestamp', 'num_supervisor',
                          'chats_per_sup', 'clients_per_server', 'fault_type', 'fault_pause', 'mean', 'median', 'min',
                          'max', 'q1', 'q3', 'detections_count', 'lang']

AGGR_DETECTIONS_MAPPING = {
    name: index
    for index, name in enumerate(AGGR_DETECTIONS_HEADER)
}

def main():
    print("Init of aggregator")
    process_throughput()
    process_reconnection()
    process_detection()
    print("Finished aggregation")


def process_throughput():
    print("Processing throughput metrics...")
    throughput_scala = read_throughput_csv("scala", SCALA_PATH)
    throughput_elixir = read_throughput_csv("elixir", ELIXIR_PATH)
    throughput_go_protoactor = read_throughput_csv("go-protoactor", GO_PROTOACTOR_PATH)

    total_raw = throughput_scala[0] + throughput_elixir[0] + throughput_go_protoactor[0]
    total_computed = throughput_scala[1] + throughput_elixir[1] + throughput_go_protoactor[1]

    print(f"Writing {len(total_raw)} raw throughput rows to {OUTPUT_DIR}/throughput_raw.csv")
    write_csv(AGGR_THROUGHPUT_HEADER, total_raw, f"{OUTPUT_DIR}/throughput_raw.csv")

    print(f"Writing {len(total_computed)} computed throughput rows to {OUTPUT_DIR}/throughput_computed.csv")
    write_csv(AGGR_THROUGHPUT_HEADER, total_computed, f"{OUTPUT_DIR}/throughput_computed.csv")


def process_reconnection():
    print("Processing reconnection metrics...")
    reconnection_elixir = read_reconnection_csv("elixir", ELIXIR_PATH)
    reconnection_scala = read_reconnection_csv("scala", SCALA_PATH)

    reconnection_go_protoactor = read_reconnection_csv("go-protoactor", GO_PROTOACTOR_PATH)
    total_raw = reconnection_elixir[0] + reconnection_scala[0] + reconnection_go_protoactor[0]
    total_computed = reconnection_elixir[1] + reconnection_scala[1] + reconnection_go_protoactor[1]

    print(f"Writing {len(total_raw)} raw reconnection rows to {OUTPUT_DIR}/reconnection_raw.csv")
    write_csv(RECONNECTION_COMPUTED_HEADER, total_raw, f"{OUTPUT_DIR}/reconnection_raw.csv")

    print(f"Writing {len(total_computed)} computed reconnection rows to {OUTPUT_DIR}/reconnection_computed.csv")
    write_csv(RECONNECTION_COMPUTED_HEADER, total_computed, f"{OUTPUT_DIR}/reconnection_computed.csv")


def process_detection():
    print("Processing detection metrics...")
    detection_scala = read_detection_csv("scala", SCALA_PATH)
    detection_elixir = read_detection_csv("elixir", ELIXIR_PATH)
    detection_go_protoactor = read_detection_csv("go-protoactor", GO_PROTOACTOR_PATH)

    total_raw = detection_scala[0] + detection_elixir[0] + detection_go_protoactor[0]
    total_computed = detection_scala[1] + detection_elixir[1] + detection_go_protoactor[1]

    print(f"Writing {len(total_raw)} raw detection rows to {OUTPUT_DIR}/detection_raw.csv")
    write_csv(AGGR_DETECTIONS_HEADER, total_raw, f"{OUTPUT_DIR}/detection_raw.csv")

    print(f"Writing {len(total_computed)} computed detection rows to {OUTPUT_DIR}/detection_computed.csv")
    write_csv(AGGR_DETECTIONS_HEADER, total_computed, f"{OUTPUT_DIR}/detection_computed.csv")


def read_throughput_csv(lang, path):
    print(f"Reading {lang} throughput CSV files from {path}")
    return read_metric_csv(
        path=path + "/throughput",
        lang=lang,
        is_valid_file=lambda name: name.endswith(".csv"),
        process_row_fn=process_throughput_row,
        group_key_fn=throughput_group_key,
        aggregate_fn=aggregate_throughput_rows
    )


def read_reconnection_csv(lang, path):
    print(f"Reading {lang} reconnection CSV files from {path}")
    return read_metric_csv(
        path=path + "/reconnection_time",
        lang=lang,
        is_valid_file=lambda name: name.endswith(".csv") and not name.startswith(
            "reconnection_milli") and not name.startswith(
            "reconnection_raw") and name.startswith("reconnection"),
        process_row_fn=process_reconnection_row,
        group_key_fn=reconnection_group_key,
        aggregate_fn=aggregate_reconnection_rows
    )


def read_detection_csv(lang, path):
    print(f"Reading {lang} detection CSV files from {path}")
    return read_metric_csv(
        path=path + "/detection_time",
        lang=lang,
        is_valid_file=lambda name: name.endswith(".csv"),
        process_row_fn=process_reconnection_row,
        group_key_fn=throughput_group_key,
        aggregate_fn=aggregate_throughput_rows
    )


def read_metric_csv(path, lang, is_valid_file, process_row_fn, group_key_fn, aggregate_fn):
    aggregated_rows = []
    if os.path.exists(path):
        for folder in os.listdir(path):
            folder_path = os.path.join(path, folder)
            if os.path.isdir(folder_path):
                print(f"Checking folder: {folder_path}")
                for filename in os.listdir(folder_path):
                    if is_valid_file(filename):
                        full_path = os.path.join(folder_path, filename)
                        try:
                            print(f"Processing file: {full_path}")
                            rows = process_row_fn(full_path, lang)
                            print(f" --> Processed {len(rows)} rows")
                            aggregated_rows += rows
                        except Exception as e:
                            print(f" !!! Error processing {full_path}: {e}")
    else:
        print(f"Path does not exist: {path}")

    grouped = group_by_key(aggregated_rows, group_key_fn)
    print(f"Grouped into {len(grouped)} keys for computation")
    computed_rows = [aggregate_fn(rows) for rows in grouped.values()]
    return aggregated_rows, computed_rows


def process_throughput_row(file_path, lang):
    rows = []
    with open(file_path, newline='') as csvfile:
        reader = csv.reader(csvfile, delimiter='\t')
        next(reader, None)
        msg_list = []
        info_row = []

        for str_row in reader:
            row = str_row[0].split(",")
            msgs_sec = int(row[THROUGHPUT_MAPPING['msg_per_second']])
            msg_list.append(msgs_sec)

            if not info_row:
                info_row = row[:9]

        if msg_list:
            mean = int(sum(msg_list) / len(msg_list))
            min_val = min(msg_list)
            max_val = max(msg_list)
            try:
                mode_val = statistics.mode(msg_list)
            except statistics.StatisticsError:
                mode_val = 0
            median_val = int(statistics.median(msg_list))

            try:
                q1, q3 = statistics.quantiles(msg_list, n=4)[0], statistics.quantiles(msg_list, n=4)[2]
            except Exception:
                q1, q3 = 0, 0

            # Append stats and metadata
            info_row += [mean, min_val, max_val, mode_val, median_val, q1, q3, len(msg_list), lang]
            rows.append(info_row)

    return rows


def process_reconnection_row(file_path, lang):
    rows = []
    with open(file_path, newline='') as csvfile:
        reader = csv.reader(csvfile, delimiter='\t')
        next(reader, None)
        for str_row in reader:
            row = str_row[0].split(",")
            row.append(lang)
            rows.append(row)
    return rows


def group_by_key(rows, key_fn):
    grouped = {}
    for row in rows:
        key = key_fn(row)
        grouped.setdefault(key, []).append(row)
    return grouped


def throughput_group_key(row):
    return tuple(row[THROUGHPUT_MAPPING[key]] for key in
                 ['num_supervisor', 'chats_per_sup', 'clients_per_server', 'fault_type', 'fault_pause'])


def reconnection_group_key(row):
    return tuple(row[RECONNECTION_COMPUTED_MAPPING[key]] for key in
                 ['num_supervisor', 'chats_per_sup', 'clients_per_server', 'fault_type', 'fault_pause'])


def aggregate_throughput_rows(rows):
    total_mean_msg = sum(int(row[9]) for row in rows)
    total_min_msg = sum(int(row[10]) for row in rows)
    total_max_msg = sum(int(row[11]) for row in rows)
    total_mode_msg = sum(int(row[12]) for row in rows)
    total_median_msg = sum(int(row[13]) for row in rows)
    total_q1 = sum(int(row[14]) for row in rows)
    total_q2 = sum(int(row[15]) for row in rows)
    base_row = rows[0][:]
    base_row[9] = int(total_mean_msg / len(rows))
    base_row[10] = int(total_min_msg / len(rows))
    base_row[11] = int(total_max_msg / len(rows))
    base_row[12] = int(total_mode_msg / len(rows))
    base_row[13] = int(total_median_msg / len(rows))
    base_row[14] = int(total_q1 / len(rows))
    base_row[15] = int(total_q2 / len(rows))
    return base_row


def aggregate_reconnection_rows(rows):
    sums = [0] * 8
    base_row = rows[0][:]
    for row in rows:
        sums[0] += int(row[9])
        sums[1] += int(row[10])
        sums[2] += int(row[11])
        sums[3] += int(row[12])
        sums[4] += float(row[13])
        sums[5] += float(row[14])
        sums[6] += float(row[15])
        sums[7] += float(row[16])

    count = len(rows)
    base_row[9:17] = [
        int(sums[0] / count),
        int(sums[1] / count),
        int(sums[2] / count),
        int(sums[3] / count),
        float(sums[4] / count),
        float(sums[5] / count),
        float(sums[6] / count),
        float(sums[7] / count)
    ]
    return base_row


def write_csv(header, content, output_path):
    os.makedirs(os.path.dirname(output_path), exist_ok=True)
    print(f"Writing to file: {output_path}")
    with open(output_path, mode='w', newline='') as file:
        writer = csv.writer(file)
        writer.writerow(header)
        writer.writerows(content)
    print(f" --> Done writing {len(content)} rows")


if __name__ == '__main__':
    try:
        main()
    except KeyboardInterrupt:
        print('Interrupted')
        os._exit(0)
