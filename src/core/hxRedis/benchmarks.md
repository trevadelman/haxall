# HxRedis Benchmark Analysis

This document provides a comprehensive analysis of HxRedis performance across different runtimes and compares it against alternative database access patterns.

## Benchmark Overview

We ran three categories of benchmarks to understand performance characteristics:

1. **Raw Redis Client Operations** - Direct Redis commands to isolate network/protocol overhead
2. **HxRedis Folio Queries** - Full Folio API queries to measure runtime overhead
3. **Python Redis vs SkySpark HTTP** - Practical comparison of data access patterns

## Test Environment

- **Hardware:** Apple Silicon Mac (local development machine)
- **Redis:** Local Redis server on default port 6379
- **SkySpark:** Local instance on port 8081 with demo project
- **Dataset:** ~340 records (4 sites, 40 equips, ~280 points)
- **Iterations:** 10 iterations per benchmark, with 3 warmup runs

## Methodology

### Raw Redis Client Benchmarks

We tested fundamental Redis operations to establish a baseline:

```
# Test data setup
100 string keys (key:0 through key:99)
100 hash fields in hash:test
100 set members in set:test
```

Operations tested:
- **GET** - Single string lookup
- **SET** - Single string write
- **HGET** - Single hash field lookup
- **HGETALL** - Retrieve all 100 hash fields
- **SMEMBERS** - Retrieve all 100 set members
- **PING** - Simple round-trip latency

### HxRedis Folio Benchmarks

We populated HxRedis with a realistic building data model:
- 4 Sites
- 40 Equips (10 per site)
- ~280 Points (7 per equip)

Queries tested:
- **Read All Records** - `readAll(Filter.has("id"))`
- **Filter: site** - `readAll(Filter.has("site"))`
- **Filter: equip** - `readAll(Filter.has("equip"))`
- **Filter: point** - `readAll(Filter.has("point"))`
- **Count All Records** - `readCount(Filter.has("id"))`

### Timing Methodology

Both Fantom and Python benchmarks use high-resolution timers:

**Fantom/JVM:**
```fantom
start := Duration.now
operation()
elapsed := Duration.now - start
// Convert to microseconds for precision
microseconds := elapsed.ticks / 1000
```

**Python:**
```python
start = time.time()
operation()
elapsed = time.time() - start
milliseconds = elapsed * 1000
```

---

## Results

### Raw Redis Client Operations

| Operation | Fantom/JVM | Python | Python Overhead |
|-----------|------------|--------|-----------------|
| GET | 0.095ms | 0.108ms | 1.1x |
| SET | 0.120ms | 0.137ms | 1.1x |
| HGET | 0.102ms | 0.119ms | 1.2x |
| HGETALL (100 fields) | 0.279ms | 4.936ms | **17.7x** |
| SMEMBERS (100 members) | 0.178ms | 3.105ms | **17.4x** |
| PING | 0.073ms | 0.154ms | 2.1x |

### HxRedis Folio Queries (~340 records)

| Benchmark | Fantom/JVM | Python | Python Overhead |
|-----------|------------|--------|-----------------|
| Read All Records | 0.526ms | 56.59ms | **108x** |
| Filter: site | 0.084ms | 4.89ms | **58x** |
| Filter: equip | 0.100ms | 9.53ms | **95x** |
| Filter: point | 0.352ms | 33.56ms | **95x** |
| Count All Records | 0.078ms | 5.23ms | **67x** |
| **AVERAGE** | **0.228ms** | **21.96ms** | **~96x** |

### Python: Redis vs SkySpark HTTP

| Benchmark | SkySpark (HTTP) | Python Redis | Speedup |
|-----------|-----------------|--------------|---------|
| Read All Records | 1085.31ms | 56.59ms | 19.2x |
| Filter: site | 14.91ms | 4.89ms | 3.0x |
| Filter: equip | 66.05ms | 9.53ms | 6.9x |
| Filter: point | 416.49ms | 33.56ms | 12.4x |
| Count All Records | 8.95ms | 5.23ms | 1.7x |
| **AVERAGE** | 318.34ms | 21.96ms | **14.5x** |

---

## Analysis

### Raw Redis: Nearly Identical Performance

The most revealing finding is that **simple Redis operations perform nearly identically** between Fantom/JVM and Python:

- GET: 0.095ms vs 0.108ms (1.1x)
- SET: 0.120ms vs 0.137ms (1.1x)
- HGET: 0.102ms vs 0.119ms (1.2x)
- PING: 0.073ms vs 0.154ms (2.1x)

