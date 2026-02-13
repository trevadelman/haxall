//
// Copyright (c) 2025, Trevor Adelman
// Licensed under the Academic Free License version 3.0
//
// History:
//   13 Feb 2025  Trevor Adelman  Creation
//

using haystack
using folio
using xeto

**
** RustFolioTestImpl plugs the RustFolio implementation into
** the testFolio test harness via the FolioTestImpl SPI.
**
class RustFolioTestImpl : FolioTestImpl
{
  ** Implementation name for test output
  override Str name() { "rustfolio" }

  ** Open a RustFolio instance for the given config
  override Folio open(FolioConfig c) { RustFolio.open(c) }

  ** Disable transient support until Milestone 3
  override Bool supportsTransient() { false }

  ** Disable history support until Milestone 5
  override Bool supportsHis() { false }

  ** Refs cross a process boundary -- use equality, not identity
  override Void verifyIdsSame(Ref a, Ref b) { verifyEq(a, b) }

  ** Dicts are deserialized fresh each time -- use value equality
  override Void verifyRecSame(Dict? a, Dict? b)
  {
    if (a == null) { verify(b == null); return }
    test.verifyDictEq(a, b)
  }

  ** Display string verification (disabled until Milestone 6)
  override Void verifyDictDis(Dict r, Str expect) {}

  ** Display string verification (disabled until Milestone 6)
  override Void verifyIdDis(Ref id, Str expect) {}
}
