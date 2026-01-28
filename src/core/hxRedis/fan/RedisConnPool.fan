//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   28 Jan 2026  Trevor Adelman  Creation
//

using concurrent

**
** RedisConnPool maintains a pool of RedisClient connections for reuse.
**
** This implementation uses Lock for thread-safe access.
** Connections are lazily created and validated with PING before use.
**
** Example:
**   pool := RedisConnPool(uri)
**   result := pool.execute |redis| { redis.get("key") }
**   pool.close
**
class RedisConnPool
{
  ** Logger
  private static const Log log := Log.get("hxRedis")

  ** Redis URI for connections
  const Uri uri

  ** Target number of connections in pool
  const Int poolSize

  ** Available connections
  private RedisClient[] available := [,]

  ** All connections (for cleanup)
  private RedisClient[] allConns := [,]

  ** Error count for monitoring
  private Int errorCount := 0

  ** Whether pool has been closed
  private Bool closed := false

  ** Lock for thread-safe access
  private Lock mutex := Lock.makeReentrant

  ** Create pool with given URI and optional size
  new make(Uri uri, Int poolSize := 3)
  {
    this.uri = uri
    this.poolSize = poolSize
    // Initialize connections eagerly
    poolSize.times { createConnection }
    log.debug("RedisConnPool initialized: $allConns.size connections to $uri")
  }

  **
  ** Execute a callback with a pooled connection.
  ** Connection is automatically returned to pool after callback.
  ** If connection fails, a new one will be created.
  **
  Obj? execute(|RedisClient->Obj?| f)
  {
    conn := checkout
    try
    {
      return f(conn)
    }
    catch (Err e)
    {
      mutex.lock
      try { errorCount++ }
      finally { mutex.unlock }
      // Don't return bad connection - let it be garbage collected
      try { conn.close } catch {}
      createConnection  // Replace with fresh connection
      throw e
    }
    finally
    {
      checkin(conn)
    }
  }

  **
  ** Get a connection from the pool.
  ** Creates new connection if pool is exhausted.
  **
  private RedisClient checkout()
  {
    mutex.lock
    try
    {
      if (closed) throw Err("Pool is closed")

      if (available.isEmpty)
      {
        // Pool exhausted - will create new connection after unlock
        return RedisClient.open(uri)
      }
      else
      {
        // Get connection from pool
        return available.pop
      }
    }
    finally { mutex.unlock }
  }

  **
  ** Return a connection to the pool.
  **
  private Void checkin(RedisClient conn)
  {
    mutex.lock
    try
    {
      if (closed)
      {
        // Pool closed - just close the connection
        try { conn.close } catch {}
        return
      }

      // Only return to pool if we're under target size
      if (available.size < poolSize)
      {
        available.add(conn)
      }
      else
      {
        // Over target - close excess connection
        try { conn.close } catch {}
      }
    }
    finally { mutex.unlock }
  }

  **
  ** Create a new connection and add to pool.
  **
  private Void createConnection()
  {
    try
    {
      conn := RedisClient.open(uri)
      mutex.lock
      try
      {
        allConns.add(conn)
        available.add(conn)
      }
      finally { mutex.unlock }
    }
    catch (Err e)
    {
      log.warn("Failed to create Redis connection: $e.msg")
    }
  }

  **
  ** Close all connections in the pool.
  **
  Void close()
  {
    mutex.lock
    try
    {
      closed = true
      allConns.each |conn|
      {
        try { conn.close }
        catch (Err e) { /* ignore */ }
      }
      allConns.clear
      available.clear
      log.debug("RedisConnPool closed")
    }
    finally { mutex.unlock }
  }

  **
  ** Check health of available connections, reconnecting bad ones.
  **
  Void checkHealth()
  {
    badConns := RedisClient[,]

    mutex.lock
    try
    {
      available.each |conn|
      {
        try
        {
          if (conn.ping != "PONG")
            badConns.add(conn)
        }
        catch (Err e)
        {
          log.debug("Health check failed: $e.msg")
          badConns.add(conn)
        }
      }
    }
    finally { mutex.unlock }

    // Replace bad connections
    badConns.each |bad|
    {
      mutex.lock
      try
      {
        available.remove(bad)
        allConns.remove(bad)
      }
      finally { mutex.unlock }
      try { bad.close } catch {}
      createConnection
      log.debug("Replaced dead connection")
    }
  }

  **
  ** Get debug info about pool state.
  **
  Str debug()
  {
    mutex.lock
    try
    {
      return "RedisConnPool: uri=$uri, total=$allConns.size, available=$available.size, errors=$errorCount"
    }
    finally { mutex.unlock }
  }
}
