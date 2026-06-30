# Reproducibility Guide

This document describes the workflow required to reproduce the benchmark
results reported in the accompanying paper.

## Prerequisites

Install the required software:

- RabbitMQ
- Python 3
- Elixir / Erlang
- Scala, sbt and a compatible JDK
- Go

For the Scala implementation, copy:

```text
scala-akka/.env.example
```

to

```text
scala-akka/.env
```

and configure your own `AKKA_KEY`.

---

## 1. Clone the Repository

```bash
git clone <repository-url>

cd benchmark
```

---

## 2. Create the Python Environment

```bash
cd stats

python3 -m venv venv
source venv/bin/activate

pip install -r requirements.txt
```

---

## 3. Generate Benchmark Configurations

```bash
python3 generate_configs.py
```

The generated benchmark configurations are stored in:

```text
stats/generated_configs/
```

---

## 4. Execute the Benchmark Campaign

```bash
cd ../scripts

./clean.sh
./all_tests.sh
```

The benchmark executes the three runtime implementations sequentially:

- Elixir / BEAM
- Scala / Akka
- Go / Proto.Actor

Each implementation builds itself automatically when required.

During execution, each implementation stores its raw benchmark results in:

```text
<implementation>/scripts/results/
```

---

## 5. Aggregate the Experimental Results

```bash
cd ../stats

python3 aggregator.py
```

This generates the aggregated CSV datasets under:

```text
stats/results/
```

---

## 6. Generate the Publication Figures

```bash
python3 plotting.py
```

Generated figures are written to:

```text
stats/results/figures/
```

---

# Workflow Summary

```text
Clone repository
        │
        ▼
Create Python environment
        │
        ▼
Generate benchmark configurations
        │
        ▼
Execute benchmark campaigns
        │
        ▼
Aggregate experimental results
        │
        ▼
Generate publication figures
```

---

# Notes

- The benchmark assumes a local RabbitMQ instance.
- By default, all implementations communicate using `localhost` / `127.0.0.1`.
- Running `clean.sh` removes all previously generated benchmark results.
- The benchmark configurations included in `stats/generated_configs/` are generated automatically and can be regenerated at any time.

---

# Expected Outputs

After a successful execution, the repository will contain:

```text
stats/results/

    throughput_raw.csv
    throughput_computed.csv

    reconnection_raw.csv
    reconnection_computed.csv

    detection_raw.csv
    detection_computed.csv

    figures/
```

These datasets reproduce the analyses reported in the accompanying paper.