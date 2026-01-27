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
