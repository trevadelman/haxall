//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Trevor Adelman  Creation
//   28 Jan 2026  Trevor Adelman  Add logging for better observability
//

using concurrent
using xeto
using haystack
using folio

**
** HxRedis is a Redis-backed `Folio` implementation.
**
** This implementation stores records in Redis using the following schema:
**   - rec:{id} -> Hash with fields: trio (encoded record), mod, trash
**   - idx:all -> Set of all record IDs
**   - meta:version -> Current database version
**
const class HxRedis : Folio
{

//////////////////////////////////////////////////////////////////////////
// Construction
//////////////////////////////////////////////////////////////////////////

  ** Logger for HxRedis operations (named hxRedisLog to avoid conflict with Folio.log)
  private static const Log hxRedisLog := Log.get("hxRedis")

  **
  ** Open for given directory/config. Redis URI comes from config opts.
  ** Default: redis://localhost:6379/0
  **
  static HxRedis open(FolioConfig config)
  {
    redisUri := config.opts["redisUri"] as Uri ?: `redis://localhost:6379/0`
    hxRedisLog.debug("Opening HxRedis folio: ${config.name} -> $redisUri")
    return make(config, redisUri)
  }

  private new make(FolioConfig config, Uri redisUri)
    : super(config)
  {
    this.redisUri = redisUri
    this.passwords = PasswordStore.open(dir+`passwords.props`, config)
    this.actor = Actor(config.pool) |msg| { onReceive(msg) }
    this.map = ConcurrentMap(1024)
    this.idsMap = ConcurrentMap(1024)

    // Initialize from Redis: load all records into cache
    redis := RedisClient.open(redisUri)
    try
    {
      verStr := redis.get("meta:version")
      curVerRef.val = verStr?.toInt ?: 1

      // Load all records into memory cache
      allIds := redis.smembers("idx:all")
      loadCount := 0
      failCount := 0
      allIds.each |idStr|
      {
        id := internRef(Ref.fromStr(idStr))
        rec := loadRecFromRedis(redis, id)
        if (rec != null)
        {
          map.set(id, rec)
          loadCount++
        }
        else
        {
          failCount++
        }
      }
      hxRedisLog.debug("HxRedis initialized: loaded $loadCount records, version=${curVerRef.val}" +
               (failCount > 0 ? ", failed=$failCount" : ""))
    }
    finally redis.close
  }

//////////////////////////////////////////////////////////////////////////
// Identity
//////////////////////////////////////////////////////////////////////////

  ** Redis connection URI
  const Uri redisUri

  @NoDoc const override PasswordStore passwords
  private const Actor actor

  ** In-memory cache of records (keyed by interned Ref)
  internal const ConcurrentMap map

  ** Map of Ref IDs to interned Refs (for object identity)
  private const ConcurrentMap idsMap

  @NoDoc override Int curVer() { curVerRef.val }
  private const AtomicInt curVerRef := AtomicInt(1)

  **
  ** Intern a Ref to ensure object identity.
  ** Same ID always returns the same Ref object.
  **
  override Ref internRef(Ref id)
  {
    if (id.isRel && idPrefix != null) id = id.toAbs(idPrefix)
    intern := idsMap.get(id) as Ref
    if (intern != null) return intern
    idsMap.set(id, id)
    return id
  }

  **
  ** Load a record from Redis and normalize its Refs.
  ** Used during initialization to populate the cache.
  **
  private Dict? loadRecFromRedis(RedisClient redis, Ref id)
  {
    key := "rec:${id}"
    data := redis.hgetall(key)
    if (data.isEmpty) return null

    trioStr := data["trio"]
    if (trioStr == null) return null

    try
    {
      rawRec := TrioReader(trioStr.in).readDict
      // Normalize all Refs in the record
      tags := Str:Obj[:]
      rawRec.each |v, n|
      {
        if (v is Ref)
          tags[n] = internRef(v)
        else
          tags[n] = v
      }
      rec := Etc.makeDict(tags)
      rec.id.disVal = rec.dis
      return rec
    }
    catch (Err e)
    {
      hxRedisLog.warn("Failed to parse record $id during init: $e.msg")
      return null
    }
  }

//////////////////////////////////////////////////////////////////////////
// Folio
//////////////////////////////////////////////////////////////////////////

  @NoDoc override Str flushMode
  {
    get { "fsync" }
    set { throw UnsupportedErr("flushMode") }
  }

  @NoDoc override Void flush() {}

  @NoDoc override FolioFuture doCloseAsync()
  {
    // Send close message to actor to cleanup connection pool
    actor.send(HxRedisMsg("close", null, null))
    return FolioFuture.makeSync(CountFolioRes(0))
  }

  @NoDoc override FolioRec? doReadRecById(Ref id)
  {
    // Use in-memory cache for object identity
    rec := map.get(internRef(id)) as Dict
    if (rec == null && id.isRel && idPrefix != null)
      rec = map.get(internRef(id.toAbs(idPrefix))) as Dict
    if (rec != null && rec.missing("trash"))
      return HxRedisRec(rec)
    else
      return null
  }

  @NoDoc override FolioFuture doReadByIds(Ref[] ids)
  {
    // Use in-memory cache for object identity
    errMsg := ""
    dicts := Dict?[,]
    dicts.size = ids.size
    ids.each |id, i|
    {
      rec := map.get(internRef(id)) as Dict
      if (rec == null && id.isRel && idPrefix != null)
        rec = map.get(internRef(id.toAbs(idPrefix))) as Dict

      if (rec != null && rec.missing("trash"))
        dicts[i] = rec
      else if (errMsg.isEmpty)
        errMsg = id.toStr
    }
    errs := !errMsg.isEmpty
    return FolioFuture.makeSync(ReadFolioRes(errMsg, errs, dicts))
  }

  @NoDoc override FolioFuture doReadAll(Filter filter, Dict? opts)
  {
    errMsg := filter.toStr
    acc := Dict[,]
    doReadAllEachWhile(filter, opts) |rec| { acc.add(rec); return null }
    if (opts != null && opts.has("sort")) acc = Etc.sortDictsByDis(acc)
    return FolioFuture.makeSync(ReadFolioRes(errMsg, false, acc))
  }

  @NoDoc override Int doReadCount(Filter filter, Dict? opts)
  {
    count := 0
    doReadAllEachWhile(filter, opts) |->| { count++ }
    return count
  }

  @NoDoc override Obj? doReadAllEachWhile(Filter filter, Dict? opts, |Dict->Obj?| f)
  {
    if (opts == null) opts = Etc.dict0
    limit := (opts["limit"] as Number)?.toInt ?: 10_000
    skipTrash := opts.missing("trash")

    hooks := this.hooks
    // Create context for filter matching - use cache for lookups
    cx := PatherContext(
      |Ref id->Dict?| { map.get(internRef(id)) },
      |Bool checked->Namespace?| { hooks.ns(checked) }
    )

    count := 0
    return map.eachWhile |val|
    {
      rec := val as Dict
      if (rec == null) return null
      if (!filter.matches(rec, cx)) return null
      if (rec.has("trash") && skipTrash) return null
      count++
      x := f(rec)
      if (x != null) return x
      return count >= limit ? "break" : null
    }
  }

  **
  ** Get candidate record IDs based on filter optimization.
  ** For simple "has" filters, use the tag index.
  ** For complex filters, fall back to idx:all.
  **
  private Str[] getCandidateIds(RedisClient redis, Filter filter)
  {
    // Try to extract a simple "has" tag from the filter
    hasTag := extractHasTag(filter)
    if (hasTag != null)
    {
      tagIds := redis.smembers("idx:tag:$hasTag")
      if (!tagIds.isEmpty) return tagIds
    }

    // Fall back to all records
    return redis.smembers("idx:all")
  }

  **
  ** Try to extract a simple tag name from a "has" filter.
  ** Returns the tag name or null if not a simple "has" filter.
  **
  private Str? extractHasTag(Filter filter)
  {
    // Filter.toStr for has(tag) returns just the tag name
    // For compound filters it returns "tag1 and tag2" etc.
    filterStr := filter.toStr

    // If it's a simple identifier (no spaces, operators), it's a "has" filter
    if (!filterStr.contains(" ") &&
        !filterStr.contains("==") &&
        !filterStr.contains("!=") &&
        !filterStr.contains("<") &&
        !filterStr.contains(">") &&
        !filterStr.contains("("))
    {
      return filterStr
    }

    return null
  }

  @NoDoc override FolioFuture doCommitAllAsync(Diff[] diffs, Obj? cxInfo)
  {
    // Check diffs on caller's thread
    diffs = diffs.toImmutable
    FolioUtil.checkDiffs(diffs)

    // Send message to background actor
    return FolioFuture(actor.send(HxRedisMsg("commit", diffs, cxInfo)))
  }

  @NoDoc override FolioHis his() { hisRef }
  private const HxRedisHis hisRef := HxRedisHis(this)

  @NoDoc override FolioBackup backup() { throw UnsupportedErr() }

  @NoDoc override FolioFile file() { throw UnsupportedErr() }

  **
  ** Override sync to handle disMacro synchronization.
  ** When mgr == "dis", recalculate all disMacro display values.
  **
  @NoDoc override This sync(Duration? timeout := null, Str? mgr := null)
  {
    if (mgr == "dis") syncDis
    return this
  }

  **
  ** Recalculate display values for all records with disMacro.
  **
  private Void syncDis()
  {
    cache := Ref:Str[:]
    map.each |val|
    {
      rec := val as Dict
      if (rec == null) return
      dis := toDis(cache, rec.id)
      rec.id.disVal = dis
    }
  }

  **
  ** Compute display string for a Ref with cycle detection via cache.
  ** Pattern from DisMgr: put default in cache BEFORE recursing.
  **
  internal Str toDis(Ref:Str cache, Ref id)
  {
    // Check cache first
    x := cache[id]
    if (x != null) return x

    // Put default (id string) in cache BEFORE computing
    // This prevents infinite cycles - if we hit this id again, we get the id string
    cache[id] = id.id

    // Now compute actual display
    rec := map.get(id) as Dict
    if (rec != null)
    {
      disMacro := rec["disMacro"] as Str
      if (disMacro != null)
        cache[id] = HxRedisMacro(disMacro, rec, this, cache).apply
      else
        cache[id] = rec.dis
    }
    // If record doesn't exist (deleted), disVal stays as id string

    // Update the Ref's disVal so Dict.dis and Ref.dis work correctly
    id.disVal = cache[id]

    return cache[id]
  }

//////////////////////////////////////////////////////////////////////////
// Redis Record I/O
//////////////////////////////////////////////////////////////////////////

  **
  ** Read a record from Redis by ID.
  ** Returns the Dict or null if not found.
  **
  internal Dict? readRecFromRedis(RedisClient redis, Ref id)
  {
    key := "rec:${id}"
    data := redis.hgetall(key)
    if (data.isEmpty) return null

    // Decode Trio-encoded record
    trioStr := data["trio"]
    if (trioStr == null) return null

    try
    {
      rec := TrioReader(trioStr.in).readDict
      return rec
    }
    catch (Err e)
    {
      hxRedisLog.warn("Failed to parse record $id from Redis: $e.msg")
      return null
    }
  }

  **
  ** Write a record to Redis.
  **
  private Void writeRecToRedis(RedisClient redis, Dict rec, Dict? oldRec := null)
  {
    id := rec.id
    key := "rec:${id}"

    // Encode as Trio
    buf := StrBuf()
    TrioWriter(buf.out).writeDict(rec)
    trioStr := buf.toStr

    // Store in Redis hash
    redis.hset(key, "trio", trioStr)
    redis.hset(key, "mod", rec["mod"]?.toStr ?: "")

    // Add to all-records index
    redis.sadd("idx:all", [id.toStr])

    // Update tag indexes
    updateTagIndexes(redis, id, oldRec, rec)
  }

  **
  ** Remove a record from Redis.
  ** oldRec must be passed in because we can't read inside a MULTI transaction.
  **
  private Void removeRecFromRedis(RedisClient redis, Ref id, Dict? oldRec)
  {
    key := "rec:${id}"
    redis.del([key])
    redis.srem("idx:all", [id.toStr])

    // Remove from all tag indexes
    if (oldRec != null)
    {
      oldRec.each |v, n|
      {
        if (n != "id" && n != "mod")
          redis.srem("idx:tag:$n", [id.toStr])
      }
    }
  }

  **
  ** Update tag indexes when a record changes.
  ** Adds new tags to indexes, removes old tags from indexes.
  **
  private Void updateTagIndexes(RedisClient redis, Ref id, Dict? oldRec, Dict newRec)
  {
    idStr := id.toStr

    // Gather old tags
    oldTags := Str:Obj[:]
    if (oldRec != null)
      oldRec.each |v, n| { if (n != "id" && n != "mod") oldTags[n] = v }

    // Gather new tags
    newTags := Str:Obj[:]
    newRec.each |v, n| { if (n != "id" && n != "mod") newTags[n] = v }

    // Remove from indexes for tags no longer present
    oldTags.each |v, n|
    {
      if (!newTags.containsKey(n))
        redis.srem("idx:tag:$n", [idStr])
    }

    // Add to indexes for new tags
    newTags.each |v, n|
    {
      if (!oldTags.containsKey(n))
        redis.sadd("idx:tag:$n", [idStr])
    }
  }

  **
  ** Get record IDs that have a specific tag.
  **
  internal Str[] getIdsByTag(RedisClient redis, Str tag)
  {
    redis.smembers("idx:tag:$tag")
  }

//////////////////////////////////////////////////////////////////////////
// Actor Processing
//////////////////////////////////////////////////////////////////////////

  private Obj? onReceive(HxRedisMsg msg)
  {
    switch (msg.id)
    {
      case "commit":  return onCommit(msg.a, msg.b)
      case "close":   return onClose
      default:        throw Err("Invalid msg: $msg")
    }
  }

  **
  ** Get or create the Redis connection pool.
  ** Pool is stored in Actor.locals for reuse across commits.
  ** Internal visibility for HxRedisHis access.
  **
  internal RedisConnPool getPool()
  {
    pool := Actor.locals["redisPool"] as RedisConnPool
    if (pool == null)
    {
      pool = RedisConnPool(redisUri)
      Actor.locals["redisPool"] = pool
      hxRedisLog.debug("Created Redis connection pool for Actor")
    }
    return pool
  }

  **
  ** Apply a single diff to the in-memory cache and optionally to Redis.
  ** Extracted from onCommit to avoid nested closure (Python transpiler limitation).
  **
  private Void applyDiffToCache(Diff diff, Int i, RedisClient redis, HxRedisCommit[] commits)
  {
    id := internRef(diff.id)
    if (diff.isRemove)
    {
      map.remove(id)
      if (!diff.isTransient)
        removeRecFromRedis(redis, diff.id, commits[i].oldRec)
    }
    else
    {
      map.set(id, diff.newRec)
      if (!diff.isTransient)
        writeRecToRedis(redis, diff.newRec, commits[i].oldRec)
    }
  }

  **
  ** Close the pool when folio is closed.
  **
  private Obj? onClose()
  {
    pool := Actor.locals["redisPool"] as RedisConnPool
    if (pool != null)
    {
      pool.close
      Actor.locals.remove("redisPool")
      hxRedisLog.debug("Closed Redis connection pool")
    }
    return null
  }

  private CommitFolioRes onCommit(Diff[] diffs, Obj? cxInfo)
  {
    pool := getPool
    return pool.execute |redis->CommitFolioRes|
    {
      // Map diffs to commit handlers
      newMod := DateTime.nowUtc(null)
      commits := HxRedisCommit[,]
      diffs.each |diff|
      {
        nm := (newMod <= diff.oldMod) ? diff.oldMod + 1ms : newMod
        commits.add(HxRedisCommit(this, redis, diff, nm, cxInfo))
      }

      // Verify all commits upfront and call pre-commit
      hooks := this.hooks
      commits.each |c|
      {
        c.verify
        hooks.preCommit(c.event)
      }

      // Apply to compute new record Dict
      diffs = commits.map |c->Diff| { c.apply }

      // Check if any diffs are non-transient (require Redis persistence)
      hasNonTransient := diffs.any |d| { !d.isTransient }

      // Start Redis transaction for non-transient commits
      // This ensures atomic writes - either all succeed or none do
      if (hasNonTransient) redis.multi

      try
      {
        // Update in-memory cache; only update Redis for non-transient
        // Note: Extracted to method to avoid nested closure (Python transpiler limitation)
        diffs.each |diff, i| { applyDiffToCache(diff, i, redis, commits) }

        // Update version if non-transient
        if (hasNonTransient)
        {
          newVer := curVerRef.incrementAndGet
          redis.set("meta:version", newVer.toStr)
        }

        // Execute Redis transaction
        if (hasNonTransient)
        {
          results := redis.exec
          if (results == null)
            throw Err("Redis transaction aborted (concurrent modification)")
        }
      }
      catch (Err e)
      {
        // Discard transaction on error
        if (hasNonTransient)
        {
          try { redis.discard } catch {}
        }
        throw e
      }

      // Post commit (only after successful Redis write)
      commits.each |c|
      {
        hooks.postCommit(c.event)
      }

      // Return result diffs
      return CommitFolioRes(diffs)
    }
  }
}

