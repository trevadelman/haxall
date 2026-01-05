#
# haystack::CoordKind - Native Python implementation
#
# This adds the missing defVal() override. The Fantom source's Kind.defVal()
# calls type.make, but Coord.make() requires lat/lng arguments.
#
# UPSTREAM FIX NEEDED: Add to CoordKind in haxall/src/core/haystack/fan/Kind.fan:
#   override Obj defVal() { Coord.defVal }
#

from fan.haystack.Kind import Kind
from fan.sys.ObjUtil import ObjUtil
from fan.sys.Type import Type


class CoordKind(Kind):

    @staticmethod
    def make():
        return CoordKind()

    def __init__(self):
        super().__init__("Coord", Type.find("haystack::Coord"))

    def defVal(self):
        """Return Coord.defVal instead of type.make (which requires args)."""
        from fan.haystack.Coord import Coord
        return Coord.defVal()

    def valToJson(self, val):
        return ("c:" + ObjUtil.coerce(val, "haystack::Coord").toLatLgnStr())

    def valToAxon(self, val):
        return (("coord(" + ObjUtil.coerce(val, "haystack::Coord").toLatLgnStr()) + ")")


# Type metadata registration for reflection
from fan.sys.Param import Param
from fan.sys.Slot import FConst
_t = Type.find('haystack::CoordKind')
_t.tf_({'sys::Js': {}}, 73736, [], 'haystack::Kind')
_t.am_('make', 257, 'sys::Void', [], {})
_t.am_('defVal', 4609, 'sys::Obj', [], {})
_t.am_('valToJson', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
_t.am_('valToAxon', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
