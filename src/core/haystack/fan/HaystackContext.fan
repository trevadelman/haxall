//
// Copyright (c) 2020, SkyFoundry LLC
// Licensed under the Academic Free License version 3.0
//
// History:
//   10 Aug 2020  Brian Frank  Creation
//

using xeto

**
** HaystackContext defines an environment of defs and data
**
@Js
mixin HaystackContext : XetoContext
{
  ** Nil context has no data and no inference
  @NoDoc static HaystackContext nil() { nilRef }
  private static const NilContext nilRef := NilContext()

  ** Return true if the given rec is nominally an instance of the given
  ** spec.  This is used by haystack Filters with a spec name.  The spec
  ** name may be qualified or unqualified.
  @NoDoc override Bool xetoIsSpec(Str spec, Dict rec) { false }

  ** Read a data record by id or return null
  @NoDoc override Dict? xetoReadById(Obj id) { deref(id) }

  ** Read all the records that match given haystack filter
  @NoDoc override Obj? xetoReadAllEachWhile(Str filter, |Dict->Obj?| f) { null }

  ** Dereference an id to an record dict or null if unresolved
  @NoDoc abstract Dict? deref(Ref id)

  ** Return inference engine used for def aware filter queries
  @NoDoc abstract FilterInference inference()

  ** Return contextual data as dict - see context()
  @NoDoc abstract Dict toDict()
}

**************************************************************************
** NilContext
**************************************************************************

@Js
internal const class NilContext : HaystackContext
{
  override Dict? deref(Ref id) { null }
  override FilterInference inference() { FilterInference.nil }
  override Dict toDict() { Etc.dict0 }
}

**************************************************************************
** PatherContext
**************************************************************************

** PatherContext provides legacy support for filter pathing.
** Optionally accepts a namespace function for xetoIsSpec support.
@NoDoc @Js
class PatherContext : HaystackContext
{
  // PYTHON-FANTOM: Added optional nsFunc parameter to enable xetoIsSpec support.
  // FolioFlatFile uses PatherContext for filter matching, and without namespace
  // access, spec-type filters like "Equip" would always return false.
  // The nsFunc callback allows FolioFlatFile to pass hooks.ns for resolution.
  new make(|Ref->Dict?| pather, |Bool->Namespace?|? nsFunc := null)
  {
    this.pather = pather
    this.nsFunc = nsFunc
  }

  override Dict? deref(Ref id) { pather(id) }

  override Bool xetoIsSpec(Str specName, Dict rec)
  {
    if (nsFunc == null) return false
    ns := nsFunc(false)
    if (ns == null) return false
    spec := xetoIsSpecCache?.get(specName)
    if (spec == null)
    {
      if (xetoIsSpecCache == null) xetoIsSpecCache = Str:Spec[:]
      spec = specName.contains("::") ? ns.type(specName) : ns.unqualifiedType(specName)
      xetoIsSpecCache[specName] = spec
    }
    return ns.specOf(rec).isa(spec)
  }

  private |Ref->Dict?| pather
  private |Bool->Namespace?|? nsFunc
  private [Str:Spec]? xetoIsSpecCache
  override FilterInference inference() { FilterInference.nil }
  override Dict toDict() { Etc.dict0 }
}

**************************************************************************
** HaystackFunc
**************************************************************************

** Mixin for Axon functions
@NoDoc @Js
mixin HaystackFunc
{
  ** Call the function
  abstract Obj? haystackCall(HaystackContext cx, Obj?[] args)
}

