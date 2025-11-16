# System Monitoring Utilities

C utilities for system resource monitoring and information retrieval.

## Utilities

### `memquery.c`

Queries and reports system memory information.

**Compilation:**

```bash
gcc -o memquery memquery.c
```

**Usage:**

```bash
./memquery
```

**Output:** Reports available memory, free swap space, and huge pages configuration from `/proc/meminfo`.

**Purpose:** Lightweight memory monitoring tool for scripting and system diagnostics.
