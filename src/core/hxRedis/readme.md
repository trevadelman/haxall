# hxRedis - Redis-Backed Folio Implementation

A pure Fantom implementation of the Folio database API backed by Redis. Provides a storage engine with connection pooling, transactions, and fail-fast error handling.

## Overview

hxRedis implements the `Folio` abstract class using Redis as the backing store. All data operations go through Redis while reads are served from an in-memory cache for performance.

**Key characteristics:**
- **Pure Fantom** - No Java native code, fully transpilable
- **Robust features** - Connection pooling, socket timeouts, authentication, transactions
- **Simple API** - Standard Folio interface, drop-in replacement for other implementations
- **Fail-fast** - Errors surface immediately, no hidden retries or magic

## Architecture

```
┌─────────────────────────────────────────┐
│         Folio API (folio pod)           │
│   readById, readAll, commit, etc.       │
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
│            RedisConnPool                │
│   - Lock-based thread-safe pooling      │
│   - Configurable pool size              │
│   - Health check support                │
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

### Code Example

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
fant hxRedis
```

**Results:** 70+ test methods covering:
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
| `zadd/zrangebyscore` | Sorted set operations |
| `multi/exec/discard` | Transactions |
| `watch/unwatch` | Optimistic locking |
| `pipeline { }` | Batch commands in single round trip |

### RedisConnPool

| Method | Description |
|--------|-------------|
| `make(uri, poolSize)` | Create pool (default 3 connections) |
| `execute { }` | Run callback with pooled connection |
| `close()` | Close all connections |
| `checkHealth()` | Validate connections with PING |
| `debug()` | Pool statistics |

### HxRedis

Standard Folio interface plus:

| Method | Description |
|--------|-------------|
| `open(config)` | Open folio with redisUri in opts |
| `readById/readAll` | Reads from in-memory cache |
| `commit` | Writes via transaction to Redis |
| `internRef` | Ref interning for object identity |

## Limitations

- **History API** - Not implemented (`his()` throws UnsupportedErr)
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
