//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Trevor Adelman  Creation
//   28 Jan 2026  Trevor Adelman  Add SocketConfig, logging, AUTH from URI
//

using inet

**
** RedisClient is a pure Fantom Redis client using the RESP protocol.
**
** This implementation uses Fantom's inet::TcpSocket for TCP communication
** and implements the Redis Serialization Protocol (RESP) directly.
** No external Java dependencies required.
**
** Example usage:
**   redis := RedisClient.open(`redis://localhost:6379`)
**   redis.set("foo", "bar")
**   val := redis.get("foo")
**   redis.close
**
** URI formats supported:
**   - redis://localhost:6379         (default host/port)
**   - redis://host:6379/0            (with database number)
**   - redis://:password@host:6379    (with authentication)
**   - redis://:password@host:6379/2  (auth + database)
**
class RedisClient
{

//////////////////////////////////////////////////////////////////////////
// Construction
//////////////////////////////////////////////////////////////////////////

  ** Logger for Redis client operations
  private static const Log log := Log.get("hxRedis")

  ** Default socket configuration with timeouts
  ** Connect timeout: 5 seconds (fail fast if Redis unreachable)
  ** Receive timeout: 30 seconds (allow for slow queries)
  static const SocketConfig defaultConfig := SocketConfig {
    it.connectTimeout = 5sec
    it.receiveTimeout = 30sec
  }

  **
  ** Open a connection to Redis server.
  ** URI format: redis://[:password@]host:port[/db]
  **
  ** Examples:
  **   `redis://localhost:6379`
  **   `redis://:mypassword@localhost:6379/0`
  **
  static RedisClient open(Uri uri := `redis://localhost:6379`, SocketConfig config := defaultConfig)
  {
    host := uri.host ?: "localhost"
    port := uri.port ?: 6379
    db := 0
    if (uri.path.size > 0)
      db = uri.path[0].toInt(10, false) ?: 0

    // Extract password from URI userInfo (format: :password or user:password)
    password := extractPassword(uri)

    log.debug("Connecting to Redis at $host:$port (db=$db, auth=${password != null})")

    client := make(host, port, config)

    // Authenticate if password provided
    if (password != null)
    {
      try
      {
        client.auth(password)
        log.debug("Redis authentication successful")
      }
      catch (Err e)
      {
        client.close
        log.err("Redis authentication failed: $e.msg")
        throw e
      }
    }

    // Select database if non-default
    if (db != 0) client.select(db)

    return client
  }

  **
  ** Extract password from URI userInfo.
  ** Supports formats: :password or user:password
  ** Returns null if no password in URI.
  **
  private static Str? extractPassword(Uri uri)
  {
    userInfo := uri.userInfo
    if (userInfo == null) return null

    // Format is either ":password" or "user:password"
    colonIdx := userInfo.index(":")
    if (colonIdx == null) return null

    password := userInfo[colonIdx + 1..-1]
    return password.isEmpty ? null : password
  }

  private new make(Str host, Int port, SocketConfig config)
  {
    this.socket = TcpSocket(config)
    try
    {
      this.socket.connect(IpAddr(host), port)
    }
    catch (Err e)
    {
      log.err("Failed to connect to Redis at $host:$port: $e.msg")
      throw e
    }
    this.out = socket.out
    this.in = socket.in
  }

  private TcpSocket socket
  private OutStream out
  private InStream in

//////////////////////////////////////////////////////////////////////////
// Connection
//////////////////////////////////////////////////////////////////////////

  ** Close the Redis connection
  Void close()
  {
    socket.close
  }

  ** Ping the server, returns "PONG"
  Str ping()
  {
    sendCommand(["PING"])
    return readReply as Str ?: ""
  }

  ** Select database by index
  Void select(Int db)
  {
    sendCommand(["SELECT", db.toStr])
    readReply
  }

