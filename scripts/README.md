# Automation Scripts

This directory contains helper scripts used to prepare, execute and clean benchmark campaigns across the supported runtime implementations.

## Scripts

- **all_tests.sh** – Executes the complete benchmark campaign by running all supported runtime implementations (Elixir/BEAM, Scala/Akka and Go/Proto.Actor) sequentially.

- **clean.sh** – Removes benchmark results, logs and build artefacts while preserving the generated benchmark configurations.

- **distclean.sh** – Performs a complete cleanup, including generated benchmark configurations, leaving the repository in a clean state.