**************************************************************************
** HxRedisMsg
**************************************************************************

internal const class HxRedisMsg
{
  new make(Str id, Obj? a, Obj? b) { this.id = id; this.a = a; this.b = b }
  const Str id
  const Obj? a
  const Obj? b
}

**************************************************************************
** HxRedisRec
**************************************************************************

internal const class HxRedisRec : FolioRec
{
  new make(Dict dict) { this.dict = dict }
  const override Dict dict
  override Int ticks() { DateTime.nowTicks }
  override Int watchCount() { 0 }
  override Int watchIncrement() { 0 }
  override Int watchDecrement() { 0 }
}

**************************************************************************
** HxRedisCommit
**************************************************************************

internal class HxRedisCommit
{
  new make(HxRedis folio, RedisClient redis, Diff diff, DateTime newMod, Obj? cxInfo)
  {
    this.folio  = folio
    this.redis  = redis
    this.id     = folio.internRef(diff.id)
    this.inDiff = diff
    this.newMod = newMod
    // Use cache for oldRec to maintain object identity
    this.oldRec = folio.map.get(this.id) as Dict
    this.oldMod = inDiff.oldMod
    this.event  = HxRedisCommitEvent(diff, oldRec, cxInfo)
  }

  HxRedis folio
  RedisClient redis
  Ref id
  Diff inDiff
  DateTime newMod
  Dict? oldRec
  DateTime? oldMod
  HxRedisCommitEvent event