  ** Authenticate with password
  Void auth(Str password)
  {
    sendCommand(["AUTH", password])
    readReply
  }

//////////////////////////////////////////////////////////////////////////
// String Operations
//////////////////////////////////////////////////////////////////////////

  ** Get value by key, returns null if not found (or if pipelining)
  Str? get(Str key)
  {
    sendCommand(["GET", key])
    return maybeReadReply as Str
  }

  ** Set key to value
  Void set(Str key, Str val)
  {
    sendCommand(["SET", key, val])
    maybeReadReply
  }

  ** Delete one or more keys (returns 0 if pipelining)
  Int del(Str[] keys)
  {
    cmd := ["DEL"]
    cmd.addAll(keys)
    sendCommand(cmd)
    return maybeReadReply as Int ?: 0
  }

  ** Check if key exists (returns false if pipelining)
  Bool exists(Str key)
  {
    sendCommand(["EXISTS", key])
    return (maybeReadReply as Int ?: 0) > 0
  }

//////////////////////////////////////////////////////////////////////////
// Hash Operations
//////////////////////////////////////////////////////////////////////////

  ** Get field from hash (returns null if pipelining)
  Str? hget(Str key, Str field)
  {
    sendCommand(["HGET", key, field])
    return maybeReadReply as Str
  }

  ** Set field in hash (returns 0 if pipelining, 1 if new field, 0 if existing)
  Int hset(Str key, Str field, Str val)
  {
    sendCommand(["HSET", key, field, val])
    return maybeReadReply as Int ?: 0
  }

  ** Get all fields and values from hash (returns empty if pipelining)
  Str:Str hgetall(Str key)
  {
    sendCommand(["HGETALL", key])
    arr := maybeReadReply as Obj[]
    result := Str:Str[:]
    if (arr != null)
    {
      i := 0
      while (i + 1 < arr.size)
      {
        k := arr[i] as Str
        v := arr[i + 1] as Str
        if (k != null && v != null) result[k] = v
        i += 2
      }
    }
    return result
  }

  ** Delete field from hash (returns 0 if pipelining)
  Int hdel(Str key, Str field)
  {
    sendCommand(["HDEL", key, field])
    return maybeReadReply as Int ?: 0
  }

  ** Set multiple fields in hash
  Void hmset(Str key, Str:Str fields)
  {
    cmd := ["HMSET", key]
    fields.each |v, k| { cmd.add(k); cmd.add(v) }
    sendCommand(cmd)
    maybeReadReply
  }

//////////////////////////////////////////////////////////////////////////
// Set Operations
//////////////////////////////////////////////////////////////////////////

  ** Add members to set (returns 0 if pipelining)
  Int sadd(Str key, Str[] members)
  {
    cmd := ["SADD", key]
    cmd.addAll(members)
    sendCommand(cmd)
    return maybeReadReply as Int ?: 0
  }

  ** Remove members from set (returns 0 if pipelining)
  Int srem(Str key, Str[] members)
  {
    cmd := ["SREM", key]
    cmd.addAll(members)
    sendCommand(cmd)
    return maybeReadReply as Int ?: 0
  }

  ** Get all members of set (returns empty if pipelining)
  Str[] smembers(Str key)
  {
    sendCommand(["SMEMBERS", key])
    arr := maybeReadReply as Obj[]
    return arr?.map |v| { v as Str }?.exclude |v| { v == null } ?: Str[,]
  }

  ** Check if member exists in set (returns false if pipelining)
  Bool sismember(Str key, Str member)
  {
    sendCommand(["SISMEMBER", key, member])
    return (maybeReadReply as Int ?: 0) > 0
  }

  ** Get intersection of sets (returns empty if pipelining)
  Str[] sinter(Str[] keys)
  {
    cmd := ["SINTER"]
    cmd.addAll(keys)
    sendCommand(cmd)
    arr := maybeReadReply as Obj[]
    return arr?.map |v| { v as Str }?.exclude |v| { v == null } ?: Str[,]
  }

//////////////////////////////////////////////////////////////////////////
// Sorted Set Operations
//////////////////////////////////////////////////////////////////////////

