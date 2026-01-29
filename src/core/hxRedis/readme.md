# hxRedis - Redis-Backed Folio Implementation

A pure Fantom implementation of the Folio database API backed by Redis. Provides a storage engine with connection pooling, transactions, history API, and fail-fast error handling.

## Overview

hxRedis implements the `Folio` abstract class using Redis as the backing store. All data operations go through Redis while reads are served from an in-memory cache for performance. History data is stored in Redis Sorted Sets for efficient time-range queries.

**Key characteristics:**
- **Pure Fantom** - No Java native code, fully transpilable to Python
- **Complete Folio API** - CRUD operations, filter queries, history read/write
- **Robust features** - Connection pooling, socket timeouts, authentication, transactions
- **Simple API** - Standard Folio interface, drop-in replacement for other implementations
- **Fail-fast** - Errors surface immediately, no hidden retries or magic

## Architecture

```
┌─────────────────────────────────────────┐
│         Folio API (folio pod)           │
│   readById, readAll, commit, his, etc.  │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│              HxRedis                    │
│   - ConcurrentMap cache (in-memory)     │
│   - Actor for write serialization       │
│   - Ref interning for object identity   │
│   - disMacro resolution                 │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│            HxRedisHis                   │
│   - History read/write via FolioHis     │
│   - Sorted Sets for time-series data    │
│   - Timezone/unit conversion on read    │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│            RedisConnPool                │
│   - Lock-based thread-safe pooling      │
│   - PING validation on conn checkout│
│   - Automatic connection replacement     │
│   - Overflow connection tracking         │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│            RedisClient                  │
│   - Pure Fantom RESP protocol           │
│   - Socket timeouts (5s connect/30s rx) │
│   - Transactions (MULTI/EXEC)           │
│   - Pipelining support                  │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│              Redis Server               │
└─────────────────────────────────────────┘
```

## Redis Data Model

```
# Records stored as Hashes
rec:{id}              → trio (Trio-encoded Dict), mod (timestamp)

# History stored as Sorted Sets
his:{id}              → Sorted Set (score=timestamp ms, value=Trio-encoded HisItem)

# Indexes
idx:all               → Set of all record IDs
idx:tag:{tagName}     → Set of IDs with that tag

# Metadata
meta:version          → Database version counter
```

## Design Decisions

### Connection Pool Uses Locks, Not Actors

The pool uses `Lock.makeReentrant` for thread-safe access rather than Fantom Actors. This is because:

- `RedisClient` holds a mutable TCP socket that cannot be passed in Actor messages (which require immutable types)
- Connection pools fundamentally need to return mutable objects to callers
- This matches how standard connection pools work (HikariCP, c3p0, Go's database/sql)

### Transactions Wrap All Commits

All non-transient folio commits are wrapped in Redis MULTI/EXEC transactions:

- Ensures atomic writes - either all records commit or none do
- Prevents partial failures leaving inconsistent state
- Transaction is discarded on any error

### In-Memory Cache for Reads

All reads come from a `ConcurrentMap` cache, not Redis:

- Eliminates network round trips for reads
- Provides object identity (same Ref object returned for same ID)
- Cache is populated on startup and maintained on commits

### Connection Pool Validates on Checkout

Connections are validated with PING before being returned to callers:

- Stale/dead connections are automatically replaced
- Overflow connections (when pool exhausted) are tracked and closed properly
- No silent failures from bad connections

### History Uses Sorted Sets

History data leverages Redis Sorted Sets for time-series storage:

- Score = timestamp in milliseconds (enables range queries)
- O(log N) insert, O(log N + M) range queries
- ZADD for writes, ZRANGEBYSCORE for reads, ZREMRANGEBYSCORE for clears

### Fail-Fast Error Handling

No automatic retries or hidden error recovery:

- Socket timeouts surface as `IOErr` immediately
- Callers decide how to handle failures
- Explicit `checkHealth()` method when validation is needed

## Usage

### Prerequisites

```bash
# Install Redis
brew install redis
brew services start redis

# Verify
redis-cli ping  # Should return PONG
```

### Connection URI

```
redis://localhost:6379              # Default
redis://localhost:6379/2            # Database 2
redis://:password@localhost:6379    # With authentication
redis://:password@localhost:6379/0  # Auth + database
```

### Using with Haxall Daemon (Recommended)

The simplest way to use hxRedis is with the Haxall daemon via `fan.props`:

**1. Configure fan.props:**
```bash
# In your project's fan.props file:
env.HAXALL_FOLIO_TYPE=redis
env.HAXALL_REDIS_URI=redis://localhost:6379/0
```

**2. Initialize database:**
```bash
fan/bin/fan hx::Main init -headless -suUser su -suPass admin /path/to/db
```

**3. Run daemon:**
```bash
fan/bin/fan hx::Main run /path/to/db
# Access at http://localhost:8080
```

All Haxall features work normally:
- Axon shell for queries
- Extensions (points, tasks, connectors)
- History read/write
- Web UI

The database stores all data in Redis instead of binary blobs on disk.

### Direct Folio API Example

```fantom
// Create config
config := FolioConfig
{
  it.name = "mydb"
  it.dir = `/tmp/mydb/`
  it.opts = Etc.dict1("redisUri", `redis://localhost:6379/0`)
}

// Open folio
folio := HxRedis.open(config)

// Add a record
diff := Diff.makeAdd(["dis":"My Site", "site":Marker.val])
rec := folio.commit(diff).newRec

// Query records
sites := folio.readAll(Filter("site"))

