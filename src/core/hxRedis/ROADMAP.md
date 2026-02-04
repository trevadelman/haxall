# hxRedis Roadmap

> **IMPORTANT:** Only **Phase 1 (Redis TimeSeries Integration)** is approved for implementation.
> All other phases are ideas for discussion and require vetting before any work begins.

---

## Current State (v1.0)

**Status:** Production-ready for metadata, functional for history

**Completed:**
- Full Folio API implementation (CRUD, filters, commits)
- History read/write via Sorted Sets
- Connection pooling with health checks
- Redis transactions (MULTI/EXEC)
- Authentication via URI
- Trio encoding for records
- In-memory cache for reads
- Tag indexes for query optimization
- Haxall daemon integration via `fan.props`

**Test Coverage:**
- 63 test methods passing
- testFolio integration tests passing

---

## Phase 1: Redis TimeSeries Integration (APPROVED)

**Goal:** Optimize history performance for production workloads (100K+ points, 100K+ samples each)

**Status:** APPROVED - Ready for implementation

### 1.1 RedisClient TimeSeries Commands

**File:** `fan/RedisClient.fan`

Add commands for Redis TimeSeries module:

```fantom
// Module detection
Obj[] moduleList()

// TimeSeries operations
Void tsCreate(Str key, Dict? opts)
Void tsAdd(Str key, Int timestamp, Float value)
Void tsMadd(Str[] keysTimestampsValues)  // Bulk write
Obj[] tsRange(Str key, Int start, Int end)
Int tsDelRange(Str key, Int start, Int end)
```

**Effort:** ~50 lines

### 1.2 Module Detection at Startup

**File:** `fan/HxRedis.fan`

```fantom
// Add field
private const Bool hasTimeSeries

// In make() - one-time check
redis := RedisClient.open(redisUri)
modules := redis.moduleList
hasTimeSeries = modules.any |m| { m["name"] == "timeseries" }
```

**Effort:** ~20 lines

### 1.3 HxRedisHis Dual Implementation

**File:** `fan/HxRedisHis.fan`

Implement both backends with automatic routing:

```fantom
override Dict write(Ref id, HisItem[] items, Dict? opts)
{
  if (folio.hasTimeSeries)
    return writeTimeSeries(id, items, opts)
  else
    return writeSortedSet(id, items, opts)
}

private Dict writeTimeSeries(Ref id, HisItem[] items, Dict? opts)
{
  // Use TS.MADD for bulk writes
  // ~10x faster than Sorted Sets
}

private Dict writeSortedSet(Ref id, HisItem[] items, Dict? opts)
{
  // Current implementation (fallback)
}
```

**Effort:** ~100 lines

### 1.4 Testing

- Test with Redis Stack (has TimeSeries)
- Test fallback with plain Redis
- Benchmark: Sorted Sets vs TimeSeries

**Effort:** ~50 lines

### Phase 1 Success Criteria

- [ ] `MODULE LIST` detection works
- [ ] TimeSeries commands implemented
- [ ] Auto-routing based on module availability
- [ ] Fallback to Sorted Sets works
- [ ] 10x+ improvement for bulk history writes

---

## Phase 2: History Performance Optimization (NOT VETTED)

**Goal:** Further optimize history for edge cases

**Status:** IDEA ONLY - Requires vetting before implementation

### 2.1 Pipelining for Sorted Sets Fallback

When TimeSeries isn't available, batch ZADD operations:

```fantom
// Instead of N round trips:
items.each |item| { redis.zadd(...) }

// One round trip:
redis.pipeline {
  items.each |item| { it.zadd(...) }
}
```

### 2.2 History Caching

Cache recent history reads in memory:

```fantom
// Cache last N hours of history per point
private const ConcurrentMap hisCache  // id -> HisItem[]
```

### 2.3 Async History Writes

Write to local buffer, sync to Redis in background:

```fantom
// Immediate return, async persist
Actor.send(HxRedisMsg("hisWrite", id, items))
```

### Phase 2 Success Criteria