  ** Add member with score to sorted set (returns 0 if pipelining)
  Int zadd(Str key, Float score, Str member)
  {
    sendCommand(["ZADD", key, score.toStr, member])
    return maybeReadReply as Int ?: 0
  }

  ** Get members by score range (returns empty if pipelining)
  Str[] zrangebyscore(Str key, Float min, Float max)
  {
    minStr := min == Float.negInf ? "-inf" : min.toStr
    maxStr := max == Float.posInf ? "+inf" : max.toStr
    sendCommand(["ZRANGEBYSCORE", key, minStr, maxStr])
    arr := maybeReadReply as Obj[]
    return arr?.map |v| { v as Str }?.exclude |v| { v == null } ?: Str[,]
  }

  ** Remove members from sorted set (returns 0 if pipelining)
  Int zrem(Str key, Str[] members)
  {
    cmd := ["ZREM", key]
    cmd.addAll(members)
    sendCommand(cmd)
    return maybeReadReply as Int ?: 0
  }

  ** Remove members by score range (returns count removed, 0 if pipelining)
  Int zremrangebyscore(Str key, Float min, Float max)
  {
    minStr := min == Float.negInf ? "-inf" : min.toStr
    maxStr := max == Float.posInf ? "+inf" : max.toStr
    sendCommand(["ZREMRANGEBYSCORE", key, minStr, maxStr])
    return maybeReadReply as Int ?: 0
  }

  ** Get count of members in sorted set (returns 0 if pipelining)
  Int zcard(Str key)
  {
    sendCommand(["ZCARD", key])
    return maybeReadReply as Int ?: 0
  }

//////////////////////////////////////////////////////////////////////////
// Key Operations
//////////////////////////////////////////////////////////////////////////

  ** Find keys matching pattern (returns empty if pipelining)
  Str[] keys(Str pattern)
  {
    sendCommand(["KEYS", pattern])
    arr := maybeReadReply as Obj[]
    return arr?.map |v| { v as Str }?.exclude |v| { v == null } ?: Str[,]
  }

  ** Flush current database
  Void flushdb()
  {
    sendCommand(["FLUSHDB"])
    maybeReadReply
  }

  ** Increment value (returns 0 if pipelining)
  Int incr(Str key)
  {
    sendCommand(["INCR", key])
    return maybeReadReply as Int ?: 0
  }

//////////////////////////////////////////////////////////////////////////
// Transactions
//////////////////////////////////////////////////////////////////////////

  **
  ** Start a transaction. All subsequent commands will be queued
  ** until exec() is called.
  **
  Void multi()
  {
    sendCommand(["MULTI"])
    readReply  // +OK
  }

  **
  ** Execute all commands queued since multi().
  ** Returns array of results from each queued command.
  ** If transaction was aborted (e.g., WATCH key modified), returns null.
  **
  Obj?[]? exec()
  {
    sendCommand(["EXEC"])
    return readReply as Obj?[]
  }

  **
  ** Discard all commands queued since multi().
  ** Use this to abort a transaction.
  **
  Void discard()
  {
    sendCommand(["DISCARD"])
    readReply  // +OK
  }

  **
  ** Watch one or more keys for changes.
  ** If any watched key is modified before exec(), the transaction aborts.
  **
  Void watch(Str[] keys)
  {
    cmd := ["WATCH"]
    cmd.addAll(keys)
    sendCommand(cmd)
    readReply  // +OK
  }

  **
  ** Unwatch all previously watched keys.
  **
  Void unwatch()
  {
    sendCommand(["UNWATCH"])
    readReply  // +OK
  }

//////////////////////////////////////////////////////////////////////////
// Pipelining
//////////////////////////////////////////////////////////////////////////

  ** Whether we're currently in pipeline mode
  private Bool pipelining := false

