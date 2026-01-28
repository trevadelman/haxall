//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Trevor Adelman  Creation
//

**
** RedisClientTest tests the pure Fantom Redis client.
**
** Prerequisites: Redis must be running on localhost:6379
**
class RedisClientTest : Test
{
  RedisClient? r

//////////////////////////////////////////////////////////////////////////
// Basics
//////////////////////////////////////////////////////////////////////////

  Void testBasics()
  {
    r = RedisClient.open

    // ping
    verifyPing

    // strings
    r.set("test:foo", "bar")
    verifyEq(r.get("test:foo"), "bar")
    verifyEq(r.get("test:nonexistent"), null)
    verifyEq(r.exists("test:foo"), true)
    verifyEq(r.exists("test:nonexistent"), false)

    // delete
    verifyEq(r.del(["test:foo"]), 1)
    verifyEq(r.get("test:foo"), null)
    verifyEq(r.del(["test:foo"]), 0)

    // incr
    r.set("test:counter", "0")
    verifyEq(r.incr("test:counter"), 1)
    verifyEq(r.incr("test:counter"), 2)
    verifyEq(r.get("test:counter"), "2")
    r.del(["test:counter"])

    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Hash
//////////////////////////////////////////////////////////////////////////

  Void testHash()
  {
    r = RedisClient.open

    // hset/hget
    r.hset("test:hash", "field1", "value1")
    r.hset("test:hash", "field2", "value2")
    verifyEq(r.hget("test:hash", "field1"), "value1")
    verifyEq(r.hget("test:hash", "field2"), "value2")
    verifyEq(r.hget("test:hash", "nonexistent"), null)

    // hgetall
    all := r.hgetall("test:hash")
    verifyEq(all.size, 2)
    verifyEq(all["field1"], "value1")
    verifyEq(all["field2"], "value2")

    // hmset
    r.hmset("test:hash2", ["a":"1", "b":"2", "c":"3"])
    verifyEq(r.hget("test:hash2", "a"), "1")
    verifyEq(r.hget("test:hash2", "b"), "2")
    verifyEq(r.hget("test:hash2", "c"), "3")

    // hdel
    verifyEq(r.hdel("test:hash", "field1"), 1)
    verifyEq(r.hget("test:hash", "field1"), null)
    verifyEq(r.hdel("test:hash", "field1"), 0)

    // cleanup
    r.del(["test:hash", "test:hash2"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Set
//////////////////////////////////////////////////////////////////////////

  Void testSet()
  {
    r = RedisClient.open

    // sadd
    verifyEq(r.sadd("test:set", ["a", "b", "c"]), 3)
    verifyEq(r.sadd("test:set", ["a"]), 0)  // already exists

    // sismember
    verifyEq(r.sismember("test:set", "a"), true)
    verifyEq(r.sismember("test:set", "b"), true)
    verifyEq(r.sismember("test:set", "x"), false)

    // smembers
    members := r.smembers("test:set")
    verifyEq(members.size, 3)
    verify(members.contains("a"))
    verify(members.contains("b"))
    verify(members.contains("c"))

    // srem
    verifyEq(r.srem("test:set", ["a"]), 1)
    verifyEq(r.sismember("test:set", "a"), false)
    verifyEq(r.srem("test:set", ["a"]), 0)

    // sinter
    r.sadd("test:set2", ["b", "c", "d"])
    inter := r.sinter(["test:set", "test:set2"])
    verifyEq(inter.size, 2)
    verify(inter.contains("b"))
    verify(inter.contains("c"))

    // cleanup
    r.del(["test:set", "test:set2"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Sorted Set
//////////////////////////////////////////////////////////////////////////

  Void testSortedSet()
  {
    r = RedisClient.open

    // zadd
    verifyEq(r.zadd("test:zset", 1.0f, "one"), 1)
    verifyEq(r.zadd("test:zset", 2.0f, "two"), 1)
    verifyEq(r.zadd("test:zset", 3.0f, "three"), 1)
    verifyEq(r.zadd("test:zset", 1.0f, "one"), 0)  // already exists

    // zrangebyscore
    range := r.zrangebyscore("test:zset", 0f, 1.5f)
    verifyEq(range.size, 1)
    verifyEq(range[0], "one")

    range = r.zrangebyscore("test:zset", 1.5f, 2.5f)
    verifyEq(range.size, 1)
    verifyEq(range[0], "two")

    range = r.zrangebyscore("test:zset", 0f, 10f)
    verifyEq(range.size, 3)

    range = r.zrangebyscore("test:zset", Float.negInf, Float.posInf)
    verifyEq(range.size, 3)

    // zrem
    verifyEq(r.zrem("test:zset", ["two"]), 1)
    range = r.zrangebyscore("test:zset", 0f, 10f)
    verifyEq(range.size, 2)

    // cleanup
    r.del(["test:zset"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Keys
//////////////////////////////////////////////////////////////////////////

  Void testKeys()
  {
    r = RedisClient.open

    // setup test keys
    r.set("test:key:a", "1")
    r.set("test:key:b", "2")
    r.set("test:key:c", "3")

    // keys pattern match
    keys := r.keys("test:key:*")
    verifyEq(keys.size, 3)
    verify(keys.contains("test:key:a"))
    verify(keys.contains("test:key:b"))
    verify(keys.contains("test:key:c"))

    // cleanup
    r.del(["test:key:a", "test:key:b", "test:key:c"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Transactions
//////////////////////////////////////////////////////////////////////////

  Void testMultiExec()
  {
    r = RedisClient.open

    // Basic transaction
    r.multi
    r.set("test:tx1", "value1")
    r.set("test:tx2", "value2")
    r.incr("test:counter")
    results := r.exec

    // Verify results array contains response for each command
    verifyNotNull(results)
    verifyEq(results.size, 3)
    verifyEq(results[0], "OK")  // SET returns OK
    verifyEq(results[1], "OK")
    verifyEq(results[2], 1)     // INCR returns new value

    // Verify values were set
    verifyEq(r.get("test:tx1"), "value1")
    verifyEq(r.get("test:tx2"), "value2")
    verifyEq(r.get("test:counter"), "1")

    // Cleanup
    r.del(["test:tx1", "test:tx2", "test:counter"])
    r.close
  }

  Void testDiscard()
  {
    r = RedisClient.open

    // Set initial value
    r.set("test:discard", "original")

    // Start transaction but discard
    r.multi
    r.set("test:discard", "changed")
    r.discard

    // Verify original value unchanged
    verifyEq(r.get("test:discard"), "original")

    // Cleanup
    r.del(["test:discard"])
    r.close
  }

  Void testWatchAbort()
  {
    r = RedisClient.open

    // Set initial value
    r.set("test:watch", "initial")

    // Watch the key
    r.watch(["test:watch"])

    // Modify the key (simulates another client)
    r2 := RedisClient.open
    r2.set("test:watch", "modified")
    r2.close

    // Try to execute transaction - should abort
    r.multi
    r.set("test:watch", "transaction")
    results := r.exec

    // exec returns null when WATCH caused abort
    verifyNull(results)

    // Verify the value is from the "other client"
    verifyEq(r.get("test:watch"), "modified")

    // Cleanup
    r.del(["test:watch"])
    r.close
  }

  Void testUnwatch()
  {
    r = RedisClient.open

    // Set initial value
    r.set("test:unwatch", "initial")

    // Watch and then unwatch
    r.watch(["test:unwatch"])
    r.unwatch

    // Modify the key
    r2 := RedisClient.open
    r2.set("test:unwatch", "modified")
    r2.close

    // Transaction should succeed because we unwatched
    r.multi
    r.set("test:unwatch", "transaction")
    results := r.exec

    verifyNotNull(results)
    verifyEq(r.get("test:unwatch"), "transaction")

    // Cleanup
    r.del(["test:unwatch"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Pipeline
//////////////////////////////////////////////////////////////////////////

  Void testBasicPipeline()
  {
    r = RedisClient.open

    // Pipeline multiple SET/GET commands
    results := r.pipeline
    {
      it.set("test:pipe:a", "value-a")
      it.set("test:pipe:b", "value-b")
      it.set("test:pipe:c", "value-c")
      it.get("test:pipe:a")
      it.get("test:pipe:b")
      it.get("test:pipe:c")
    }

    // Verify results array matches command order
    verifyEq(results.size, 6)
    verifyEq(results[0], "OK")  // SET response
    verifyEq(results[1], "OK")
    verifyEq(results[2], "OK")
    verifyEq(results[3], "value-a")  // GET response
    verifyEq(results[4], "value-b")
    verifyEq(results[5], "value-c")

    // Cleanup
    r.del(["test:pipe:a", "test:pipe:b", "test:pipe:c"])
    r.close
  }

  Void testPipelineMixedCommands()
  {
    r = RedisClient.open

    // Pipeline with different command types
    results := r.pipeline
    {
      it.set("test:pipe:str", "hello")
      it.hset("test:pipe:hash", "field", "value")
      it.sadd("test:pipe:set", ["a", "b"])
      it.incr("test:pipe:counter")
      it.get("test:pipe:str")
      it.hget("test:pipe:hash", "field")
    }

    verifyEq(results.size, 6)
    verifyEq(results[0], "OK")      // SET
    verifyEq(results[1], 1)         // HSET returns 1 for new field
    verifyEq(results[2], 2)         // SADD returns count of new members
    verifyEq(results[3], 1)         // INCR returns new value
    verifyEq(results[4], "hello")   // GET
    verifyEq(results[5], "value")   // HGET

    // Cleanup
    r.del(["test:pipe:str", "test:pipe:hash", "test:pipe:set", "test:pipe:counter"])
    r.close
  }

  Void testLargePipeline()
  {
    r = RedisClient.open

    // Pipeline 100 commands
    results := r.pipeline |redis|
    {
      100.times |i|
      {
        redis.set("test:pipe:large:$i", "value-$i")
      }
    }

    verifyEq(results.size, 100)
    results.each |res| { verifyEq(res, "OK") }

    // Verify data was written
    verifyEq(r.get("test:pipe:large:0"), "value-0")
    verifyEq(r.get("test:pipe:large:99"), "value-99")

    // Cleanup with pipeline
    r.pipeline |redis|
    {
      100.times |i|
      {
        redis.del(["test:pipe:large:$i"])
      }
    }

    r.close
  }

  Void testPipelineAfterRegularCommands()
  {
    r = RedisClient.open

    // Regular commands before pipeline
    r.set("test:pipe:before", "before-value")

    // Pipeline
    results := r.pipeline
    {
      it.get("test:pipe:before")
      it.set("test:pipe:during", "during-value")
    }

    verifyEq(results[0], "before-value")
    verifyEq(results[1], "OK")

    // Regular commands after pipeline
    verifyEq(r.get("test:pipe:during"), "during-value")

    // Cleanup
    r.del(["test:pipe:before", "test:pipe:during"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Connection
//////////////////////////////////////////////////////////////////////////

  Void testConnection()
  {
    // test default connection
    r = RedisClient.open
    verifyPing
    r.close

    // test explicit URI
    r = RedisClient.open(`redis://localhost:6379`)
    verifyPing
    r.close

    // test database selection
    r = RedisClient.open(`redis://localhost:6379/1`)
    verifyPing
    r.set("test:db1", "value")
    verifyEq(r.get("test:db1"), "value")
    r.del(["test:db1"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Utils
//////////////////////////////////////////////////////////////////////////

  private Void verifyPing()
  {
    result := r.ping
    verifyEq(result, "PONG")
  }
}
