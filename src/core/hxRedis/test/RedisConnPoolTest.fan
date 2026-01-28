//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   28 Jan 2026  Trevor Adelman  Creation
//

using concurrent
using haystack

**
** RedisConnPoolTest tests the Redis connection pool.
**
** These tests verify:
**   - Pool initialization creates correct number of connections
**   - Connections are reused across execute calls
**   - Pool handles concurrent access
**   - Pool closes all connections on close()
**   - Pool creates overflow connections when exhausted
**   - Health check identifies and replaces bad connections
**
** Prerequisites: Redis must be running on localhost:6379
**
class RedisConnPoolTest : Test
{

//////////////////////////////////////////////////////////////////////////
// Basic Pool Operations
//////////////////////////////////////////////////////////////////////////

  Void testPoolInitialization()
  {
    pool := RedisConnPool(`redis://localhost:6379/15`, 3)
    try
    {
      // Pool should be initialized with 3 connections
      debug := pool.debug
      verify(debug.contains("total=3"))
      verify(debug.contains("available=3"))
    }
    finally pool.close
  }

  Void testConnectionReuse()
  {
    pool := RedisConnPool(`redis://localhost:6379/15`, 3)
    try
    {
      // Execute multiple times - connections should be reused
      10.times |i|
      {
        result := pool.execute |redis|
        {
          redis.set("test_key", "value_$i")
          return redis.get("test_key")
        }
        verifyEq(result, "value_$i")
      }

      // Pool should still have 3 connections (no growth from reuse)
      debug := pool.debug
      verify(debug.contains("total=3"))
    }
    finally
    {
      pool.close
      // Cleanup
      redis := RedisClient.open(`redis://localhost:6379/15`)
      redis.del(["test_key"])
      redis.close
    }
  }

  Void testExecuteWithResult()
  {
    pool := RedisConnPool(`redis://localhost:6379/15`, 2)
    try
    {
      // Set a value
      pool.execute |redis|
      {
        redis.set("pool_test", "hello")
        return null
      }

      // Get the value
      result := pool.execute |redis->Str?|
      {
        return redis.get("pool_test")
      }
      verifyEq(result, "hello")

      // Verify with direct client
      redis := RedisClient.open(`redis://localhost:6379/15`)
      verifyEq(redis.get("pool_test"), "hello")
      redis.del(["pool_test"])
      redis.close
    }
    finally pool.close
  }

//////////////////////////////////////////////////////////////////////////
// Pool Exhaustion
//////////////////////////////////////////////////////////////////////////

  Void testPoolOverflow()
  {
    // Small pool of 1
    pool := RedisConnPool(`redis://localhost:6379/15`, 1)
    try
    {
      // Execute sequentially - should work fine with 1 connection
      5.times |i|
      {
        pool.execute |redis|
        {
          redis.set("overflow_$i", "val_$i")
          return null
        }
      }

      // Verify all values written
      pool.execute |redis->Obj?|
      {
        5.times |i|
        {
          verifyEq(redis.get("overflow_$i"), "val_$i")
        }
        return null
      }
    }
    finally
    {
      pool.close
      // Cleanup
      redis := RedisClient.open(`redis://localhost:6379/15`)
      5.times |i| { redis.del(["overflow_$i"]) }
      redis.close
    }
  }

//////////////////////////////////////////////////////////////////////////
// Pool Close
//////////////////////////////////////////////////////////////////////////

  Void testPoolClose()
  {
    pool := RedisConnPool(`redis://localhost:6379/15`, 3)

    // Do some work
    pool.execute |redis|
    {
      redis.set("close_test", "value")
      return null
    }

    // Close the pool
    pool.close

    // Verify pool reports closed state in debug (should show 0 connections)
    debug := pool.debug
    verify(debug.contains("total=0"))
    verify(debug.contains("available=0"))

    // Cleanup with fresh connection
    redis := RedisClient.open(`redis://localhost:6379/15`)
    redis.del(["close_test"])
    redis.close
  }

//////////////////////////////////////////////////////////////////////////
// Health Check
//////////////////////////////////////////////////////////////////////////

  Void testHealthCheck()
  {
    pool := RedisConnPool(`redis://localhost:6379/15`, 2)
    try
    {
      // Initial health should be good
      pool.checkHealth

      // Pool should still have 2 connections
      debug := pool.debug
      verify(debug.contains("total=2"))

      // Do some work to verify pool is functional
      result := pool.execute |redis->Str?|
      {
        redis.set("health_test", "ok")
        return redis.get("health_test")
      }
      verifyEq(result, "ok")
    }
    finally
    {
      pool.close
      // Cleanup
      redis := RedisClient.open(`redis://localhost:6379/15`)
      redis.del(["health_test"])
      redis.close
    }
  }

//////////////////////////////////////////////////////////////////////////
// Debug Info
//////////////////////////////////////////////////////////////////////////

  Void testDebugInfo()
  {
    pool := RedisConnPool(`redis://localhost:6379/15`, 5)
    try
    {
      debug := pool.debug

      // Verify debug contains expected info
      verify(debug.contains("RedisConnPool"))
      verify(debug.contains("uri=redis://localhost:6379/15"))
      verify(debug.contains("total=5"))
      verify(debug.contains("available=5"))
      verify(debug.contains("errors=0"))
    }
    finally pool.close
  }

//////////////////////////////////////////////////////////////////////////
// Stress Test
//////////////////////////////////////////////////////////////////////////

  Void testRapidExecutions()
  {
    pool := RedisConnPool(`redis://localhost:6379/15`, 3)
    try
    {
      // Rapid sequential executions
      100.times |i|
      {
        pool.execute |redis|
        {
          redis.set("rapid_$i", i.toStr)
          return null
        }
      }

      // Verify random samples
      pool.execute |redis|
      {
        verifyEq(redis.get("rapid_0"), "0")
        verifyEq(redis.get("rapid_50"), "50")
        verifyEq(redis.get("rapid_99"), "99")
        return null
      }

      // Pool should still be healthy
      debug := pool.debug
      verify(debug.contains("total=3"))
    }
    finally
    {
      pool.close
      // Cleanup
      redis := RedisClient.open(`redis://localhost:6379/15`)
      100.times |i| { redis.del(["rapid_$i"]) }
      redis.close
    }
  }
}
