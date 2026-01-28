//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   28 Jan 2026  Trevor Adelman  Creation
//

using concurrent
using xeto
using haystack
using folio

**
** HxRedisHis is the hxRedis implementation of FolioHis.
**
** History data is stored in Redis Sorted Sets:
**   - Key: his:{recId}
**   - Score: timestamp in milliseconds (enables time range queries)
**   - Value: Trio-encoded HisItem
**
** This design leverages Redis's efficient sorted set operations:
**   - ZADD for writes (O(log N))
**   - ZRANGEBYSCORE for time-range queries (O(log N + M))
**   - ZREMRANGEBYSCORE for clearing ranges (O(log N + M))
**
@NoDoc
const class HxRedisHis : FolioHis
{

//////////////////////////////////////////////////////////////////////////
// Construction
//////////////////////////////////////////////////////////////////////////

  new make(HxRedis folio)
  {
    this.folio = folio
  }

  private const HxRedis folio

  ** Logger
  private static const Log log := Log.get("hxRedis")

//////////////////////////////////////////////////////////////////////////
// FolioHis
//////////////////////////////////////////////////////////////////////////

  **
  ** Read the history items stored for given record id.
  **
  ** If span is null then all items are read, otherwise the span's
  ** inclusive start/exclusive end are used. Per SkySpark behavior,
  ** we always include the previous item before span and next two
  ** items after the span.
  **
  ** Options:
  **   - 'limit': caps total number of items read
  **   - 'clipFuture': clip any data after current time
  **
  override Void read(Ref id, Span? span, Dict? opts, |HisItem| f)
  {
    if (opts == null) opts = Etc.dict0
    limit := (opts["limit"] as Number)?.toInt ?: Int.maxVal
    clipFuture := opts.has("clipFuture")
    now := DateTime.now

    // Read record from cache directly (includes trashed records for proper error)
    rec := folio.map.get(folio.internRef(id)) as Dict
    if (rec == null) throw UnknownRecErr(id.toStr)
    checkHisConfig(rec)

    // Get record's current tz and unit for timestamp/value conversion
    tz := TimeZone.fromStr(rec["tz"] as Str ?: "UTC")
    unitStr := rec["unit"] as Str
    Unit? unit := null
    if (unitStr != null) unit = Number.loadUnit(unitStr, false)

    // Get history from Redis using direct connection
    // (HxRedisHis runs on any thread, not the Actor thread)
    key := hisKey(id)
    redis := RedisClient.open(folio.redisUri)
    try
    {
      // Query all items from Redis (we'll filter in memory for span logic)
      allEncoded := redis.zrangebyscore(key, Float.negInf, Float.posInf)

      // Decode all items, converting to record's current tz and applying unit
      allItems := HisItem[,]
      allItems.capacity = allEncoded.size
      allEncoded.each |encoded|
      {
        item := decodeHisItem(encoded)
        if (item != null)
        {
          // Convert timestamp to record's tz
          ts := item.ts.toTimeZone(tz)
          // Apply unit if record has unit and value is Number
          val := item.val
          if (unit != null && val is Number)
          {
            num := val as Number
            if (num.unit == null)
              val = Number(num.toFloat, unit)
          }
          allItems.add(HisItem(ts, val))
        }
      }

      // Apply span logic if provided
      if (span == null)
      {
        // No span - return all items (with limit and clipFuture)
        count := 0
        allItems.each |item|
        {
          if (count >= limit) return
          if (clipFuture && item.ts > now) return
          f(item)
          count++
        }

        // Update hisStart/hisEnd/hisSize in current record's tz
        // This handles the case where tz tag changed since last write
        if (!allItems.isEmpty)
          updateHisTransientTags(id, rec, allItems)
      }
      else
      {
        // Span query - implement SkySpark's prev/next behavior
        HisItem? prev := null
        next := 0
        count := 0

        allItems.each |item|
        {
          if (count >= limit) return
          if (clipFuture && item.ts > now) return

          if (item.ts < span.start)
          {
            // Track previous item before span
            prev = item
          }
          else if (item.ts >= span.end)
          {
            // Include next two items after span
            if (next < 2)
            {
              f(item)
              count++
              next++
            }
          }
          else
          {
            // Item is within span
            if (prev != null)
            {
              f(prev)
              count++
              prev = null
            }
            if (count < limit)
            {
              f(item)
              count++
            }
          }
        }
      }
    }
    finally
    {
      redis.close
    }
  }

  **
  ** Write history items to the given record id.
  **
  ** Items are validated and normalized using FolioUtil.hisWriteCheck.
  ** ZADD overwrites existing timestamps automatically.
  **
  ** Options:
  **   - 'clear': Span for existing items to clear
  **   - 'clearAll': marker to remove all existing items
  **
  override FolioFuture write(Ref id, HisItem[] items, Dict? opts := null)
  {
    if (opts == null) opts = Etc.dict0

    // Short circuit if no items and no clear options
    if (items.isEmpty && !opts.has("clear") && !opts.has("clearAll"))
      return FolioFuture(HisWriteFolioRes.empty)

    // Read record from cache directly (includes trashed records for proper error)
    rec := folio.map.get(folio.internRef(id)) as Dict
    if (rec == null) throw UnknownRecErr(id.toStr)

    // Validate using existing FolioUtil - this handles all the edge cases (including trash check)
    validatedItems := items.isEmpty ? items : FolioUtil.hisWriteCheck(rec, items, opts)

    // Get history key and open direct connection
    // (HxRedisHis runs on any thread, not the Actor thread)
    key := hisKey(id)
    redis := RedisClient.open(folio.redisUri)
    writeCount := 0
    HisItem? firstItem := null
    HisItem? lastItem := null
    try
    {
      // Handle clear options first
      if (opts.has("clearAll"))
      {
        redis.del([key])
        log.debug("Cleared all history for $id")
      }
      else
      {
        clearSpan := opts["clear"] as Span
        if (clearSpan != null)
        {
          minScore := clearSpan.start.toJava.toFloat
          maxScore := (clearSpan.end.toJava - 1).toFloat  // exclusive end
          cleared := redis.zremrangebyscore(key, minScore, maxScore)
          log.debug("Cleared $cleared history items in span for $id")
        }
      }

      // Write new items
      validatedItems.each |item|
      {
        score := item.ts.toJava.toFloat
        if (item.val === Remove.val)
        {
          // Remove this specific timestamp
          redis.zremrangebyscore(key, score, score)
        }
        else
        {
          // Add/overwrite item
          encoded := encodeHisItem(item)
          redis.zadd(key, score, encoded)
          writeCount++
        }
      }

      log.debug("Wrote $writeCount history items for $id")

      // Read back all items to update transient tags
      allEncoded := redis.zrangebyscore(key, Float.negInf, Float.posInf)
      if (!allEncoded.isEmpty)
      {
        // Decode first and last items for hisStart/hisEnd
        firstItem = decodeHisItem(allEncoded.first)
        lastItem = decodeHisItem(allEncoded.last)
        hisSize := allEncoded.size

        // Update record directly in cache (hisSize/hisStart/hisEnd are "never" tags)
        tz := TimeZone.fromStr(rec["tz"] as Str ?: "UTC")
        tags := Str:Obj[:]
        rec.each |v, n| { tags[n] = v }
        tags["hisSize"] = Number(hisSize)
        if (firstItem != null)
        {
          tags["hisStart"] = firstItem.ts.toTimeZone(tz)
          tags["hisStartVal"] = firstItem.val
        }
        if (lastItem != null)
        {
          tags["hisEnd"] = lastItem.ts.toTimeZone(tz)
          tags["hisEndVal"] = lastItem.val
        }

        // Replace record in cache directly (bypass Diff for "never" tags)
        newRec := Etc.makeDict(tags)
        newRec.id.disVal = rec.id.disVal
        folio.map.set(folio.internRef(id), newRec)
      }
    }
    finally
    {
      redis.close
    }

    // Build result dict with count and span
    Dict result := Etc.dict1("count", Number(writeCount))
    if (writeCount > 0 && firstItem != null && lastItem != null)
      result = Etc.makeDict(["count": Number(writeCount), "span": Span(firstItem.ts, lastItem.ts)])

    // Fire postHisWrite hook if configured
    hooks := folio.hooks
    // Get context info from current context if available
    cxInfo := FolioContext.curFolio(false)?.commitInfo
    hooks.postHisWrite(HxRedisHisEvent(rec, result, cxInfo))

    return FolioFuture(HisWriteFolioRes(result))
  }

//////////////////////////////////////////////////////////////////////////
// Config Checks
//////////////////////////////////////////////////////////////////////////

  **
  ** Check that record is properly configured for history operations.
  ** Throws HisConfigErr if not configured correctly.
  **
  private Void checkHisConfig(Dict rec)
  {
    if (rec["point"] !== Marker.val) throw HisConfigErr(rec, "Rec missing 'point' tag")
    if (rec["his"] !== Marker.val) throw HisConfigErr(rec, "Rec missing 'his' tag")
    if (rec.has("aux")) throw HisConfigErr(rec, "Rec marked as 'aux'")
    if (rec.has("trash")) throw HisConfigErr(rec, "Rec marked as 'trash'")
  }

  **
  ** Update history transient tags (hisSize, hisStart, hisEnd) in the record's current timezone.
  ** This is called on full reads (span==null) to handle tz changes since last write.
  **
  private Void updateHisTransientTags(Ref id, Dict rec, HisItem[] allItems)
  {
    tz := TimeZone.fromStr(rec["tz"] as Str ?: "UTC")

    // Build new record with updated transient tags
    tags := Str:Obj[:]
    rec.each |v, n| { tags[n] = v }
    tags["hisSize"] = Number(allItems.size)
    tags["hisStart"] = allItems.first.ts.toTimeZone(tz)
    tags["hisStartVal"] = allItems.first.val
    tags["hisEnd"] = allItems.last.ts.toTimeZone(tz)
    tags["hisEndVal"] = allItems.last.val

    // Replace record in cache
    newRec := Etc.makeDict(tags)
    newRec.id.disVal = rec.id.disVal
    folio.map.set(folio.internRef(id), newRec)
  }

//////////////////////////////////////////////////////////////////////////
// Encoding
//////////////////////////////////////////////////////////////////////////

  **
  ** Get Redis key for history data.
  **
  private Str hisKey(Ref id)
  {
    "his:${id}"
  }

  **
  ** Encode a HisItem to a string for Redis storage.
  ** Format: Trio-encoded Dict with ts and val tags.
  **
  private Str encodeHisItem(HisItem item)
  {
    // Use Trio format for simplicity and compatibility
    buf := StrBuf()
    TrioWriter(buf.out).writeDict(Etc.dict2("ts", item.ts, "val", item.val))
    return buf.toStr
  }

  **
  ** Decode a HisItem from Redis stored string.
  **
  private HisItem? decodeHisItem(Str encoded)
  {
    try
    {
      dict := TrioReader(encoded.in).readDict
      ts := dict["ts"] as DateTime
      val := dict["val"]
      if (ts == null || val == null) return null
      return HisItem(ts, val)
    }
    catch (Err e)
    {
      log.warn("Failed to decode history item: $e.msg")
      return null
    }
  }
}

**************************************************************************
** HxRedisHisEvent
**************************************************************************

**
** HxRedisHisEvent is the FolioHisEvent implementation for hxRedis
**
@NoDoc
internal class HxRedisHisEvent : FolioHisEvent
{
  new make(Dict rec, Dict result, Obj? cxInfo)
  {
    this.recRef = rec
    this.resultRef = result
    this.cxInfoRef = cxInfo
  }

  override Dict rec() { recRef }
  private const Dict recRef

  override Dict result() { resultRef }
  private const Dict resultRef

  override Obj? cxInfo() { cxInfoRef }
  private const Obj? cxInfoRef
}
