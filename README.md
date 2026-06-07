# Actor Fault-Tolerance Benchmark

A language-independent benchmarking framework for evaluating fault-tolerance characteristics of actor-based runtimes.

## Overview

This repository contains the benchmark framework presented in the paper:

> *Benchmarking Fault-Tolerance Characteristics of Actor-Based Runtimes*

The framework was designed to provide a fair and reproducible comparison of fault-tolerance behaviour across different actor-based ecosystems. It evaluates how runtimes react to recurring failures while maintaining equivalent application architectures and fault-injection mechanisms.

The benchmark currently includes implementations for:

* Elixir / BEAM
* Scala / Akka
* Go / Proto.Actor

## Benchmark Architecture

The benchmark is based on a distributed chat application architecture composed of:

* Supervisors
* Chat instances
* Clients
* Service discovery mechanisms
* Fault injection module
* External statistics collector

The architecture allows equivalent experiments to be executed across all runtimes while minimizing implementation-specific bias.

## Evaluated Metrics

The benchmark evaluates three complementary fault-tolerance dimensions:

1. Throughput under recurring transient failures
2. Reconnection latency
3. Failure-detection latency

## Experimental Design

The framework supports configurable workloads through parameters such as:

* Number of supervisors
* Number of chat instances
* Number of connected clients
* Message generation rate
* Fault-injection interval
* Experiment duration

## Repository Structure

```text
elixir/
scala/
go/
common/
results/
docs/
```

## Reproducibility

All benchmark implementations follow the same architectural model and equivalent execution flow to ensure fair comparison between runtimes.

The source code, benchmark configurations, and experimental artefacts are provided to support reproducibility and future comparative studies.

## Citation

If you use this benchmark in your research, please cite:

```bibtex
[paper citation to be added after publication]
```
