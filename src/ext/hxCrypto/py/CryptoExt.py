#
# hxCrypto::CryptoExt - Python native implementation
#
# ============================================================================
# CRYPTO EXTENSION FOR PYTHON
# ============================================================================
#
# This is a Python-native implementation of CryptoExt that replaces the
# transpiled version. The transpiled version contains Java FFI calls
# (java.lang.System.setProperty) that don't apply to Python.
#
# The Java FFI calls set JVM truststore properties for SSL, which is
# JVM-specific. In Python, SSL/TLS is configured through:
# - ssl module (stdlib)
# - requests library (with certifi)
# - SocketConfig for timeout configuration
#
# ============================================================================

import sys as sys_module
sys_module.path.insert(0, '.')

from fan import sys
from fan.hx.ExtObj import ExtObj
from fan.sys.ObjUtil import ObjUtil
from fan.hx.ICryptoExt import ICryptoExt


class CryptoExt(ICryptoExt, ExtObj):
    """Python implementation of hxCrypto::CryptoExt.

    Manages cryptographic services for Haxall including:
    - KeyStore management via CryptoKeyStore
    - HTTPS key configuration
    - SocketConfig truststore setup
    """

    @staticmethod
    def make():
        """Factory method."""
        return CryptoExt()

    def __init__(self):
        super().__init__()
        self._dir_ = None
        self._keystore = None

        # Create crypto directory
        self._dir_ = self.sys_().var_dir().plus(sys.Uri.from_str("crypto/")).create()

        # Create keystore using Python-native CryptoKeyStore
        from fan.hxCrypto.CryptoKeyStore import CryptoKeyStore
        self._keystore = CryptoKeyStore.make(
            self.rt().exts().actor_pool(),
            self._dir_,
            self.log(),
            CryptoExt.actor_timeout(self)
        )

    def dir_(self, _val_=None):
        """Get or set the crypto directory."""
        if _val_ is None:
            return self._dir_
        else:
            self._dir_ = _val_

    def keystore(self, _val_=None):
        """Get or set the keystore."""
        if _val_ is None:
            return self._keystore
        else:
            self._keystore = _val_

    def actor_timeout(self):
        """Get the actor timeout from settings."""
        val = ObjUtil.as_(self.settings().get("actorTimeout"), "haystack::Number")
        if val is not None and val.is_duration():
            return ObjUtil.coerce(val.to_duration(), "sys::Duration")
        return sys.Duration.make(60000000000)  # 60 seconds

    def https_key(self, checked=True):
        """Get the HTTPS key store entry.

        Args:
            checked: If True, raise error if not found

        Returns:
            KeyStore with HTTPS entry, or None if not found and not checked
        """
        from fan.crypto.Crypto import Crypto as PyCrypto

        entry = ObjUtil.as_(self._keystore.get("https", False), "crypto::PrivKeyEntry")
        if entry is not None:
            return PyCrypto.cur().load_key_store().set_(
                "https",
                ObjUtil.coerce(entry, "crypto::KeyStoreEntry")
            )

        if checked:
            raise sys.ArgErr.make("https key not found")
        return None

    def host_key_pair(self):
        """Get the host key pair.

        REQUIRES: cryptography library for KeyPair support.
        """
        return self.host_key().key_pair()

    def host_key(self):
        """Get the host private key entry."""
        return self._keystore.host_key()

    def read_buf(self):
        """Read the keystore as a buffer."""
        return self._keystore.read_buf()

    def write_buf(self, buf):
        """Write a buffer to the keystore."""
        self._keystore.write_buf(buf)
        return

    def on_start(self):
        """Extension startup hook.

        In Java, this sets JVM system properties for SSL truststore.
        In Python, we just configure SocketConfig with the truststore.
        The Java FFI calls (System.setProperty) are skipped as they
        don't apply to Python's SSL/TLS implementation.
        """
        # Skip if in test mode
        if self.sys_().config()._is_test:
            return

        # Configure SocketConfig with our truststore
        from fan.inet.SocketConfig import SocketConfig

        def configure_socket(it):
            it._truststore = self._keystore

        SocketConfig.set_cur(SocketConfig.make(configure_socket))

        # Note: The Java version also sets these JVM properties:
        #   System.setProperty("javax.net.ssl.trustStoreType", "pkcs12")
        #   System.setProperty("javax.net.ssl.trustStore", keystore.file.osPath)
        #   System.setProperty("javax.net.ssl.trustStorePassword", "changeit")
        #
        # These are JVM-specific and don't apply to Python.
        # Python's ssl module uses certifi or OS certificate stores.
        # When the 'cryptography' library is added, we can configure
        # SSL contexts directly.
