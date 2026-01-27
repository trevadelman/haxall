//
// Copyright (c) 2026, Project Haystack
// Licensed under the Academic Free License version 3.0
//
// History:
//   27 Jan 2026  Trevor Adelman  Creation
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
class RedisClient
{

//////////////////////////////////////////////////////////////////////////
// Construction
//////////////////////////////////////////////////////////////////////////

  **
  ** Open a connection to Redis server.
  ** URI format: redis://host:port or redis://host:port/db
  **
  static RedisClient open(Uri uri := `redis://localhost:6379`)
  {
    host := uri.host ?: "localhost"
    port := uri.port ?: 6379
    db := 0
    if (uri.path.size > 0)
      db = uri.path[0].toInt(10, false) ?: 0

    client := make(host, port)
    if (db != 0) client.select(db)
    return client
  }

  private new make(Str host, Int port)
  {
    this.socket = TcpSocket()
    this.socket.connect(IpAddr(host), port)
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

  ** Get value by key, returns null if not found
  Str? get(Str key)
  {
    sendCommand(["GET", key])
    return readReply as Str
  }

  ** Set key to value
  Void set(Str key, Str val)
  {
    sendCommand(["SET", key, val])
    readReply
  }

  ** Delete one or more keys
  Int del(Str[] keys)
  {
    cmd := ["DEL"]
    cmd.addAll(keys)
    sendCommand(cmd)
    return readReply as Int ?: 0
  }

  ** Check if key exists
  Bool exists(Str key)
  {
    sendCommand(["EXISTS", key])
    return (readReply as Int ?: 0) > 0
  }

//////////////////////////////////////////////////////////////////////////
// Hash Operations
//////////////////////////////////////////////////////////////////////////

  ** Get field from hash
  Str? hget(Str key, Str field)
  {
    sendCommand(["HGET", key, field])
    return readReply as Str
  }

  ** Set field in hash
  Void hset(Str key, Str field, Str val)
  {
    sendCommand(["HSET", key, field, val])
    readReply
  }

  ** Get all fields and values from hash
  Str:Str hgetall(Str key)
  {
    sendCommand(["HGETALL", key])
    arr := readReply as Obj[]
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

  ** Delete field from hash
  Int hdel(Str key, Str field)
  {
    sendCommand(["HDEL", key, field])
    return readReply as Int ?: 0
  }

  ** Set multiple fields in hash
  Void hmset(Str key, Str:Str fields)
  {
    cmd := ["HMSET", key]
    fields.each |v, k| { cmd.add(k); cmd.add(v) }
    sendCommand(cmd)
    readReply
  }

//////////////////////////////////////////////////////////////////////////
// Set Operations
//////////////////////////////////////////////////////////////////////////

  ** Add members to set
  Int sadd(Str key, Str[] members)
  {
    cmd := ["SADD", key]
    cmd.addAll(members)
    sendCommand(cmd)
    return readReply as Int ?: 0
  }

  ** Remove members from set
  Int srem(Str key, Str[] members)
  {
    cmd := ["SREM", key]
    cmd.addAll(members)
    sendCommand(cmd)
    return readReply as Int ?: 0
  }

  ** Get all members of set
  Str[] smembers(Str key)
  {
    sendCommand(["SMEMBERS", key])
    arr := readReply as Obj[]
    return arr?.map |v| { v as Str }?.exclude |v| { v == null } ?: Str[,]
  }

  ** Check if member exists in set
  Bool sismember(Str key, Str member)
  {
    sendCommand(["SISMEMBER", key, member])
    return (readReply as Int ?: 0) > 0
  }

  ** Get intersection of sets
  Str[] sinter(Str[] keys)
  {
    cmd := ["SINTER"]
    cmd.addAll(keys)
    sendCommand(cmd)
    arr := readReply as Obj[]
    return arr?.map |v| { v as Str }?.exclude |v| { v == null } ?: Str[,]
  }

//////////////////////////////////////////////////////////////////////////
// Sorted Set Operations
//////////////////////////////////////////////////////////////////////////

  ** Add member with score to sorted set
  Int zadd(Str key, Float score, Str member)
  {
    sendCommand(["ZADD", key, score.toStr, member])
    return readReply as Int ?: 0
  }

  ** Get members by score range
  Str[] zrangebyscore(Str key, Float min, Float max)
  {
    minStr := min == Float.negInf ? "-inf" : min.toStr
    maxStr := max == Float.posInf ? "+inf" : max.toStr
    sendCommand(["ZRANGEBYSCORE", key, minStr, maxStr])
    arr := readReply as Obj[]
    return arr?.map |v| { v as Str }?.exclude |v| { v == null } ?: Str[,]
  }

  ** Remove members from sorted set
  Int zrem(Str key, Str[] members)
  {
    cmd := ["ZREM", key]
    cmd.addAll(members)
    sendCommand(cmd)
    return readReply as Int ?: 0
  }

//////////////////////////////////////////////////////////////////////////
// Key Operations
//////////////////////////////////////////////////////////////////////////

  ** Find keys matching pattern
  Str[] keys(Str pattern)
  {
    sendCommand(["KEYS", pattern])
    arr := readReply as Obj[]
    return arr?.map |v| { v as Str }?.exclude |v| { v == null } ?: Str[,]
  }

  ** Flush current database
  Void flushdb()
  {
    sendCommand(["FLUSHDB"])
    readReply
  }

  ** Increment value
  Int incr(Str key)
  {
    sendCommand(["INCR", key])
    return readReply as Int ?: 0
  }

//////////////////////////////////////////////////////////////////////////
// RESP Protocol
//////////////////////////////////////////////////////////////////////////

  **
  ** Send a command to Redis using RESP protocol.
  ** Commands are sent as arrays: *<count>\r\n$<len>\r\n<arg>\r\n...
  **
  private Void sendCommand(Str[] args)
  {
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

    out.flush
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
          if (read == null) throw RedisErr("Unexpected end of stream")
          remaining -= read
        }
        in.readChar  // \r
        in.readChar  // \n
        // Use readChars to preserve exact bytes without line ending conversion
        return buf.seek(0).readChars(len)

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