- [ ] Pipelining improves Sorted Set writes by 5x
- [ ] History cache reduces read latency
- [ ] Async writes don't block callers

---

## Phase 3: Clustering & High Availability (NOT VETTED)

**Goal:** Support Redis Cluster and Sentinel

**Status:** IDEA ONLY - Requires vetting before implementation

### 3.1 Redis Sentinel Support

Automatic failover for high availability:

```fantom
// URI format: sentinel://master-name@host1:26379,host2:26379
static RedisClient openSentinel(Str masterName, Uri[] sentinels)
```

### 3.2 Redis Cluster Support

Sharding across multiple Redis nodes:

```fantom
// URI format: cluster://host1:6379,host2:6379,host3:6379
// Key hashing for record distribution
```

### 3.3 Read Replicas

Route reads to replicas for scaling:

```fantom
// Write to primary, read from replica
```

### Phase 3 Success Criteria

- [ ] Sentinel failover works
- [ ] Cluster sharding works
- [ ] Read replicas reduce primary load

---

## Phase 4: Advanced Features (NOT VETTED)

**Goal:** Enterprise-grade capabilities

**Status:** IDEA ONLY - Requires vetting before implementation

### 4.1 Change Notifications (Pub/Sub)

Notify other services when records change:

```fantom
// On commit, publish to channel
redis.publish("folio:changes", changeJson)
```

### 4.2 Audit Logging (Streams)

Append-only log of all changes:

```fantom
// On commit, append to stream
redis.xadd("audit:folio", ["action":"commit", "id":id, ...])
```

### 4.3 Backup/Restore API

```fantom
// Export to JSON/Trio
Str export(Filter filter)

// Import from JSON/Trio
Int import(Str data)
```

### 4.4 FolioBackup Implementation

Currently throws `UnsupportedErr`. Implement using Redis persistence:

```fantom
override FolioBackup backup()
{
  // Use BGSAVE or export to file
}
```

### Phase 4 Success Criteria

- [ ] Pub/Sub notifications work
- [ ] Audit stream captures all changes
- [ ] Backup/restore implemented

---

## Phase 5: Observability & Operations (NOT VETTED)

**Goal:** Production monitoring and debugging

**Status:** IDEA ONLY - Requires vetting before implementation

### 5.1 Metrics

```fantom
// Expose metrics for monitoring
Int readCount()
Int writeCount()
Int cacheHitRate()
Duration avgLatency()
```

### 5.2 Health Endpoint

```fantom
// For load balancer health checks
Dict healthCheck()
{
  Etc.dict2(
    "status", redis.ping == "PONG" ? "healthy" : "unhealthy",
    "latency", latencyMs
  )
}
```

### 5.3 Debug Commands

```fantom
// Dump internal state
Dict debug()
{
  Etc.dict4(
    "cacheSize", map.size,
    "poolStats", pool.debug,
    "hasTimeSeries", hasTimeSeries,
    "version", curVer
  )
}
```

### Phase 5 Success Criteria

- [ ] Metrics exposed for Prometheus/etc
- [ ] Health endpoint for K8s probes
- [ ] Debug tools for troubleshooting

---

## Future Considerations

### TLS/SSL Support

```fantom
// rediss:// scheme for TLS
static RedisClient open(`rediss://host:6379`)
```

### ACL Support (Redis 6+)

```fantom
// Username + password auth
// redis://user:password@host:6379
```

### Lua Scripting

For complex atomic operations:

```fantom
Obj eval(Str script, Str[] keys, Obj[] args)
```

### Multi-Tenancy

Namespace isolation for SaaS deployments:

```fantom
// Prefix all keys with tenant ID
// tenant:123:rec:abc -> record
```

---

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0 | 2026-01-28 | Initial release - full Folio API |
| 1.1 | TBD | Phase 1 - TimeSeries integration |

---

## Contributing

See `readme.md` for API documentation and usage examples.

To run tests:
```bash
fant hxRedis           # Unit tests
fant testFolio         # Integration tests
```