  ** Count of commands sent during current pipeline
  private Int pipelineCount := 0

  **
  ** Execute multiple commands in a single round trip.
  ** Commands are buffered and sent together, then all responses are read.
  **
  ** Example:
  **   results := redis.pipeline {
  **     it.set("key1", "val1")
  **     it.set("key2", "val2")
  **     it.get("key1")
  **   }
  **   // results = ["OK", "OK", "val1"]
  **
  Obj?[] pipeline(|This| block)
  {
    // Enter pipeline mode
    pipelining = true
    pipelineCount = 0

    try
    {
      // Execute the block - commands are sent but responses not read
      block(this)

      // Flush any remaining buffered output
      out.flush

      // Read all responses
      results := Obj?[,]
      pipelineCount.times { results.add(readReply) }
      return results
    }
    finally
    {
      pipelining = false
      pipelineCount = 0
    }
  }

//////////////////////////////////////////////////////////////////////////
// RESP Protocol
//////////////////////////////////////////////////////////////////////////

  **
  ** Send a command to Redis using RESP protocol.
  ** Commands are sent as arrays: *<count>\r\n$<len>\r\n<arg>\r\n...
  ** If pipelining, command count is tracked and flush is deferred.
  **
  private Void sendCommand(Str[] args)
  {
    // Track command count for pipelining
    if (pipelining) pipelineCount++

    // Array header
    out.print("*${args.size}\r\n")

    // Each argument as bulk string
    args.each |arg|
    {
      bytes := arg.toBuf
      out.print("\$${bytes.size}\r\n")
      out.writeBuf(bytes)
      out.print("\r\n")
    }

    // Don't flush during pipeline - wait until all commands are sent
    if (!pipelining) out.flush
  }

  **
  ** Read reply only if not in pipeline mode.
  ** Returns the reply or null if pipelining.
  **
  private Obj? maybeReadReply()
  {
    if (pipelining) return null
    return readReply
  }

  **
  ** Read a reply from Redis.
  ** Returns: Str (simple/bulk string), Int, Obj[] (array), or null
  **
  private Obj? readReply()
  {
    type := in.readChar

    switch (type)
    {
      // Simple string: +OK\r\n
      case '+':
        return readLine

      // Error: -ERR message\r\n
      case '-':
        msg := readLine
        throw RedisErr(msg)

      // Integer: :123\r\n
      case ':':
        return readLine.toInt

      // Bulk string: $<len>\r\n<data>\r\n
      case '\$':
        len := readLine.toInt
        if (len < 0) return null
        buf := Buf(len)
        // Read all bytes - readBuf may not read all in one call
        remaining := len
        while (remaining > 0)
        {
          read := in.readBuf(buf, remaining)
          if (read == null) throw RedisErr("Unexpected end of stream reading bulk string")
          remaining -= read
        }
        in.readChar  // \r
        in.readChar  // \n
        // Convert bytes to string - len is byte count, not char count
        // UTF-8 multi-byte chars mean byte count != char count
        // IMPORTANT: pass false to disable line ending normalization (\r\n -> \n)
        return buf.seek(0).readAllStr(false)

      // Array: *<count>\r\n<elements>
      case '*':
        count := readLine.toInt
        if (count < 0) return null
        arr := Obj?[,]
        count.times { arr.add(readReply) }
        return arr

      default:
        throw RedisErr("Unknown RESP type: $type")
    }
  }

  ** Read a line (until \r\n)
  private Str readLine()
  {
    buf := StrBuf()
    while (true)
    {
      ch := in.readChar
      if (ch == '\r')
      {
        in.readChar  // consume \n
        break
      }
      buf.addChar(ch)
    }
    return buf.toStr
  }
}

**************************************************************************
** RedisErr
**************************************************************************

**
** Redis error returned by server
**
const class RedisErr : Err
{
  new make(Str msg) : super(msg) {}
}
