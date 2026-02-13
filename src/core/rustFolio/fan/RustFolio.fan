//
// Copyright (c) 2025, Trevor Adelman
// Licensed under the Academic Free License version 3.0
//
// History:
//   13 Feb 2025  Trevor Adelman  Creation
//

using concurrent
using haystack
using folio
using xeto

**
** RustFolio is a Folio implementation backed by a standalone Rust process.
** The Rust process handles record persistence, filter evaluation, history
** storage, and display string computation via a binary wire protocol over
** Unix domain sockets.
**
** This class manages the Rust process lifecycle and delegates storage
** operations while handling passwords, hooks, file storage, and permissions
** locally on the Fantom side.
**
const class RustFolio : Folio
{

//////////////////////////////////////////////////////////////////////////
// Construction
//////////////////////////////////////////////////////////////////////////

  ** Open a RustFolio database for the given configuration.
  static RustFolio open(FolioConfig config)
  {
    return make(config)
  }

  private new make(FolioConfig config) : super(config)
  {
    this.passwords = PasswordStore.open(dir + `passwords.props`, config)
  }

//////////////////////////////////////////////////////////////////////////
// Identity
//////////////////////////////////////////////////////////////////////////

  override const PasswordStore passwords

  override Int curVer() { throw UnsupportedErr("RustFolio.curVer not yet implemented") }

//////////////////////////////////////////////////////////////////////////
// Modes
//////////////////////////////////////////////////////////////////////////

  override Str flushMode
  {
    get { throw UnsupportedErr("RustFolio.flushMode not yet implemented") }
    set { throw UnsupportedErr("RustFolio.flushMode not yet implemented") }
  }

  override Void flush() { throw UnsupportedErr("RustFolio.flush not yet implemented") }

//////////////////////////////////////////////////////////////////////////
// Subsystems
//////////////////////////////////////////////////////////////////////////

  override FolioBackup backup() { throw UnsupportedErr("RustFolio.backup not yet implemented") }

  override FolioHis his() { throw UnsupportedErr("RustFolio.his not yet implemented") }

  override FolioFile file() { throw UnsupportedErr("RustFolio.file not yet implemented") }

//////////////////////////////////////////////////////////////////////////
// Close
//////////////////////////////////////////////////////////////////////////

  override protected FolioFuture doCloseAsync()
  {
    return FolioFuture.makeSync(CountFolioRes(0))
  }

//////////////////////////////////////////////////////////////////////////
// Reads
//////////////////////////////////////////////////////////////////////////

  override protected FolioRec? doReadRecById(Ref id)
  {
    throw UnsupportedErr("RustFolio.doReadRecById not yet implemented")
  }

  override protected FolioFuture doReadByIds(Ref[] ids)
  {
    throw UnsupportedErr("RustFolio.doReadByIds not yet implemented")
  }

  override protected FolioFuture doReadAll(Filter filter, Dict? opts)
  {
    throw UnsupportedErr("RustFolio.doReadAll not yet implemented")
  }

  override protected Int doReadCount(Filter filter, Dict? opts)
  {
    throw UnsupportedErr("RustFolio.doReadCount not yet implemented")
  }

  override protected Obj? doReadAllEachWhile(Filter filter, Dict? opts, |Dict->Obj?| f)
  {
    throw UnsupportedErr("RustFolio.doReadAllEachWhile not yet implemented")
  }

//////////////////////////////////////////////////////////////////////////
// Commits
//////////////////////////////////////////////////////////////////////////

  override protected FolioFuture doCommitAllAsync(Diff[] diffs, Obj? cxInfo)
  {
    throw UnsupportedErr("RustFolio.doCommitAllAsync not yet implemented")
  }
}