// Close (releases all pooled connections)
folio.close
```

### History API Example

```fantom
// Create a history point
tz := TimeZone("New_York")
pointTags := Etc.dictx(
  "dis", "Temperature Sensor",
  "point", Marker.val,
  "his", Marker.val,
  "tz", "New_York",
  "kind", "Number"
)
point := folio.commit(Diff.makeAdd(pointTags)).newRec

// Write history items
date := Date("2024-01-15")
items := [
  HisItem(date.toDateTime(Time("00:00:00"), tz), n(72.5)),
  HisItem(date.toDateTime(Time("01:00:00"), tz), n(73.0)),
  HisItem(date.toDateTime(Time("02:00:00"), tz), n(73.5)),
]
result := folio.his.write(point.id, items)
echo("Wrote ${result.get("count")} items")

// Read history back
folio.his.read(point.id, null, null) |item|
{
  echo("${item.ts}: ${item.val}")
}

// Read with span (time range query)
span := Span(date.toDateTime(Time("00:30:00"), tz),
             date.toDateTime(Time("01:30:00"), tz))
folio.his.read(point.id, span, null) |item|
{
  echo("${item.ts}: ${item.val}")
}
```

### Using RedisClient Directly

For direct Redis access without the Folio layer:

```fantom
// Basic operations
redis := RedisClient.open(`redis://localhost:6379`)
redis.set("key", "value")
val := redis.get("key")
redis.close

// Transactions
redis.multi
redis.set("a", "1")
redis.set("b", "2")
results := redis.exec  // ["OK", "OK"]

// Pipelining (single round trip)
results := redis.pipeline {
  it.set("x", "1")
  it.set("y", "2")
  it.get("x")
}
// results = ["OK", "OK", "1"]
```

## File Structure

```
haxall/src/core/hxRedis/
├── build.fan                     # Pod build configuration
├── README.md                     # This file
├── fan/
│   ├── HxRedis.fan               # Folio implementation
│   ├── HxRedisHis.fan            # History API implementation
│   ├── RedisClient.fan           # RESP protocol client
│   └── RedisConnPool.fan         # Connection pool
└── test/
    ├── HxRedisTest.fan           # Basic CRUD tests
    ├── HxRedisTortureTest.fan    # Scale/stress tests
    ├── HxRedisTestImpl.fan       # AbstractFolioTest integration
    ├── HxRedisBenchmark.fan      # Performance benchmarks
    ├── RedisClientTest.fan       # Client unit tests
    ├── RedisClientTortureTest.fan # Client stress tests
    └── RedisConnPoolTest.fan     # Pool tests
```

## Test Coverage

```bash
fant testFolio   # Full Folio test suite
fant hxRedis     # hxRedis-specific tests
```

**testFolio Results:** All tests passing - 10,000+ verifications across all Folio implementations including:
- Basic CRUD operations (testBasics)
- Filter queries (testFilters)
- Trash management (testTrash)
- Type handling (testKinds)
- History read/write (HisTest.testBasics, HisTest.testConfig)
- Hooks (testHooks including postHisWrite)

**hxRedis Results:** 63 test methods covering:
- Basic CRUD operations
- Filter queries at scale (1000+ records)
- Transaction atomicity and WATCH conflicts
- Connection pool behavior
- Pipeline operations
- Edge cases (unicode, binary data, large values)

## API Reference

### RedisClient

| Method | Description |
|--------|-------------|
| `open(uri)` | Connect to Redis with optional auth/db |
| `close()` | Close connection |
| `ping()` | Health check, returns "PONG" |
| `get/set/del` | String operations |
| `hget/hset/hgetall` | Hash operations |
| `sadd/srem/smembers` | Set operations |
| `zadd/zrangebyscore/zremrangebyscore` | Sorted set operations |
| `multi/exec/discard` | Transactions |
| `watch/unwatch` | Optimistic locking |
| `pipeline { }` | Batch commands in single round trip |

### RedisConnPool

| Method | Description |
|--------|-------------|
| `make(uri, poolSize)` | Create pool (default 3 connections) |
| `execute { }` | Run callback with pooled connection |
| `close()` | Close all connections (including overflow) |
| `checkHealth()` | Validate and replace dead connections |
| `debug()` | Pool statistics (total, available, errors) |

### HxRedis

Standard Folio interface plus:

| Method | Description |
|--------|-------------|
| `open(config)` | Open folio with redisUri in opts |
| `readById/readAll` | Reads from in-memory cache |
| `commit` | Writes via transaction to Redis |
| `his` | Returns HxRedisHis for history operations |
| `internRef` | Ref interning for object identity |

### HxRedisHis

| Method | Description |
|--------|-------------|
| `read(id, span, opts, f)` | Read history items for record |
| `write(id, items, opts)` | Write history items to record |

**Read options:**
- `limit`: Maximum items to return
- `clipFuture`: Clip items after current time

**Write options:**
- `clear`: Span of items to clear before write
- `clearAll`: Clear all history before write

**Behavior:**
- Timestamps converted to record's `tz` tag on read
- Units applied from record's `unit` tag on read
- Transient tags (hisSize, hisStart, hisEnd) updated automatically

## Limitations

- **FolioBackup** - Not implemented
- **FolioFile** - Not implemented
- **idPrefixRename** - Not supported

## Redis Server Configuration

Recommended Redis settings:

```conf
# Persistence
appendonly yes
appendfsync everysec

# Memory
maxmemory 256mb
maxmemory-policy allkeys-lru

# Security
requirepass your-password-here
```

## License

Licensed under the Academic Free License version 3.0
