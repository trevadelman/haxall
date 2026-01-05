#
# haystack::BinKind - Native Python implementation
#
# This adds the missing defVal() override. The Fantom source's Kind.defVal()
# calls type.make, but Bin.make() requires a mime argument.
#
# UPSTREAM FIX NEEDED: Add to BinKind in haxall/src/core/haystack/fan/Kind.fan:
#   override Obj defVal() { Bin.defVal }
#

from fan.haystack.Kind import Kind
from fan.sys.ObjUtil import ObjUtil
from fan.sys.Str import Str
from fan.sys.Type import Type


class BinKind(Kind):

    @staticmethod
    def make():
        return BinKind()

    def __init__(self):
        super().__init__("Bin", Type.find("haystack::Bin"))

    def isXStr(self):
        return True

    def defVal(self):
        """Return Bin.defVal instead of type.make (which requires args)."""
        from fan.haystack.Bin import Bin
        return Bin.defVal()

    def valToZinc(self, val):
        return (("Bin(" + Str.toCode(ObjUtil.coerce(val, "haystack::Bin")._mime.toStr())) + ")")

    def valToJson(self, val):
        return ("b:" + ObjUtil.coerce(val, "haystack::Bin")._mime.toStr())

    def valToAxon(self, val):
        return (("xstr(\"Bin\"," + Str.toCode(ObjUtil.coerce(val, "haystack::Bin")._mime.toStr())) + ")")


# Type metadata registration for reflection
from fan.sys.Param import Param
from fan.sys.Slot import FConst
_t = Type.find('haystack::BinKind')
_t.tf_({'sys::Js': {}}, 73736, [], 'haystack::Kind')
_t.am_('make', 257, 'sys::Void', [], {})
_t.am_('isXStr', 4609, 'sys::Bool', [], {})
_t.am_('defVal', 4609, 'sys::Obj', [], {})
_t.am_('valToZinc', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
_t.am_('valToJson', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
_t.am_('valToAxon', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
