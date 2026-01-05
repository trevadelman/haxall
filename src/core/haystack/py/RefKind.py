#
# haystack::RefKind - Native Python implementation
#
# This adds the missing defVal() override. The Fantom source's Kind.defVal()
# calls type.make, but Ref.make() requires id/dis arguments.
#
# UPSTREAM FIX NEEDED: Add to RefKind in haxall/src/core/haystack/fan/Kind.fan:
#   override Obj defVal() { Ref.defVal }
#

from fan.haystack.Kind import Kind
from fan.sys.ObjUtil import ObjUtil
from fan.sys.Type import Type
from fan.xeto.Ref import Ref
from fan.xeto.Dict import Dict


class RefKind(Kind):

    @staticmethod
    def make():
        return RefKind()

    @staticmethod
    def makeTag(tag):
        inst = object.__new__(RefKind)
        inst._ctor_init()
        inst._makeTag_body(tag)
        return inst

    def _makeTag_body(self, tag):
        super().__init__("Ref", Type.find("xeto::Ref"), (("Ref<" + tag) + ">"))
        self._tag = tag

    def _ctor_init(self):
        super()._ctor_init()
        self._tag = None

    def __init__(self):
        super().__init__("Ref", Type.find("xeto::Ref"))
        self._tag = None

    def tag(self, _val_=None):
        if _val_ is None:
            return self._tag
        else:
            self._tag = _val_

    def toTagOf(self, tag):
        return self.makeTag(tag)

    def isRef(self):
        return True

    def defVal(self):
        """Return Ref.defVal instead of type.make (which requires args)."""
        return Ref.defVal()

    def valToStr(self, val):
        return ObjUtil.coerce(val, "xeto::Ref").toCode()

    def valToDis(self, val, meta=None):
        if meta is None:
            meta = __import__('fan.haystack.Etc', fromlist=['Etc']).Etc.dict0()
        return ObjUtil.coerce(val, "xeto::Ref").dis()

    def valToZinc(self, val):
        return ObjUtil.coerce(val, "xeto::Ref").toZinc()

    def valToJson(self, val):
        return ObjUtil.coerce(val, "xeto::Ref").toJson()

    def valToAxon(self, val):
        return ObjUtil.coerce(val, "xeto::Ref").toCode()


# Type metadata registration for reflection
from fan.sys.Param import Param
from fan.sys.Slot import FConst
_t = Type.find('haystack::RefKind')
_t.tf_({'sys::Js': {}}, 73736, [], 'haystack::Kind')
_t.af_('tag', 12801, 'sys::Str?', {})
_t.am_('make', 257, 'sys::Void', [], {})
_t.am_('makeTag', 257, 'sys::Void', [Param('tag', Type.find('sys::Str?'), False)], {})
_t.am_('toTagOf', 4609, 'haystack::Kind', [Param('tag', Type.find('sys::Str'), False)], {})
_t.am_('isRef', 4609, 'sys::Bool', [], {})
_t.am_('defVal', 4609, 'sys::Obj', [], {})
_t.am_('valToStr', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
_t.am_('valToDis', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False), Param('meta', Type.find('xeto::Dict'), True)], {})
_t.am_('valToZinc', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
_t.am_('valToJson', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
_t.am_('valToAxon', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
