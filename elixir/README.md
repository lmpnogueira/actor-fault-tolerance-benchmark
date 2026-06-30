# Elixir/BEAM Implementation

This directory contains the Elixir/BEAM implementation of the fault-tolerance benchmarking framework presented in the accompanying paper.

## Requirements

- Elixir 1.19.5
- Erlang/OTP 28
- Python 3 (for the external statistics module)

The benchmark expects:

- generated benchmark configurations under `../../stats/generated_configs/`;
- a Python virtual environment available at `../../stats/venv/`.

## Build

```bash
mix deps.get
mix compile
mix release
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