  Void verify()
  {
    // Sanity check oldRec
    if (inDiff.isAdd)
    {
      if (oldRec != null) throw CommitErr("Rec already exists: $id")
    }
    else
    {
      if (oldRec == null) throw CommitErr("Rec not found: $id")

      // Unless the force flag was specified check for concurrent change errors
      if (!inDiff.isForce && oldRec->mod != oldMod)
        throw ConcurrentChangeErr("$id: ${oldRec->mod} != $oldMod")
    }

    return this
  }

  Diff apply()
  {
    // Construct new rec
    tags := Str:Obj[:]
    if (oldRec != null) oldRec.each |v, n| { tags[n] = v }
    inDiff.changes.each |v, n|
    {
      if (v === Remove.val) tags.remove(n)
      else tags[n] = norm(v)
    }
    tags["id"] = id
    if (!inDiff.isTransient) tags["mod"] = this.newMod
    newRec := Etc.makeDict(tags)
    newRec.id.disVal = newRec.dis

    // Return applied Diff
    outDiff := Diff.makeAll(id, oldMod, oldRec, newMod, newRec, inDiff.changes, inDiff.flags)
    event.diff = outDiff
    return outDiff
  }

  private Obj norm(Obj val)
  {
    Etc.mapRefs(val) |ref| { normRef(ref) }
  }

