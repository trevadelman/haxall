//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Creation
//

using concurrent
using haystack
using folio
using xeto

**
** HxRedisBenchmark - Benchmark HxRedis performance
**
** Run with: fan hxRedis::HxRedisBenchmark
**
class HxRedisBenchmark
{
  static Void main()
  {
    echo("=" * 60)
    echo("HxRedis Fantom Benchmark")
    echo("=" * 60)

    benchmark := HxRedisBenchmark()
    benchmark.run
  }

  Void run()
  {
    // Part 1: Raw Redis Client benchmarks
    runRedisClientBenchmarks

    // Part 2: HxRedis Folio benchmarks
    setupFolio
    populateData

    echo("\n" + "=" * 60)
    echo("PART 2: HxRedis FOLIO BENCHMARKS (" + iterations + " iterations each)")
    echo("=" * 60)

    results := Str:Float[:]
    results["read_all"] = benchmarkReadAll
    results["read_sites"] = benchmarkReadSites
    results["read_equips"] = benchmarkReadEquips
    results["read_points"] = benchmarkReadPoints
    results["count_all"] = benchmarkCountAll

    // Print results
    printResults(results)

    // Cleanup
    folio.close
    echo("\nFolio closed")
  }

  private Void runRedisClientBenchmarks()
  {
    echo("\n" + "=" * 60)
    echo("PART 1: RAW REDIS CLIENT BENCHMARKS (" + iterations + " iterations each)")
    echo("=" * 60)

    redis := RedisClient.open(`redis://localhost:6379/15`)
    redis.flushdb

    // Populate test data
    echo("\nPopulating Redis test data...")
    start := Duration.now
    100.times |i| { redis.set("key:$i", "value $i") }
    100.times |i| { redis.hset("hash:test", "field$i", "value $i") }
    redis.sadd("set:test", (0..<100).map |i| { "member$i" })
    elapsed := Duration.now - start
    echo("  Populated in " + elapsed.toMillis + "ms")

    // Benchmark GET (benchmarkRedis returns microseconds)
    echo("\nBenchmarking Redis operations...")
    getTime := benchmarkRedis(redis) |->| { redis.get("key:50") }
    echo("  GET: " + (getTime / 1000f).toLocale("0.000") + "ms (" + getTime.toLocale("0") + " us)")

    // Benchmark SET
    setTime := benchmarkRedis(redis) |->| { redis.set("key:test", "test value") }
    echo("  SET: " + (setTime / 1000f).toLocale("0.000") + "ms (" + setTime.toLocale("0") + " us)")

    // Benchmark HGET
    hgetTime := benchmarkRedis(redis) |->| { redis.hget("hash:test", "field50") }
    echo("  HGET: " + (hgetTime / 1000f).toLocale("0.000") + "ms (" + hgetTime.toLocale("0") + " us)")

    // Benchmark HGETALL
    hgetallTime := benchmarkRedis(redis) |->| { redis.hgetall("hash:test") }
    echo("  HGETALL (100 fields): " + (hgetallTime / 1000f).toLocale("0.000") + "ms (" + hgetallTime.toLocale("0") + " us)")

    // Benchmark SMEMBERS
    smembersTime := benchmarkRedis(redis) |->| { redis.smembers("set:test") }
    echo("  SMEMBERS (100 members): " + (smembersTime / 1000f).toLocale("0.000") + "ms (" + smembersTime.toLocale("0") + " us)")

    // Benchmark PING
    pingTime := benchmarkRedis(redis) |->| { redis.ping }
    echo("  PING: " + (pingTime / 1000f).toLocale("0.000") + "ms (" + pingTime.toLocale("0") + " us)")

    redis.close
  }

  private Float benchmarkRedis(RedisClient redis, |->| f)
  {
    // Warmup
    3.times { f() }

    times := Float[,]
    iterations.times
    {
      start := Duration.now
      f()
      elapsed := Duration.now - start
      // Use ticks (nanoseconds) / 1000 for microseconds
      times.add(elapsed.ticks.toFloat / 1000f)
    }
    sum := 0f
    times.each |t| { sum += t }
    return sum / times.size.toFloat  // returns microseconds
  }

  private Void setupFolio()
  {
    echo("\nSetting up Redis Folio...")

    // Clear Redis first
    redis := RedisClient.open(`redis://localhost:6379/15`)
    redis.flushdb
    redis.close

    // Create folio
    dir := Env.cur.tempDir + `hxRedisBenchmark/`
    dir.create
    config := FolioConfig
    {
      it.name = "benchmark"
      it.dir = dir
      it.opts = Etc.dict1("redisUri", `redis://localhost:6379/15`)
    }
    folio = HxRedis.open(config)
    echo("  Redis Folio ready")
  }

