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
** HxRedisTest tests the Redis-backed Folio implementation.
**
** Prerequisites: Redis must be running on localhost:6379
**
class HxRedisTest : Test
{

//////////////////////////////////////////////////////////////////////////
// Basic CRUD
//////////////////////////////////////////////////////////////////////////

  Void testReadWriteBasic()
  {
    folio := openTestFolio

    // Add a record (id is auto-generated)
    rec := folio.commit(Diff.makeAdd(["dis":"Test Record", "site":Marker.val])).newRec
    id := rec.id
    verifyEq(rec["dis"], "Test Record")
    verifyEq(rec.has("site"), true)
    verifyNotNull(rec["mod"])
    verifyNotNull(id)

    // Read it back
    readRec := folio.readById(id)
    verifyEq(readRec["dis"], "Test Record")
    verifyEq(readRec.has("site"), true)
    verifyEq(readRec.id, id)

    // Update it
    updated := folio.commit(Diff(rec, ["dis":"Updated Record", "newTag":n(123)])).newRec
    verifyEq(updated["dis"], "Updated Record")
    verifyEq(updated["newTag"], n(123))

    // Read updated
    readUpdated := folio.readById(id)
    verifyEq(readUpdated["dis"], "Updated Record")
    verifyEq(readUpdated["newTag"], n(123))

    // Remove it
    folio.commit(Diff(readUpdated, null, Diff.remove))
    verifyEq(folio.readById(id, false), null)

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// ReadAll
//////////////////////////////////////////////////////////////////////////

  Void testReadAll()
  {
    folio := openTestFolio

    // Add multiple records
    3.times |i|
    {
      folio.commit(Diff.makeAdd(["dis":"Record $i", "site":Marker.val, "num":n(i)]))
    }

    // Read all site records
    recs := folio.readAll(Filter("site"))
    verifyEq(recs.size, 3)

    // Read with filter
    recs = folio.readAll(Filter("num == 1"))
    verifyEq(recs.size, 1)
    verifyEq(recs[0]["dis"], "Record 1")

    // Count
    verifyEq(folio.readCount(Filter("site")), 3)
    verifyEq(folio.readCount(Filter("num >= 1")), 2)

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// ReadByIds
//////////////////////////////////////////////////////////////////////////

  Void testReadByIds()
  {
    folio := openTestFolio

    // Add records and capture their ids
    rec1 := folio.commit(Diff.makeAdd(["dis":"One"])).newRec
    rec2 := folio.commit(Diff.makeAdd(["dis":"Two"])).newRec
    rec3 := folio.commit(Diff.makeAdd(["dis":"Three"])).newRec

    // Read by ids
    recs := folio.readByIds([rec1.id, rec3.id])
    verifyEq(recs.size, 2)
    verifyNotNull(recs[0])
    verifyNotNull(recs[1])
    verifyEq(recs[0]["dis"], "One")
    verifyEq(recs[1]["dis"], "Three")

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Version
//////////////////////////////////////////////////////////////////////////

  Void testVersion()
  {
    folio := openTestFolio

    v1 := folio.curVer

    // Commit should increment version
    rec := folio.commit(Diff.makeAdd(["dis":"Test"])).newRec
    v2 := folio.curVer
    verify(v2 > v1)

    // Another commit
    folio.commit(Diff(rec, ["dis":"Updated"]))
    v3 := folio.curVer
    verify(v3 > v2)

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Trash Handling
//////////////////////////////////////////////////////////////////////////

  Void testTrashHandling()
  {
    folio := openTestFolio

    // Create record
    rec := folio.commit(Diff.makeAdd(["dis":"Trash Test"])).newRec
    id := rec.id

    // Mark as trash
    trashed := folio.commit(Diff(rec, ["trash":Marker.val])).newRec
    verifyEq(trashed.has("trash"), true)

    // Normal read should NOT find it
    verifyEq(folio.readById(id, false), null)

    // ReadAll should NOT find it
    recs := folio.readAll(Filter("dis"))
    verify(recs.find |r| { r.id == id } == null)

    // ReadAll with trash option SHOULD find it
    recsWithTrash := folio.readAllList(Filter("dis"), Etc.makeDict(["trash":Marker.val]))
    verify(recsWithTrash.find |r| { r.id == id } != null)

    // ReadCount should NOT count it normally
    verifyEq(folio.readCount(Filter("dis")), 0)

    // ReadCount with trash option SHOULD count it
    verifyEq(folio.readCount(Filter("dis"), Etc.makeDict(["trash":Marker.val])), 1)

    closeTestFolio(folio)
  }

  Void testUntrash()
  {
    folio := openTestFolio

    // Create and trash record
    rec := folio.commit(Diff.makeAdd(["dis":"Untrash Test"])).newRec
    trashed := folio.commit(Diff(rec, ["trash":Marker.val])).newRec
    id := trashed.id

    // Verify it's hidden
    verifyEq(folio.readById(id, false), null)

    // Read with trash option to get the record back
    trashedRec := folio.readAllList(Filter("dis == \"Untrash Test\""), Etc.makeDict(["trash":Marker.val])).first

    // Remove trash flag
    untrashed := folio.commit(Diff(trashedRec, ["trash":Remove.val])).newRec
    verifyEq(untrashed.has("trash"), false)

    // Now should be visible again
    verifyNotNull(folio.readById(id, false))

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Transient Handling
//////////////////////////////////////////////////////////////////////////

  Void testTransientCommit()
  {
    folio := openTestFolio

    v1 := folio.curVer

    // Regular commit increments version
    rec := folio.commit(Diff.makeAdd(["dis":"Regular"])).newRec
    v2 := folio.curVer
    verifyEq(v2, v1 + 1)
    verifyNotNull(rec["mod"])

    // Transient UPDATE does NOT increment version
    // Note: transient cannot be used with add or remove, only updates
    transResult := folio.commit(Diff(rec, ["transientTag":Marker.val], Diff.transient))
    rec = transResult.newRec  // Refresh rec with result
    v3 := folio.curVer
    verifyEq(v3, v2)  // Version unchanged

    // Verify the transient tag was applied
    verifyEq(rec.has("transientTag"), true)

    // Regular update increments version - use refreshed rec
    rec = folio.commit(Diff(rec, ["normalTag":Marker.val])).newRec
    v4 := folio.curVer
    verifyEq(v4, v3 + 1)

    // Another transient update
    rec = folio.commit(Diff(rec, ["anotherTransient":Marker.val], Diff.transient)).newRec
    v5 := folio.curVer
    verifyEq(v5, v4)  // Version still unchanged

    // All tags should be present
    verifyEq(rec.has("transientTag"), true)
    verifyEq(rec.has("normalTag"), true)
    verifyEq(rec.has("anotherTransient"), true)

    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Index Management
//////////////////////////////////////////////////////////////////////////

  Void testTagIndexes()
  {
    folio := openTestFolio

    // Create records with various tags
    rec1 := folio.commit(Diff.makeAdd(["dis":"Site 1", "site":Marker.val])).newRec
    rec2 := folio.commit(Diff.makeAdd(["dis":"Site 2", "site":Marker.val, "geoCity":"Boston"])).newRec
    rec3 := folio.commit(Diff.makeAdd(["dis":"Equip 1", "equip":Marker.val])).newRec

    // Verify idx:tag:site has both site records
    redis := RedisClient.open(`redis://localhost:6379/15`)
    siteIds := redis.smembers("idx:tag:site")
    verifyEq(siteIds.size, 2)
    verify(siteIds.contains(rec1.id.toStr))
    verify(siteIds.contains(rec2.id.toStr))

    // Verify idx:tag:equip has equip record
    equipIds := redis.smembers("idx:tag:equip")
    verifyEq(equipIds.size, 1)
    verify(equipIds.contains(rec3.id.toStr))

    // Verify idx:tag:geoCity has only rec2
    geoCityIds := redis.smembers("idx:tag:geoCity")
    verifyEq(geoCityIds.size, 1)
    verify(geoCityIds.contains(rec2.id.toStr))

    // Update rec1 to add geoCity
    rec1 = folio.commit(Diff(rec1, ["geoCity":"NYC"])).newRec
    geoCityIds = redis.smembers("idx:tag:geoCity")
    verifyEq(geoCityIds.size, 2)

    // Remove site from rec1
    rec1 = folio.commit(Diff(rec1, ["site":Remove.val])).newRec
    siteIds = redis.smembers("idx:tag:site")
    verifyEq(siteIds.size, 1)
    verify(!siteIds.contains(rec1.id.toStr))
    verify(siteIds.contains(rec2.id.toStr))

    // Delete rec2 - should remove from all indexes
    folio.commit(Diff(rec2, null, Diff.remove))
    siteIds = redis.smembers("idx:tag:site")
    verifyEq(siteIds.size, 0)
    geoCityIds = redis.smembers("idx:tag:geoCity")
    verifyEq(geoCityIds.size, 1)  // rec1 still has geoCity

    redis.close
    closeTestFolio(folio)
  }

//////////////////////////////////////////////////////////////////////////
// Error Cases
//////////////////////////////////////////////////////////////////////////

  Void testConcurrentChangeErr()
  {
    folio := openTestFolio

    // Add record
    rec := folio.commit(Diff.makeAdd(["dis":"Test"])).newRec

    // Simulate stale record (wrong mod timestamp)
    staleRec := Etc.dictSet(rec, "mod", DateTime.now - 1hr)

    // Should throw ConcurrentChangeErr
    verifyErr(ConcurrentChangeErr#) { folio.commit(Diff(staleRec, ["dis":"Bad Update"])) }

    // Original should be unchanged
    verifyEq(folio.readById(rec.id)["dis"], "Test")

    closeTestFolio(folio)
  }

  Void testAddDuplicate()
  {
    folio := openTestFolio

    // Add record - get the generated ID
    rec := folio.commit(Diff.makeAdd(["dis":"First"])).newRec
    id := rec.id

    // Folio auto-generates unique IDs, so duplicates are not possible via makeAdd
    // This test just verifies that sequential adds work
    rec2 := folio.commit(Diff.makeAdd(["dis":"Second"])).newRec
    verifyNotEq(rec2.id, id)

    closeTestFolio(folio)
  }

  Void testRemoveNonExistent()
  {
    folio := openTestFolio

    // Try to remove non-existent record
    fakeId := Ref.gen
    fakeRec := Etc.makeDict(["id":fakeId, "mod":DateTime.now])
    verifyErr(CommitErr#) { folio.commit(Diff(fakeRec, null, Diff.remove)) }

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
    dir := Env.cur.tempDir + `hxRedisTest/`
    dir.create

    // Open folio
    config := FolioConfig
    {
      it.name = "test"
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

  private static Number n(Int val) { Number.makeInt(val) }
}
