//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Trevor Adelman  Creation
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

  **
  ** Open for given directory/config. Redis URI comes from config opts.
  ** Default: redis://localhost:6379/0
  **
  static HxRedis open(FolioConfig config)
  {
    redisUri := config.opts["redisUri"] as Uri ?: `redis://localhost:6379/0`
    return make(config, redisUri)
  }

  private new make(FolioConfig config, Uri redisUri)
    : super(config)
  {
    this.redisUri = redisUri
    this.passwords = PasswordStore.open(dir+`passwords.props`, config)
    this.actor = Actor(config.pool) |msg| { onReceive(msg) }

    // Initialize version from Redis
    redis := RedisClient.open(redisUri)
    try
    {
      verStr := redis.get("meta:version")
      curVerRef.val = verStr?.toInt ?: 1
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

  @NoDoc override Int curVer() { curVerRef.val }
  private const AtomicInt curVerRef := AtomicInt(1)

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
    FolioFuture.makeSync(CountFolioRes(0))
  }

  @NoDoc override FolioRec? doReadRecById(Ref id)
  {
    redis := RedisClient.open(redisUri)
    try
    {
      rec := readRecFromRedis(redis, id)
      if (rec == null && id.isRel && idPrefix != null)
        rec = readRecFromRedis(redis, id.toAbs(idPrefix))
      if (rec != null && rec.missing("trash"))
        return HxRedisRec(rec)
      else
        return null
    }
    finally redis.close
  }

  @NoDoc override FolioFuture doReadByIds(Ref[] ids)
  {
    redis := RedisClient.open(redisUri)
    try
    {
      errMsg := ""
      dicts := Dict?[,]
      dicts.size = ids.size
      ids.each |id, i|
      {
        rec := readRecFromRedis(redis, id)
        if (rec == null && id.isRel && idPrefix != null)
          rec = readRecFromRedis(redis, id.toAbs(idPrefix))

        if (rec != null && rec.missing("trash"))
          dicts[i] = rec
        else if (errMsg.isEmpty)
          errMsg = id.toStr
      }
      errs := !errMsg.isEmpty
      return FolioFuture.makeSync(ReadFolioRes(errMsg, errs, dicts))
    }
    finally redis.close
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

    redis := RedisClient.open(redisUri)
    try
    {
      hooks := this.hooks
      // Create context for filter matching
      cx := PatherContext(
        |Ref id->Dict?| { readRecFromRedis(redis, id) },
        |Bool checked->Namespace?| { hooks.ns(checked) }
      )

      // Optimize: Use tag index for simple "has" filters
      candidateIds := getCandidateIds(redis, filter)
      count := 0

      for (i := 0; i < candidateIds.size; i++)
      {
        idStr := candidateIds[i]
        rec := readRecFromRedis(redis, Ref.fromStr(idStr))
        if (rec == null) continue
        if (!filter.matches(rec, cx)) continue
        if (rec.has("trash") && skipTrash) continue

        count++
        x := f(rec)
        if (x != null) return x
        if (count >= limit) return "break"
      }
      return null
    }
    finally redis.close
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

  @NoDoc override FolioHis his() { throw UnsupportedErr() }

  @NoDoc override FolioBackup backup() { throw UnsupportedErr() }

  @NoDoc override FolioFile file() { throw UnsupportedErr() }

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
  **
  private Void removeRecFromRedis(RedisClient redis, Ref id)
  {
    // Get existing record to clean up indexes
    oldRec := readRecFromRedis(redis, id)

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
      default:        throw Err("Invalid msg: $msg")
    }
  }

  private CommitFolioRes onCommit(Diff[] diffs, Obj? cxInfo)
  {
    redis := RedisClient.open(redisUri)
    try
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

      // Update Redis - pass oldRec for proper index management
      diffs.each |diff, i|
      {
        if (diff.isRemove)
          removeRecFromRedis(redis, diff.id)
        else
          writeRecToRedis(redis, diff.newRec, commits[i].oldRec)
      }

      // Post commit
      commits.each |c|
      {
        hooks.postCommit(c.event)
      }

      // Update version if not transient
      if (!diffs.first.isTransient)
      {
        newVer := curVerRef.incrementAndGet
        redis.set("meta:version", newVer.toStr)
      }

      // Return result diffs
      return CommitFolioRes(diffs)
    }
    finally redis.close
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
    this.id     = normRef(diff.id)
    this.inDiff = diff
    this.newMod = newMod
    this.oldRec = folio.readRecFromRedis(redis, this.id)
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
    if (id.isRel && folio.idPrefix != null) id = id.toAbs(folio.idPrefix)
    rec := folio.readRecFromRedis(redis, id)
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
