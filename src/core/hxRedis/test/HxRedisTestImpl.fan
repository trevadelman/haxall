//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Trevor Adelman  Creation
//

using concurrent
using haystack
using xeto
using folio

**
** HxRedisTestImpl implements the pluggable test framework for HxRedis.
**
** This allows running the standard AbstractFolioTest suite against Redis.
**
class HxRedisTestImpl : FolioTestImpl
{
  override Str name() { "hxRedis" }

  ** Track if this is first open for this test
  private Bool needsFlush := true

  override Folio open(FolioConfig config)
  {
    // Flush only on first open per test, not on reopens
    if (needsFlush)
    {
      try
      {
        redis := RedisClient.open(`redis://localhost:6379/15`)
        redis.flushdb
        redis.close
      }
      catch (Err e) {}
      needsFlush = false
    }

    // Build opts with Redis URI pointing to test database
    optsMap := Str:Obj[:]
    config.opts.each |v, n| { optsMap[n] = v }
    optsMap["redisUri"] = `redis://localhost:6379/15`

    // Create config with all original settings plus Redis URI
    testConfig := FolioConfig
    {
      it.name = config.name
      it.dir = config.dir
      it.pool = config.pool
      it.idPrefix = config.idPrefix
      it.log = config.log
      it.opts = Etc.makeDict(optsMap)
    }

    return HxRedis.open(testConfig)
  }

  override Void teardown()
  {
    // Reset flush flag for next test
    needsFlush = true
    // Flush Redis test database after tests
    try
    {
      redis := RedisClient.open(`redis://localhost:6379/15`)
      redis.flushdb
      redis.close
    }
    catch (Err e) {}
  }

  override Bool supportsTransient() { true }
  override Bool supportsHis() { true }  // History API now implemented via HxRedisHis
  override Bool supportsFolioX() { false }
  override Bool supportsIdPrefixRename() { false }
}
