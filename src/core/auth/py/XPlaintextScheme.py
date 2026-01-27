#
# auth::XPlaintextScheme - Python native implementation
#
# Fixed to properly call PlaintextScheme's constructor with name parameter.
#

import sys as sys_module
sys_module.path.insert(0, '.')

from typing import Optional, Callable, List as TypingList, Dict as TypingDict

from fan import sys
from fan.auth.PlaintextScheme import PlaintextScheme
from fan.sys.ObjUtil import ObjUtil
from fan import concurrent
from fan import inet
from fan import web
from fan import haystack


class XPlaintextScheme(PlaintextScheme):

    @staticmethod
    def make():
        return XPlaintextScheme()

    def __init__(self):
        super().__init__("x-plaintext")


# Type metadata registration for reflection
from fan.sys.Param import Param
from fan.sys.Slot import FConst
_t = sys.Type.find('auth::XPlaintextScheme')
_t.tf_({'sys::NoDoc': {}}, 8194, [], 'auth::PlaintextScheme')
_t.am_('make', 8196, 'sys::Void', [], {})
