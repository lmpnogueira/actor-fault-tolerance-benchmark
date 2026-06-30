# Go/Proto.Actor Implementation

This directory contains the Go/Proto.Actor implementation of the fault-tolerance benchmarking framework presented in the accompanying paper.

## Requirements

- Go 1.24
- Proto.Actor 0.4.0
- Python 3 (for the external statistics module)

The benchmark expects:

- generated benchmark configurations under `../../stats/generated_configs/`;
- a Python virtual environment available at `../../stats/venv/`.

## Build

```bash
go mod download
go build ./...
```

## Run

To execute a single experiment:

```bash
cd scripts
./run_experiment.sh ../../stats/generated_configs/<config_file>.yml
```

To execute the complete benchmark:

```bash
cd scripts
./run_benchmark.sh
```

## Results

Benchmark events are forwarded to the common statistics module, which computes the evaluation metrics used in the paper. No benchmark results are stored within this implementation.