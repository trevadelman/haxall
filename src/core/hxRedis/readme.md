# hxRedis - Redis-Backed Folio Implementation

A pure Fantom implementation of the Folio database API backed by Redis. This provides a transpiler-friendly storage engine that runs natively.

## Overview

hxRedis implements the `Folio` abstract class using Redis as the backing store instead of the Java-based hxStore. This enables:

- **Non-JVM database backend** - Redis instead of Java blob storage
- **Pure Fantom implementation** - No Java native code, fully transpilable

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
│   - Ref interning for identity          │
│   - Actor for write serialization       │
│   - disMacro resolution                 │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│            RedisClient                  │
│   - Pure Fantom RESP protocol           │
│   - inet::TcpSocket networking          │
│   - No external dependencies            │
└─────────────────────────────────────────┘
                    │
                    ▼
┌─────────────────────────────────────────┐
│              Redis Server               │
│   - In-memory key-value store           │
│   - RDB/AOF persistence                 │
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

## Features

### Core CRUD Operations
- `readById(id)` - Single record lookup
- `readByIds(ids)` - Batch record lookup
- `readAll(filter)` - Filter-based queries
- `readCount(filter)` - Count queries
- `commit(diff)` - Add, update, remove records

### Advanced Features
- **Ref Interning** - Same ID always returns same Ref object
- **Object Identity** - ConcurrentMap cache ensures `verifyRecSame` tests pass
- **Transient Commits** - Skip Redis persistence for temporary changes
- **Trash Handling** - Soft delete with trash flag
- **disMacro Support** - Display macro resolution with cycle detection
- **Tag Indexes** - Automatic index maintenance for optimized queries
- **Concurrent Change Detection** - Prevents lost updates

### Test Suite Results

**testFolio (AbstractFolioTest):**
- 7 types, 23 methods, 9964 verifications - ALL PASSING

**hxRedis internal tests:**
- 4 types, 41 methods, 1112 verifications - ALL PASSING

### Benchmark Summary

| Runtime | Query Time | Use Case |
|---------|------------|----------|
| Fantom/JVM | 0.228ms | Production, real-time |
| Python | 21.96ms | Analytics, ML integration |
| HTTP API | 318.34ms | Remote access |

**Key findings:**
- Fantom/JVM is ~96x faster than Python for Folio operations
- Python Redis is 14.5x faster than SkySpark HTTP API
- Raw Redis ops show minimal overhead (1.1-2.1x) - the difference is in the Folio layer

For detailed methodology and analysis, see [benchmarks.md](benchmarks.md).


## Usage

### Prerequisites

```bash
# Install Redis (macOS)
brew install redis
brew services start redis

# Verify Redis is running
redis-cli ping  # Should return PONG
```

### Building

```bash
cd haxall
fan src/core/hxRedis/build.fan
```

### Running Tests

```bash
# Run hxRedis internal tests
fan test hxRedis

# Run against AbstractFolioTest suite
fan test testFolio
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
diff := Diff.makeAdd(Etc.dict2("dis", "My Site", "site", Marker.val))
folio.commit(diff)

// Query records
sites := folio.readAll(Filter.has("site"))

// Close
folio.close
```

## File Structure

```
haxall/src/core/hxRedis/
├── build.fan                 # Pod build configuration
├── README.md                 # This file
├── fan/
│   ├── HxRedis.fan           # Main Folio implementation (~530 lines)
│   └── RedisClient.fan       # Redis RESP protocol client (~270 lines)
└── test/
    ├── HxRedisTest.fan       # Basic CRUD tests
    ├── HxRedisTortureTest.fan  # Stress/edge case tests
    ├── HxRedisTestImpl.fan   # AbstractFolioTest integration
    ├── RedisClientTest.fan   # Redis client unit tests
    └── RedisClientTortureTest.fan  # Redis client stress tests
```

## Implementation Details

### RedisClient

Pure Fantom implementation of the Redis RESP protocol using `inet::TcpSocket`:

- **No external JARs** - Just Fantom's built-in networking
- **Full RESP support** - Strings, hashes, sets, sorted sets

### HxRedis

Folio implementation following the FolioFlatFile pattern:

- **ConcurrentMap cache** - In-memory record storage for fast reads
- **Actor for writes** - Serialized write operations prevent race conditions
- **Ref interning** - `internRef()` ensures object identity
- **disMacro** - Uses Macro class with custom refToDis resolution

### Test Framework Integration

The `HxRedisTestImpl` class integrates with AbstractFolioTest:

```fantom
class HxRedisTestImpl : FolioTestImpl
{
  override Str name() { "hxRedis" }
  override Bool supportsHis() { false }
  override Bool supportsIdPrefixRename() { false }
  // ...
}
```

## Limitations

- **History API** - Not yet implemented (Phase 6)
- **FolioBackup** - Throws UnsupportedErr
- **FolioFile** - Throws UnsupportedErr
- **idPrefixRename** - Not supported


## License

Licensed under the Academic Free License version 3.0
