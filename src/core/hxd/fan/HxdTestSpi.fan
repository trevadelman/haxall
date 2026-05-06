//
// Copyright (c) 2021, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   21 May 2021  Brian Frank  Creation
//

using concurrent
using xeto
using haystack
using folio
using hx
using hxm

**
** Haxall daemon HxTest service provider implementation
**
class HxdTestSpi : HxTestSpi
{
  new make(HxTest test) : super(test) {}

  static HxdBoot boot(File dir, Bool create, Dict projMeta := Etc.dict0)
  {
    HxdBoot.makeTest(dir, create, projMeta)
  }

  override Proj start(Dict projMeta)
  {
    boot(test.tempDir, true, projMeta).init.start
  }

  override Void stop(Proj proj)
  {
    ((HxRuntime)proj).stop
  }

  override Proj restart(Proj proj)
  {
    stop(proj)
    return boot(proj.dir, false).init.start
  }

  override Void addLib(Str libName)
  {
    proj.libs.addDepends(libName, true)
  }

  override Ext addExt(Str libName, Str:Obj? tags)
  {
    // add depends we need to enable too (but not the ext itself)
    proj.libs.addDepends(libName, false)

    // then update/add ext
    ext := proj.exts.get(libName, false)
    if (ext == null)
      ext = proj.exts.add(libName, Etc.makeDict(tags))
    else
      ext.spi.settingsUpdate(Etc.makeDict(tags))
    ext.spi.sync
    return ext
  }

  override HxUser addUser(Str user, Str pass, Str:Obj? tags)
  {
    HxdUserUtil.addUser(test.proj.db, user, pass, tags)
  }

  override Context makeContext(User? user)
  {
    if (user == null)
      user = test.proj.sys.user.makeUser("test", ["userRole":"su"])
    return test.proj.newContext(user)
  }

  override Void forceSteadyState()
  {
    ((HxRuntime)proj).backgroundMgr.forceSteadyState
  }

  Proj proj() { test.proj }
}

