#
# haystack::XStrKind - Native Python implementation
#
# This adds the missing defVal() override. The Fantom source's Kind.def_val()
# calls type.make, but XStr.make() requires type/val arguments.
#
# UPSTREAM FIX NEEDED: Add to XStrKind in haxall/src/core/haystack/fan/Kind.fan:
#   override Obj defVal() { XStr.defVal }
#

from fan.haystack.Kind import Kind
from fan.sys.ObjUtil import ObjUtil
from fan.sys.Str import Str
from fan.sys.Type import Type


class XStrKind(Kind):

    @staticmethod
    def make():
        return XStrKind()

    def __init__(self):
        super().__init__("XStr", Type.find("haystack::XStr"))

    def is_x_str(self):
        return True

    def def_val(self):
        """Return XStr.defVal instead of type.make (which requires args)."""
        from fan.haystack.XStr import XStr
        return XStr.def_val()

    def val_to_json(self, val):
        x = ObjUtil.coerce(val, "haystack::XStr")
        return ((("x:" + x._type_) + ":") + x._val)

    def val_to_axon(self, val):
        x = ObjUtil.coerce(val, "haystack::XStr")
        return (((("xstr(" + Str.to_code(x._type_)) + ", ") + Str.to_code(x._val)) + ")")


# Type metadata registration for reflection
from fan.sys.Param import Param
from fan.sys.Slot import FConst
_t = Type.find('haystack::XStrKind')
_t.tf_({'sys::Js': {}}, 73736, [], 'haystack::Kind')
_t.am_('make', 257, 'sys::Void', [], {})
_t.am_('isXStr', 4609, 'sys::Bool', [], {})
_t.am_('defVal', 4609, 'sys::Obj', [], {})
_t.am_('valToJson', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
_t.am_('valToAxon', 4609, 'sys::Str', [Param('val', Type.find('sys::Obj'), False)], {})
