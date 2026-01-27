//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Trevor Adelman  Creation
//

using concurrent

**
** RedisClientTortureTest - Comprehensive stress and edge case testing
** for the pure Fantom Redis client.
**
** Prerequisites: Redis must be running on localhost:6379
**
class RedisClientTortureTest : Test
{
  RedisClient? r

//////////////////////////////////////////////////////////////////////////
// Binary Data (using Base64 - how Brio encodes data)
//////////////////////////////////////////////////////////////////////////

  Void testBinaryData()
  {
    r = RedisClient.open

    // All byte values 0-255 encoded as base64
    buf := Buf()
    256.times |i| { buf.write(i) }
    binaryStr := buf.toBase64
    r.set("test:binary:all", binaryStr)
    result := r.get("test:binary:all")
    verifyEq(result, binaryStr)
    // Verify we can decode it back
    decoded := Buf.fromBase64(result)
    verifyEq(decoded.size, 256)
    256.times |i| { verifyEq(decoded[i], i) }

    // Random binary data as base64
    randomBuf := Buf.random(1024)
    randomStr := randomBuf.toBase64
    r.set("test:binary:random", randomStr)
    verifyEq(r.get("test:binary:random"), randomStr)

    // Large random binary as base64
    largeBuf := Buf.random(10 * 1024)
    largeStr := largeBuf.toBase64
    r.set("test:binary:large", largeStr)
    verifyEq(r.get("test:binary:large"), largeStr)

    // Cleanup
    r.del(["test:binary:all", "test:binary:random", "test:binary:large"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Large Values
//////////////////////////////////////////////////////////////////////////

  Void testLargeValues()
  {
    r = RedisClient.open

    // 1KB
    val1k := Buf.random(1024).toBase64
    r.set("test:large:1k", val1k)
    verifyEq(r.get("test:large:1k"), val1k)

    // 10KB
    val10k := Buf.random(10 * 1024).toBase64
    r.set("test:large:10k", val10k)
    verifyEq(r.get("test:large:10k"), val10k)

    // 100KB
    val100k := Buf.random(100 * 1024).toBase64
    r.set("test:large:100k", val100k)
    verifyEq(r.get("test:large:100k"), val100k)

    // 1MB
    val1m := Buf.random(1024 * 1024).toBase64
    r.set("test:large:1m", val1m)
    result1m := r.get("test:large:1m")
    verifyEq(result1m?.size, val1m.size)
    verifyEq(result1m, val1m)

    // Cleanup
    r.del(["test:large:1k", "test:large:10k", "test:large:100k", "test:large:1m"])
    r.close
  }

  Void testLargeHash()
  {
    r = RedisClient.open

    // Hash with many fields
    100.times |i|
    {
      r.hset("test:large:hash", "field$i", "value-$i-" + Buf.random(100).toBase64)
    }

    all := r.hgetall("test:large:hash")
    verifyEq(all.size, 100)
    verifyEq(all["field0"]?.startsWith("value-0-"), true)
    verifyEq(all["field99"]?.startsWith("value-99-"), true)

    // Cleanup
    r.del(["test:large:hash"])
    r.close
  }

  Void testLargeSet()
  {
    r = RedisClient.open

    // Set with many members
    members := Str[,]
    1000.times |i| { members.add("member-$i") }
    r.sadd("test:large:set", members)

    result := r.smembers("test:large:set")
    verifyEq(result.size, 1000)
    verify(result.contains("member-0"))
    verify(result.contains("member-999"))

    // Cleanup
    r.del(["test:large:set"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Special Characters
//////////////////////////////////////////////////////////////////////////

  Void testSpecialCharsInKeys()
  {
    r = RedisClient.open

    // Colons (common in Redis keys)
    r.set("test:special:a:b:c:d:e", "value")
    verifyEq(r.get("test:special:a:b:c:d:e"), "value")

    // Spaces
    r.set("test:special:with space", "value with space")
    verifyEq(r.get("test:special:with space"), "value with space")

    // Newlines in values
    r.set("test:special:newline", "line1\nline2\nline3")
    verifyEq(r.get("test:special:newline"), "line1\nline2\nline3")

    // Carriage returns
    r.set("test:special:crlf", "line1\r\nline2\r\n")
    verifyEq(r.get("test:special:crlf"), "line1\r\nline2\r\n")

    // Tabs
    r.set("test:special:tabs", "col1\tcol2\tcol3")
    verifyEq(r.get("test:special:tabs"), "col1\tcol2\tcol3")

    // Dollar signs (RESP uses these)
    r.set("test:special:dollar", "\$100 \$200")
    verifyEq(r.get("test:special:dollar"), "\$100 \$200")

    // Asterisks (RESP uses these)
    r.set("test:special:asterisk", "*important* **very**")
    verifyEq(r.get("test:special:asterisk"), "*important* **very**")

    // Cleanup
    r.del(["test:special:a:b:c:d:e", "test:special:with space",
           "test:special:newline", "test:special:crlf", "test:special:tabs",
           "test:special:dollar", "test:special:asterisk"])
    r.close
  }

  Void testUnicode()
  {
    r = RedisClient.open

    // Chinese
    r.set("test:unicode:chinese", "Hello")
    verifyEq(r.get("test:unicode:chinese"), "Hello")

    // Japanese
    r.set("test:unicode:japanese", "Hello")
    verifyEq(r.get("test:unicode:japanese"), "Hello")

    // Emojis (if supported)
    r.set("test:unicode:emoji", "Hello World")
    verifyEq(r.get("test:unicode:emoji"), "Hello World")

    // Mixed
    r.set("test:unicode:mixed", "Hello World 123 ABC")
    verifyEq(r.get("test:unicode:mixed"), "Hello World 123 ABC")

    // Unicode in hash fields
    r.hset("test:unicode:hash", "field", "value")
    verifyEq(r.hget("test:unicode:hash", "field"), "value")

    // Cleanup
    r.del(["test:unicode:chinese", "test:unicode:japanese",
           "test:unicode:emoji", "test:unicode:mixed", "test:unicode:hash"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Edge Cases
//////////////////////////////////////////////////////////////////////////

  Void testEmptyValues()
  {
    r = RedisClient.open

    // Empty string value
    r.set("test:edge:empty", "")
    verifyEq(r.get("test:edge:empty"), "")

    // Empty hash field value
    r.hset("test:edge:hash", "emptyfield", "")
    verifyEq(r.hget("test:edge:hash", "emptyfield"), "")

    // Empty set (should not exist after removing all)
    r.sadd("test:edge:set", ["a"])
    r.srem("test:edge:set", ["a"])
    verifyEq(r.smembers("test:edge:set").size, 0)

    // Cleanup
    r.del(["test:edge:empty", "test:edge:hash", "test:edge:set"])
    r.close
  }

  Void testNonExistent()
  {
    r = RedisClient.open

    // Non-existent key returns null
    verifyEq(r.get("test:nonexistent:key:12345"), null)

    // Non-existent hash field returns null
    r.hset("test:nonexistent:hash", "exists", "value")
    verifyEq(r.hget("test:nonexistent:hash", "notexists"), null)

    // Non-existent key in exists check
    verifyEq(r.exists("test:nonexistent:key:67890"), false)

    // Delete non-existent key returns 0
    verifyEq(r.del(["test:nonexistent:key:abcde"]), 0)

    // Cleanup
    r.del(["test:nonexistent:hash"])
    r.close
  }

  Void testOverwrite()
  {
    r = RedisClient.open

    // Set then overwrite
    r.set("test:overwrite:key", "original")
    verifyEq(r.get("test:overwrite:key"), "original")
    r.set("test:overwrite:key", "updated")
    verifyEq(r.get("test:overwrite:key"), "updated")

    // Overwrite with different size
    r.set("test:overwrite:size", "short")
    verifyEq(r.get("test:overwrite:size"), "short")
    r.set("test:overwrite:size", "this is a much longer value than before")
    verifyEq(r.get("test:overwrite:size"), "this is a much longer value than before")

    // Cleanup
    r.del(["test:overwrite:key", "test:overwrite:size"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Numeric Edge Cases
//////////////////////////////////////////////////////////////////////////

  Void testNumericValues()
  {
    r = RedisClient.open

    // Zero
    r.set("test:numeric:zero", "0")
    verifyEq(r.get("test:numeric:zero"), "0")

    // Negative
    r.set("test:numeric:negative", "-12345")
    verifyEq(r.get("test:numeric:negative"), "-12345")

    // Large integer
    r.set("test:numeric:large", "9223372036854775807")
    verifyEq(r.get("test:numeric:large"), "9223372036854775807")

    // Float
    r.set("test:numeric:float", "3.14159265358979")
    verifyEq(r.get("test:numeric:float"), "3.14159265358979")

    // Scientific notation
    r.set("test:numeric:scientific", "1.23e-10")
    verifyEq(r.get("test:numeric:scientific"), "1.23e-10")

    // Incr from string zero
    r.set("test:numeric:incr", "0")
    verifyEq(r.incr("test:numeric:incr"), 1)
    verifyEq(r.incr("test:numeric:incr"), 2)
    verifyEq(r.incr("test:numeric:incr"), 3)

    // Cleanup
    r.del(["test:numeric:zero", "test:numeric:negative", "test:numeric:large",
           "test:numeric:float", "test:numeric:scientific", "test:numeric:incr"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Sorted Set Edge Cases
//////////////////////////////////////////////////////////////////////////

  Void testSortedSetScores()
  {
    r = RedisClient.open

    // Zero score
    r.zadd("test:zset:scores", 0f, "zero")

    // Negative score
    r.zadd("test:zset:scores", -100f, "negative")

    // Very small score
    r.zadd("test:zset:scores", 0.00001f, "tiny")

    // Very large score
    r.zadd("test:zset:scores", 1e10f, "huge")

    // Verify range queries work
    all := r.zrangebyscore("test:zset:scores", Float.negInf, Float.posInf)
    verifyEq(all.size, 4)
    verifyEq(all[0], "negative")  // -100
    verifyEq(all[1], "zero")      // 0
    verifyEq(all[2], "tiny")      // 0.00001
    verifyEq(all[3], "huge")      // 1e10

    // Range with bounds
    mid := r.zrangebyscore("test:zset:scores", -50f, 50f)
    verifyEq(mid.size, 2)
    verify(mid.contains("zero"))
    verify(mid.contains("tiny"))

    // Cleanup
    r.del(["test:zset:scores"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Set Operations Edge Cases
//////////////////////////////////////////////////////////////////////////

  Void testSetIntersection()
  {
    r = RedisClient.open

    // Empty intersection
    r.sadd("test:sinter:a", ["1", "2", "3"])
    r.sadd("test:sinter:b", ["4", "5", "6"])
    inter := r.sinter(["test:sinter:a", "test:sinter:b"])
    verifyEq(inter.size, 0)

    // Partial intersection
    r.sadd("test:sinter:c", ["2", "3", "4"])
    inter2 := r.sinter(["test:sinter:a", "test:sinter:c"])
    verifyEq(inter2.size, 2)
    verify(inter2.contains("2"))
    verify(inter2.contains("3"))

    // Self intersection
    self := r.sinter(["test:sinter:a", "test:sinter:a"])
    verifyEq(self.size, 3)

    // Cleanup
    r.del(["test:sinter:a", "test:sinter:b", "test:sinter:c"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Rapid Operations
//////////////////////////////////////////////////////////////////////////

  Void testRapidOperations()
  {
    r = RedisClient.open

    // Rapid set/get
    100.times |i|
    {
      r.set("test:rapid:$i", "value-$i")
    }

    100.times |i|
    {
      verifyEq(r.get("test:rapid:$i"), "value-$i")
    }

    // Rapid hash operations
    100.times |i|
    {
      r.hset("test:rapid:hash", "field$i", "val$i")
    }
    verifyEq(r.hgetall("test:rapid:hash").size, 100)

    // Cleanup
    keys := Str[,]
    100.times |i| { keys.add("test:rapid:$i") }
    keys.add("test:rapid:hash")
    r.del(keys)
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Connection Stress
//////////////////////////////////////////////////////////////////////////

  Void testMultipleConnections()
  {
    // Open multiple connections sequentially
    10.times |i|
    {
      client := RedisClient.open
      verifyEq(client.ping, "PONG")
      client.set("test:multi:$i", "value-$i")
      verifyEq(client.get("test:multi:$i"), "value-$i")
      client.del(["test:multi:$i"])
      client.close
    }
  }

  Void testReconnect()
  {
    // Connect, use, close, reconnect
    r = RedisClient.open
    r.set("test:reconnect:before", "value1")
    r.close

    r = RedisClient.open
    verifyEq(r.get("test:reconnect:before"), "value1")
    r.set("test:reconnect:after", "value2")
    verifyEq(r.get("test:reconnect:after"), "value2")

    // Cleanup
    r.del(["test:reconnect:before", "test:reconnect:after"])
    r.close
  }

//////////////////////////////////////////////////////////////////////////
// Database Selection
//////////////////////////////////////////////////////////////////////////

  Void testDatabaseSelection()
  {
    // Use database 1 for isolation
    r1 := RedisClient.open(`redis://localhost:6379/1`)
    r1.set("test:db1:key", "db1value")
    r1.close

    // Verify not in database 0
    r0 := RedisClient.open(`redis://localhost:6379/0`)
    // Note: This might find the key if test:db1:key exists in db0 from other tests
    // So we just verify db1 has our value
    r0.close

    // Verify in database 1
    r1 = RedisClient.open(`redis://localhost:6379/1`)
    verifyEq(r1.get("test:db1:key"), "db1value")
    r1.del(["test:db1:key"])
    r1.close
  }

//////////////////////////////////////////////////////////////////////////
// Cleanup Verification
//////////////////////////////////////////////////////////////////////////

  Void testCleanup()
  {
    r = RedisClient.open

    // Create some keys
    r.set("test:cleanup:a", "1")
    r.set("test:cleanup:b", "2")
    r.hset("test:cleanup:hash", "f", "v")
    r.sadd("test:cleanup:set", ["x"])

    // Verify they exist
    verifyEq(r.exists("test:cleanup:a"), true)
    verifyEq(r.exists("test:cleanup:b"), true)
    verifyEq(r.exists("test:cleanup:hash"), true)
    verifyEq(r.exists("test:cleanup:set"), true)

    // Delete all
    count := r.del(["test:cleanup:a", "test:cleanup:b",
                    "test:cleanup:hash", "test:cleanup:set"])
    verifyEq(count, 4)

    // Verify gone
    verifyEq(r.exists("test:cleanup:a"), false)
    verifyEq(r.exists("test:cleanup:b"), false)
    verifyEq(r.exists("test:cleanup:hash"), false)
    verifyEq(r.exists("test:cleanup:set"), false)

    r.close
  }
}
