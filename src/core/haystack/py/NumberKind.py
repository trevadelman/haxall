#
# haystack::NumberKind - Native Python implementation
#
# This adds the missing defVal() override. The Fantom source's Kind.defVal()
# calls type.make, but Number.make() requires a val argument.
#
# UPSTREAM FIX NEEDED: Add to NumberKind in haxall/src/core/haystack/fan/Kind.fan:
#   override Obj defVal() { Number.defVal }
#

from fan.haystack.Kind import Kind
from fan.sys.ObjUtil import ObjUtil
from fan.sys.Float import Float
from fan.sys.Type import Type
from fan.xeto.Dict import Dict


class NumberKind(Kind):

    @staticmethod
    def make():
        return NumberKind()

    def __init__(self):
        super().__init__("Number", Type.find("haystack::Number"))

    def isNumber(self):
        return True

    def defVal(self):
        """Return Number.defVal instead of type.make (which requires args)."""
        from fan.haystack.Number import Number
        return Number.defVal()

    def valToDis(self, val, meta=None):
        if meta is None:
            meta = __import__('fan.haystack.Etc', fromlist=['Etc']).Etc.dict0()
        return ObjUtil.coerce(val, "haystack::Number").toLocale(ObjUtil.coerce(meta["format"], "sys::Str?"))

    def valToJson(self, val):
        return ObjUtil.coerce(val, "haystack::Number").toJson()

    def valToAxon(self, val):
        f = ObjUtil.coerce(val, "haystack::Number").toFloat()
        if Float.isNaN(f):
            return "nan()"
        if (f == Float.posInf()):
            return "posInf()"
        if (f == Float.negInf()):
            return "negInf()"
        return ObjUtil.toStr(val)


# Type metadata registration for reflection
from fan.sys.Param import Param
from fan.sys.Slot import FConst
_t = Type.find('haystack::NumberKind')
_t.tf_({'sys::Js': {}}, 73736, [], 'haystack::Kind')
_t.am_('make', 257, 'sys::Void', [], {})
_t.am_('isNumber', 4609, 'sys::Bool', [], {})
_t.am_('defVal', 4609, 'sys::Obj', [], {})
_t.am_('valToDis', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False), Param('meta', Type.find('xeto::Dict'), True)], {})
_t.am_('valToJson', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
_t.am_('valToAxon', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