  private Void populateData()
  {
    echo("\nPopulating test data...")
    start := Duration.now

    // Create sites (4)
    sites := Ref[,]
    4.times |i|
    {
      diff := Diff.makeAdd(Etc.dict2("dis", "Site $i", "site", Marker.val))
      result := folio.commit(diff)
      sites.add(result.newRec.id)
    }

    // Create equips (40 - 10 per site)
    equips := Ref[,]
    sites.each |siteRef, si|
    {
      10.times |i|
      {
        diff := Diff.makeAdd(Etc.dict4(
          "dis", "Equip $si-$i",
          "equip", Marker.val,
          "siteRef", siteRef,
          "ahu", Marker.val
        ))
        result := folio.commit(diff)
        equips.add(result.newRec.id)
      }
    }

    // Create points (296 - ~7 per equip to get ~340 total)
    equips.each |equipRef, ei|
    {
      7.times |i|
      {
        diff := Diff.makeAdd(Etc.dictx(
          "dis", "Point $ei-$i",
          "point", Marker.val,
          "equipRef", equipRef,
          "temp", Marker.val,
          "sensor", Marker.val,
          "his", Marker.val
        ))
        folio.commit(diff)
      }
    }

    elapsed := Duration.now - start
    total := 4 + 40 + (40 * 7)
    echo("  Created " + total + " records in " + elapsed.toMillis + "ms")
  }

  private Float benchmarkReadAll()
  {
    3.times { folio.readAll(Filter.has("id")) }  // warmup
    return benchmark |->| { folio.readAll(Filter.has("id")) }
  }

  private Float benchmarkReadSites()
  {
    3.times { folio.readAll(Filter.has("site")) }  // warmup
    return benchmark |->| { folio.readAll(Filter.has("site")) }
  }

  private Float benchmarkReadEquips()
  {
    3.times { folio.readAll(Filter.has("equip")) }  // warmup
    return benchmark |->| { folio.readAll(Filter.has("equip")) }
  }

  private Float benchmarkReadPoints()
  {
    3.times { folio.readAll(Filter.has("point")) }  // warmup
    return benchmark |->| { folio.readAll(Filter.has("point")) }
  }

  private Float benchmarkCountAll()
  {
    3.times { folio.readCount(Filter.has("id")) }  // warmup
    return benchmark |->| { folio.readCount(Filter.has("id")) }
  }

  private Float benchmark(|->| f)
  {
    times := Float[,]
    iterations.times
    {
      start := Duration.now
      f()
      elapsed := Duration.now - start
      // Use ticks (nanoseconds) / 1000 for microseconds
      times.add(elapsed.ticks.toFloat / 1000f)
    }
    sum := 0f
    times.each |t| { sum += t }
    return sum / times.size.toFloat  // returns microseconds
  }

  private Void printResults(Str:Float results)
  {
    echo("\n" + "=" * 60)
    echo("BENCHMARK RESULTS (Fantom/JVM)")
    echo("=" * 60)
    echo("")
    echo("Benchmark".padr(25) + "Avg Time (ms)".padr(15) + "Microseconds".padr(15))
    echo("-" * 55)

    total := 0f
    results.each |time, key|
    {
      label := labels[key] ?: key
      msTime := time / 1000f
      echo(label.padr(25) + msTime.toLocale("0.000") + "ms".padr(8) + time.toLocale("0") + " us")
      total += time
    }

    echo("-" * 55)
    avg := total / results.size.toFloat
    avgMs := avg / 1000f
    echo("AVERAGE".padr(25) + avgMs.toLocale("0.000") + "ms".padr(8) + avg.toLocale("0") + " us")

    echo("\n" + "=" * 60)
    echo("SUMMARY")
    echo("=" * 60)
    echo("\nRecords in database: ~324")
    echo("Benchmark iterations: " + iterations)
    echo("Average query time: " + avgMs.toLocale("0.000") + "ms (" + avg.toLocale("0") + " us)")
    echo("\nCompare this to Python benchmark to see runtime difference.")
  }

  private const Int iterations := 10

  private const Str:Str labels := [
    "read_all": "Read All Records",
    "read_sites": "Filter: site",
    "read_equips": "Filter: equip",
    "read_points": "Filter: point",
    "count_all": "Count All Records",
  ]

  private HxRedis? folio
}
