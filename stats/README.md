# Statistical Analysis

This directory contains the tools used to generate benchmark configurations, collect runtime events, aggregate experimental data and reproduce the results reported in the accompanying paper.

## Workflow

The statistical analysis pipeline consists of the following stages:

1. Generate benchmark configurations from the base configuration (`generate_configs.py`).
2. Execute the benchmark campaigns for all runtime implementations.
3. Collect runtime events and compute the benchmark metrics (`main.py`).
4. Aggregate the experimental results (`aggregator.py`).
5. Generate the publication figures (`plotting.py`).

## Directory Contents

* **generate_configs.py** – Generates the benchmark configurations used in the experimental campaign.
* **main.py** – Collects runtime events and computes the benchmark metrics.
* **aggregator.py** – Aggregates the results produced by multiple benchmark executions.
* **plotting.py** – Produces the figures used in the accompanying paper.
* **generated_configs/** – Generated benchmark configurations.
* **results/** – Raw and processed benchmark results.

All statistical processing is performed outside the benchmark implementations to ensure a consistent and language-independent evaluation methodology across all runtime ecosystems.
