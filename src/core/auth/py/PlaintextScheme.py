#
# auth::PlaintextScheme - Python native implementation
#
# Fixes the constructor to accept optional name parameter for subclass use.
#

import sys as sys_module
sys_module.path.insert(0, '.')

from typing import Optional, Callable, List as TypingList, Dict as TypingDict

from fan import sys
from fan.auth.AuthScheme import AuthScheme
from fan.sys.ObjUtil import ObjUtil
from fan import concurrent
from fan import inet
from fan import web
from fan import haystack


class PlaintextScheme(AuthScheme):

    @staticmethod
    def make():
        return PlaintextScheme()

    @staticmethod
    def make_scheme(name):
        inst = object.__new__(PlaintextScheme)
        inst._ctor_init()
        inst._make_scheme_body(name)
        return inst

    def _make_scheme_body(self, name):
        super().__init__(name)

    def _ctor_init(self):
        pass

    def __init__(self, name="plaintext"):
        """Accept optional name parameter for subclass use."""
        super().__init__(name)

    def on_client(self, cx: 'AuthClientContext', msg: 'AuthMsg') -> 'AuthMsg':
        return __import__('fan.auth.AuthMsg', fromlist=['AuthMsg']).AuthMsg.make(self._name, sys.Map.from_literal(["username", "password"], [__import__('fan.auth.AuthUtil', fromlist=['AuthUtil']).AuthUtil.to_base64(cx._user), __import__('fan.auth.AuthUtil', fromlist=['AuthUtil']).AuthUtil.to_base64(ObjUtil.coerce(cx._pass_, "sys::Obj"))], "sys::Str", "sys::Str"))

    def on_server(self, cx: 'AuthServerContext', msg: 'AuthMsg') -> 'AuthMsg':
        if ObjUtil.equals(msg._scheme, "hello"):
            return ObjUtil.coerce(__import__('fan.auth.AuthMsg', fromlist=['AuthMsg']).AuthMsg.from_str(self._name), "auth::AuthMsg")
        given = __import__('fan.auth.AuthUtil', fromlist=['AuthUtil']).AuthUtil.from_base64(ObjUtil.coerce(msg.param("password"), "sys::Str"))
        if not cx.auth_secret(given):
            raise __import__('fan.auth.AuthErr', fromlist=['AuthErr']).AuthErr.make_invalid_password()
        auth_token = cx.login()
        return __import__('fan.auth.AuthMsg', fromlist=['AuthMsg']).AuthMsg.make(self._name, sys.Map.from_literal(["authToken"], [auth_token], "sys::Str", "sys::Str"))


# Type metadata registration for reflection
from fan.sys.Param import Param
from fan.sys.Slot import FConst
_t = sys.Type.find('auth::PlaintextScheme')
_t.tf_({}, 8194, [], 'auth::AuthScheme')
_t.am_('make', 8196, 'sys::Void', [], {})
_t.am_('makeScheme', 4100, 'sys::Void', [Param('name', sys.Type.find('sys::Str'), False)], {})
_t.am_('onClient', 271360, 'auth::AuthMsg', [Param('cx', sys.Type.find('auth::AuthClientContext'), False), Param('msg', sys.Type.find('auth::AuthMsg'), False)], {})
_t.am_('onServer', 271360, 'auth::AuthMsg', [Param('cx', sys.Type.find('auth::AuthServerContext'), False), Param('msg', sys.Type.find('auth::AuthMsg'), False)], {})
