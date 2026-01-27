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
** HxRedisTortureTest tests the Redis Folio implementation at scale.
**
** These tests verify:
**   - Large numbers of records (1000+)
**   - Large record payloads (many tags, big strings)
**   - Rapid sequential operations
**   - Filter queries over large datasets
**   - Bulk operations
**
** Prerequisites: Redis must be running on localhost:6379
**
class HxRedisTortureTest : Test
{

//////////////////////////////////////////////////////////////////////////
// Bulk Records
//////////////////////////////////////////////////////////////////////////

  Void testBulkInsert()
  {
    folio := openTestFolio
    count := 1000

    // Insert 1000 records
    ids := Ref[,]
    count.times |i|
    {
      rec := folio.commit(Diff.makeAdd([
        "dis":"Record $i",
        "site":Marker.val,
        "num":Number.makeInt(i),
        "group":Number.makeInt(i / 100)  // 10 groups of 100
      ])).newRec
      ids.add(rec.id)
    }

    // Verify count
    verifyEq(ids.size, count)

    // Verify all can be read back
    recs := folio.readAll(Filter("site"))
    verifyEq(recs.size, count)

    // Verify random access
    10.times
    {
      idx := Int.random(0..<count)
      rec := folio.readById(ids[idx])
      verifyNotNull(rec)
      verifyEq(rec["dis"], "Record $idx")
    }

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Large Records
//////////////////////////////////////////////////////////////////////////

  Void testLargeRecordPayload()
  {
    folio := openTestFolio

    // Create a record with many tags
    tags := Str:Obj["dis":"Large Record", "site":Marker.val]
    100.times |i|
    {
      tags["tag$i"] = "value $i"
    }

    rec := folio.commit(Diff.makeAdd(tags)).newRec
    verifyEq(rec["dis"], "Large Record")
    verifyEq(rec["tag50"], "value 50")
    verifyEq(rec["tag99"], "value 99")

    // Read it back
    readRec := folio.readById(rec.id)
    verifyEq(readRec["dis"], "Large Record")
    verifyEq(readRec["tag50"], "value 50")

    // Update with more tags
    updateTags := Str:Obj[:]
    50.times |i|
    {
      updateTags["extra$i"] = "extra value $i"
    }
    updated := folio.commit(Diff(readRec, updateTags)).newRec
    verifyEq(updated["extra25"], "extra value 25")

    closeTestFolio(folio)
  }

  Void testLargeStringValues()
  {
    folio := openTestFolio

    // 10KB string
    bigStr := StrBuf()
    1000.times { bigStr.add("0123456789") }
    val10k := bigStr.toStr

    rec := folio.commit(Diff.makeAdd([
      "dis":"Big String Record",
      "bigData":val10k
    ])).newRec

    readRec := folio.readById(rec.id)
    verifyEq(readRec["bigData"], val10k)
    verifyEq((readRec["bigData"] as Str).size, 10000)

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Rapid Operations
//////////////////////////////////////////////////////////////////////////

  Void testRapidCommits()
  {
    folio := openTestFolio
    count := 100

    // Rapid add
    ids := Ref[,]
    count.times |i|
    {
      rec := folio.commit(Diff.makeAdd(["dis":"Rapid $i"])).newRec
      ids.add(rec.id)
    }
    verifyEq(ids.size, count)

    // Rapid update
    ids.each |id, i|
    {
      rec := folio.readById(id)
      folio.commit(Diff(rec, ["updated":Marker.val, "seq":Number.makeInt(i)]))
    }

    // Verify all updated
    recs := folio.readAll(Filter("updated"))
    verifyEq(recs.size, count)

    // Rapid delete (first 50)
    ids[0..<50].each |id|
    {
      rec := folio.readById(id)
      folio.commit(Diff(rec, null, Diff.remove))
    }

    // Verify remaining
    remaining := folio.readCount(Filter("updated"))
    verifyEq(remaining, 50)

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Filter Queries at Scale
//////////////////////////////////////////////////////////////////////////

  Void testFilterQueriesAtScale()
  {
    folio := openTestFolio

    // Insert records with varied tags
    500.times |i|
    {
      tags := Str:Obj["dis":"Filter Test $i"]
      if (i % 2 == 0) tags["even"] = Marker.val
      if (i % 3 == 0) tags["divisibleBy3"] = Marker.val
      if (i % 5 == 0) tags["divisibleBy5"] = Marker.val
      if (i < 100) tags["firstHundred"] = Marker.val
      tags["num"] = Number.makeInt(i)
      folio.commit(Diff.makeAdd(tags))
    }

    // Test various filters
    verifyEq(folio.readCount(Filter("even")), 250)
    verifyEq(folio.readCount(Filter("divisibleBy3")), 167)  // 0, 3, 6, ... 498
    verifyEq(folio.readCount(Filter("divisibleBy5")), 100)
    verifyEq(folio.readCount(Filter("firstHundred")), 100)

    // Compound filters
    verifyEq(folio.readCount(Filter("even and divisibleBy3")), 84)  // divisible by 6
    verifyEq(folio.readCount(Filter("even and divisibleBy5")), 50)  // divisible by 10
    verifyEq(folio.readCount(Filter("divisibleBy3 and divisibleBy5")), 34)  // divisible by 15

    // Numeric comparisons
    verifyEq(folio.readCount(Filter("num < 100")), 100)
    verifyEq(folio.readCount(Filter("num >= 400")), 100)
    verifyEq(folio.readCount(Filter("num >= 200 and num < 300")), 100)

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// ReadByIds at Scale
//////////////////////////////////////////////////////////////////////////

  Void testReadByIdsAtScale()
  {
    folio := openTestFolio

    // Insert 200 records
    ids := Ref[,]
    200.times |i|
    {
      rec := folio.commit(Diff.makeAdd(["dis":"Batch $i", "idx":Number.makeInt(i)])).newRec
      ids.add(rec.id)
    }

    // Read all at once
    recs := folio.readByIds(ids)
    verifyEq(recs.size, 200)
    recs.each |rec, i|
    {
      verifyNotNull(rec)
      verifyEq(rec["dis"], "Batch $i")
    }

    // Read subset
    subset := ids[50..<100]
    subRecs := folio.readByIds(subset)
    verifyEq(subRecs.size, 50)
    subRecs.each |rec, i|
    {
      verifyNotNull(rec)
      verifyEq(rec["dis"], "Batch ${i + 50}")
    }

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Version Stress
//////////////////////////////////////////////////////////////////////////

  Void testVersionStress()
  {
    folio := openTestFolio

    v0 := folio.curVer

    // 50 commits should increment version 50 times
    50.times |i|
    {
      folio.commit(Diff.makeAdd(["dis":"Version Test $i"]))
    }

    v50 := folio.curVer
    verifyEq(v50, v0 + 50)

    // Updates also increment
    recs := folio.readAll(Filter("dis"))
    10.times |i|
    {
      folio.commit(Diff(recs[i], ["updated":Marker.val]))
    }

    v60 := folio.curVer
    verifyEq(v60, v50 + 10)

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Utils
//////////////////////////////////////////////////////////////////////////

  private HxRedis openTestFolio()
  {
    // Flush Redis test database
    redis := RedisClient.open(`redis://localhost:6379/15`)
    redis.flushdb
    redis.close

    // Create temp dir for test
    dir := Env.cur.tempDir + `hxRedisTortureTest/`
    dir.create

    // Open folio
    config := FolioConfig
    {
      it.name = "torture"
      it.dir = dir
      it.opts = Etc.makeDict(["redisUri": `redis://localhost:6379/15`])
    }
    return HxRedis.open(config)
  }

  private Void closeTestFolio(HxRedis folio)
  {
    folio.close

    // Cleanup Redis
    redis := RedisClient.open(`redis://localhost:6379/15`)
    redis.flushdb
    redis.close
  }
}