  private Ref normRef(Ref id)
  {
    // Use interned Refs from cache for object identity
    id = folio.internRef(id)
    rec := folio.map.get(id) as Dict
    if (rec != null) return rec.id
    if (id.disVal != null) id = Ref(id.id, null)
    return id
  }
}

**************************************************************************
** HxRedisCommitEvent
**************************************************************************

internal class HxRedisCommitEvent : FolioCommitEvent
{
  new make(Diff diff, Dict? oldRec, Obj? cxInfo)
  {
    this.diff   = diff
    this.oldRec = oldRec
    this.cxInfo = cxInfo
  }

  override Diff diff
  override Dict? oldRec
  override Obj? cxInfo
}

**************************************************************************
** HxRedisMacro
**************************************************************************

**
** HxRedisMacro extends Macro to resolve Ref display values via toDis.
** This is the same pattern as DisMgrMacro in hxFolio.
**
internal class HxRedisMacro : Macro
{
  new make(Str pattern, Dict scope, HxRedis folio, Ref:Str cache)
    : super(pattern, scope)
  {
    this.folio = folio
    this.cache = cache
  }

  HxRedis folio
  Ref:Str cache

  override Str refToDis(Ref ref)
  {
    folio.toDis(cache, folio.internRef(ref))
  }
}