This makes sense because:
1. The actual work is done by the Redis server, not the client runtime
2. Network latency dominates the operation time
3. Both runtimes are making the same socket calls

### Bulk Operations: Python Object Construction Overhead

For operations returning many items (HGETALL, SMEMBERS), we see **~17x overhead**:

- HGETALL: 0.279ms vs 4.936ms (17.7x)
- SMEMBERS: 0.178ms vs 3.105ms (17.4x)

This overhead comes from:
1. **Python list/dict construction** - Creating 100 Python objects takes time
2. **Type conversion** - Converting Redis strings to Python strings
3. **Memory allocation** - Python's memory model is less efficient than JVM

### Folio Layer: Interpreted Runtime Overhead

The Folio layer shows **~96x overhead** on average. This is where the interpreted Python runtime hurts most:

**What's happening in a Folio query:**
1. Parse the Filter expression
2. Iterate all records in ConcurrentMap cache
3. For each record, evaluate the Filter against its tags
4. Build the result Grid with type-safe columns
5. Handle Ref interning for object identity

Each of these steps involves many function calls, type checks, and object allocations. In Python:
- Function calls are expensive (~100ns each)
- Type checking is dynamic (runtime cost)
- Object allocation goes through Python's GC

### Python Redis vs HTTP: Network vs Local

Python Redis (21.96ms) is **14.5x faster** than SkySpark HTTP (318.34ms):

| Factor | SkySpark HTTP | Python Redis |
|--------|---------------|--------------|
| Network | HTTP round-trip | Local socket |
| Serialization | JSON/Zinc encode/decode | Direct memory |
| Auth | SCRAM per request | None (local) |
| Server overhead | Full SkySpark stack | Redis + HxRedis |

The key insight: **even with Python's 96x Folio overhead**, local Redis access is still 14.5x faster than HTTP API access.

---

## Practical Implications

### When is Python HxRedis Good Enough?

At **22ms average query time**, Python HxRedis is suitable for:

- **Batch analytics** - Processing thousands of records in Python
- **ML/AI integration** - Loading building data into pandas/numpy
- **Data science workflows** - Interactive exploration in Jupyter
- **Background processing** - Non-real-time data pipelines

### When Should You Use Fantom/JVM?

At **0.228ms average query time**, Fantom/JVM is required for:

- **Real-time systems** - Sub-millisecond response requirements
- **High-throughput servers** - Thousands of queries per second
- **Production Haxall** - Runtime performance matters

### The Tradeoff

| Runtime | Query Time | Use Case |
|---------|------------|----------|
| Fantom/JVM | 0.228ms | Production, real-time |
| Python | 21.96ms | Analytics, ML integration |
| HTTP API | 318.34ms | Remote access, web apps |

---

## Running the Benchmarks

### Fantom/JVM Benchmark

```bash
cd python-fantom
./build-haxall.sh --build-only
fan hxRedis::HxRedisBenchmark
```

### Python Benchmark

```bash
cd python-fantom
python scripts/benchmark_skyspark_to_redis.py
```

**Prerequisites:**
- Redis running on localhost:6379
- SkySpark running on localhost:8081 (for HTTP comparison)

---

## Benchmark Scripts

- **Fantom:** `haxall/src/core/hxRedis/test/HxRedisBenchmark.fan`
- **Python:** `scripts/benchmark_skyspark_to_redis.py`

Both scripts use the same test methodology for fair comparison.

---

## Future Optimization Opportunities

### Python Performance

1. **Cython compilation** - Compile hot paths to C
2. **PyPy runtime** - JIT compilation for Python
3. **Native extensions** - C extensions for Filter evaluation
4. **Connection pooling** - Reuse Redis connections

### HxRedis Architecture

1. **Batch operations** - Pipeline multiple Redis commands
2. **Lazy loading** - Don't load all tags until accessed
3. **Index optimization** - Use Redis sorted sets for range queries
4. **Caching** - Cache Filter parse results

---

## Conclusion

The benchmark results confirm that **Python transpilation trades runtime performance for ecosystem access**:

- Raw Redis performance is nearly identical (1.1-2.1x overhead)
- Folio layer adds ~96x overhead from interpreted code
- Python Redis is still 14.5x faster than HTTP API access
- 22ms query times are acceptable for analytics/ML use cases

The tradeoff is reasonable: Python users get full Folio API compatibility with access to the entire Python data science ecosystem, at a cost of ~100x slower queries compared to JVM. For batch processing and analytics workflows, this is an acceptable price.
