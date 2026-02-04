#
# Python-native CryptoKeyStore for hxCrypto
#
# ============================================================================
# HXCRYPTO KEYSTORE IMPLEMENTATION
# ============================================================================
#
# This module provides a Python-native implementation of hxCrypto::CryptoKeyStore
# that replaces the transpiled version. The transpiled version contains JVM-specific
# code paths (loading cacerts from java.home, etc.) that don't apply to Python.
#
# WHAT'S FULLY IMPLEMENTED (No Dependencies Required)
# ---------------------------------------------------
# - In-memory keystore operations (add, remove, get, list aliases)
# - Case-insensitive alias lookups
# - PrivKeyEntry and TrustEntry management
# - KeyStore interface compliance
# - Actor-based message handling pattern (simplified for Python)
#
# WHAT REQUIRES THE `cryptography` LIBRARY
# ----------------------------------------
# The following features are stubbed until the cryptography dependency is added:
#
# 1. JVM Certificate Import (initJvm/findJvmCerts)
#    - Fantom/Java loads trusted CA certs from JRE's cacerts
#    - In Python, we could load from certifi or OS cert stores
#    - Implementation path: Use cryptography.x509 to parse certs
#
# 2. Host Key Generation (initHostKey)
#    - Fantom auto-generates a self-signed "host" certificate
#    - Requires RSA key generation and X.509 certificate creation
#    - Implementation path: Use cryptography.hazmat.primitives.asymmetric
#
# 3. PKCS12 File Persistence
#    - The keystore.p12 file format requires PKCS12 serialization
#    - Implementation path: Use cryptography.hazmat.primitives.serialization
#
# 4. Backup Operations
#    - Currently no-op since we don't persist to files
#
# IMPLICATIONS FOR HAXALL
# -----------------------
# Without the cryptography library:
# - HTTPS is not available (no host key for TLS)
# - HTTP-only mode is required
# - No persistent keystore across restarts
# - No imported CA certificates for outbound TLS verification
#
# TO ADD FULL SUPPORT:
# -------------------
# 1. Add `cryptography` to pyproject.toml dependencies
# 2. Implement init_host_key() using:
#    - cryptography.hazmat.primitives.asymmetric.rsa for key generation
#    - cryptography.x509 for self-signed certificate creation
# 3. Implement file persistence using:
#    - cryptography.hazmat.primitives.serialization.pkcs12
# 4. Optionally import system CA certs using:
#    - certifi package or OS certificate stores
#
# ============================================================================

from fan.sys.Obj import Obj
from fan.sys.List import List
from fan.sys.Map import Map
from fan.sys.Err import Err, ArgErr, UnsupportedErr


class CryptoKeyStore(Obj):
    """Python implementation of hxCrypto::CryptoKeyStore.

    This replaces the transpiled CryptoKeyStore which contains JVM-specific
    code for loading Java cacerts and requires JCE for key generation.

    The keystore is fully functional for in-memory operations. File persistence
    and host key generation require the cryptography library.
    """

    @staticmethod
    def make(pool, dir_, log, timeout=None):
        """Factory method matching Fantom signature.

        Args:
            pool: ActorPool for async operations
            dir_: Directory for keystore file
            log: Log instance for messages
            timeout: Operation timeout (default 1min)

        Returns:
            New CryptoKeyStore instance
        """
        return CryptoKeyStore(pool, dir_, log, timeout)

    def __init__(self, pool, dir_, log, timeout=None):
        """Initialize the keystore.

        Args:
            pool: ActorPool for async operations
            dir_: Directory for keystore file
            log: Log instance for messages
            timeout: Operation timeout
        """
        super().__init__()
        self._pool = pool
        self._dir = dir_
        self._log = log
        self._timeout = timeout
        self._entries = {}  # alias -> KeyStoreEntry
        self._format = "PyKeyStore"

        # Compute file path
        self._file = CryptoKeyStore.to_file(dir_)

        # Attempt to load existing keystore
        if self._file.exists():
            self._load_from_file()

        # Initialize JVM certs (stubbed - requires cryptography for cert parsing)
        updated_jvm = self._init_jvm()

        # Initialize host key (stubbed - requires cryptography for key generation)
        updated_host = self._init_host_key()

        # Log status
        if not updated_jvm and not updated_host:
            log.info(
                "CryptoKeyStore: Python mode - "
                "host key generation requires 'cryptography' library"
            )

        # Autosave and backup if updated (stubbed since we don't persist)
        if updated_jvm or updated_host:
            self._autosave()
            self._backup()

    @staticmethod
    def to_file(dir_):
        """Get the keystore file path.

        Args:
            dir_: Directory containing the keystore

        Returns:
            File pointing to keystore.p12
        """
        from fan.sys.Uri import Uri
        return dir_.plus(Uri.from_str("keystore.p12"), False)

    @staticmethod
    def find_jvm_certs():
        """Find JVM trusted certificates file.

        In Python, we don't have JVM certs. This method exists for
        API compatibility with the Fantom version.

        FUTURE: Could return path to certifi bundle or OS cert store.

        Returns:
            File pointing to non-existent path (no JVM in Python)
        """
        from fan.sys.File import File
        # Return a non-existent file - caller should check exists()
        return File.os("/no-jvm-certs-in-python/lib/security/cacerts")

    def _load_from_file(self):
        """Load keystore from PKCS12 file.

        REQUIRES: cryptography library for PKCS12 parsing.
        Currently a no-op that logs a message.
        """
        self._log.debug(
            f"CryptoKeyStore: Cannot load {self._file} - "
            "PKCS12 parsing requires 'cryptography' library"
        )

    def _init_jvm(self):
        """Initialize JVM trusted certificates.

        In the Java version, this loads CA certificates from the JRE's
        cacerts file. In Python:
        - We don't have JVM certs
        - FUTURE: Could load from certifi or OS cert stores

        REQUIRES: cryptography library for X.509 certificate parsing.

        Returns:
            False (no updates in Python mode)
        """
        # In Python, we skip JVM cert loading
        # FUTURE: Load from certifi or OS trust store
        return False

    def _init_host_key(self):
        """Initialize the host key pair for TLS.

        The host key is a self-signed certificate used for HTTPS.
        In the Java version, this generates an RSA key pair and
        creates a self-signed certificate.

        REQUIRES: cryptography library for RSA key generation and
        X.509 certificate creation.

        Returns:
            False (no updates - key generation not available)
        """
        # Check if host key already exists
        if self.get("host", False) is not None:
            return False

        # Without cryptography library, we can't generate keys
        self._log.debug(
            "CryptoKeyStore: Cannot generate host key - "
            "requires 'cryptography' library for RSA key generation"
        )
        return False

    # =========================================================================
    # KeyStore Interface - Fully Implemented
    # =========================================================================

    def format(self):
        """Get the format that this keystore stores entries in."""
        return self._format

    def aliases(self):
        """Get all the aliases in the key store."""
        return List.from_literal(list(self._entries.keys()), "sys::Str")

    def size(self):
        """Get the number of entries in the key store."""
        return len(self._entries)

    def get(self, alias, checked=True):
        """Get the entry with the given alias.

        Lookup is case-insensitive per the KeyStore contract.

        Args:
            alias: Entry alias
            checked: If True, throw error when not found

        Returns:
            KeyStoreEntry or None
        """
        alias_lower = alias.lower()
        for key, value in self._entries.items():
            if key.lower() == alias_lower:
                return value
        if checked:
            raise Err.make(f"KeyStore entry not found: {alias}")
        return None

    def get_trust(self, alias, checked=True):
        """Get a TrustEntry from the keystore."""
        return self.get(alias, checked)

    def get_priv_key(self, alias, checked=True):
        """Get a PrivKeyEntry from the keystore."""
        return self.get(alias, checked)

    def contains_alias(self, alias):
        """Check if the keystore contains an alias."""
        return self.get(alias, False) is not None

    def set_priv_key(self, alias, priv, chain):
        """Add a private key entry.

        Args:
            alias: Entry alias
            priv: Private key
            chain: Certificate chain

        Returns:
            self for chaining
        """
        entry = _PyPrivKeyEntry(priv, chain)
        self._entries[alias] = entry
        self._autosave()
        return self

    def set_trust(self, alias, cert):
        """Add a trust entry.

        Args:
            alias: Entry alias
            cert: Trusted certificate

        Returns:
            self for chaining
        """
        entry = _PyTrustEntry(cert)
        self._entries[alias] = entry
        self._autosave()
        return self

    def set_(self, alias, entry):
        """Set an entry by alias.

        Args:
            alias: Entry alias
            entry: KeyStoreEntry to store

        Returns:
            self for chaining
        """
        self._entries[alias] = entry
        self._autosave()
        return self

    def remove(self, alias):
        """Remove an entry by alias.

        Args:
            alias: Entry alias to remove
        """
        alias_lower = alias.lower()
        for key in list(self._entries.keys()):
            if key.lower() == alias_lower:
                del self._entries[key]
                self._autosave()
                return

    def save(self, out, options=None):
        """Save the keystore to an output stream.

        REQUIRES: cryptography library for PKCS12 serialization.
        Currently a no-op.

        Args:
            out: Output stream
            options: Save options
        """
        self._log.debug(
            "CryptoKeyStore.save(): No-op - "
            "PKCS12 serialization requires 'cryptography' library"
        )

    # =========================================================================
    # CryptoKeyStore-specific Methods
    # =========================================================================

    def file(self):
        """Get the backing file for the keystore."""
        return self._file

    def backup(self):
        """Create a backup of the keystore file.

        REQUIRES: File persistence (which requires cryptography).
        Returns the backup file path.
        """
        return self._backup()

    def _backup(self):
        """Internal backup implementation."""
        # No-op in Python mode - we don't have file persistence
        from fan.sys.Uri import Uri
        backup_file = self._file.parent().plus(
            Uri.from_str(f"{self._file.basename()}-bkup.{self._file.ext()}"),
            False
        )
        return backup_file

    def host_key(self):
        """Get the host key pair for TLS.

        Returns the PrivKeyEntry for alias "host", or None if not available.
        Without the cryptography library, the host key cannot be auto-generated.

        Returns:
            PrivKeyEntry or None
        """
        return self.get("host", False)

    def read_buf(self):
        """Read the keystore file into a buffer.

        REQUIRES: File persistence.
        Returns empty buffer in Python mode.
        """
        from fan.sys.Buf import Buf
        # Can't read - no file persistence
        return Buf.make(0)

    def write_buf(self, buf):
        """Write a buffer to the keystore file.

        REQUIRES: cryptography library for PKCS12 parsing.
        Currently a no-op.

        Args:
            buf: Buffer containing keystore data

        Returns:
            self for chaining
        """
        self._log.debug(
            "CryptoKeyStore.writeBuf(): No-op - "
            "PKCS12 parsing requires 'cryptography' library"
        )
        return self

    def _autosave(self):
        """Save the keystore after modifications.

        REQUIRES: cryptography library for PKCS12 serialization.
        Currently a no-op.
        """
        # No-op in Python mode - we don't persist
        pass


# =============================================================================
# KeyStore Entry Classes - Fully Implemented
# =============================================================================

class _PyKeyStoreEntry(Obj):
    """Base class for keystore entries.

    Implements the KeyStoreEntry mixin from crypto pod.
    """

    def __init__(self):
        super().__init__()
        self._attrs = {}

    def attrs(self):
        """Get entry attributes.

        Returns:
            Immutable Map[Str,Str]
        """
        m = Map.make_with_type("sys::Str", "sys::Str")
        for k, v in self._attrs.items():
            m.set_(k, v)
        return m.to_immutable()


class _PyPrivKeyEntry(_PyKeyStoreEntry):
    """Private key entry storing a key and certificate chain.

    Implements the PrivKeyEntry mixin from crypto pod.
    """

    def __init__(self, priv_key, cert_chain):
        """Create a private key entry.

        Args:
            priv_key: Private key object
            cert_chain: List of certificates (end entity first)
        """
        super().__init__()
        self._priv = priv_key
        self._chain = cert_chain

    def priv(self):
        """Get the private key."""
        return self._priv

    def cert_chain(self):
        """Get the certificate chain."""
        return self._chain

    def cert(self):
        """Get the end entity certificate (first in chain)."""
        if self._chain and len(self._chain) > 0:
            return self._chain[0]
        return None

    def pub(self):
        """Get the public key from the certificate."""
        cert = self.cert()
        if cert and hasattr(cert, 'pub'):
            return cert.pub()
        return None

    def key_pair(self):
        """Get the KeyPair for this entry.

        REQUIRES: cryptography library.
        """
        raise UnsupportedErr.make(
            "KeyPair requires the 'cryptography' library"
        )


class _PyTrustEntry(_PyKeyStoreEntry):
    """Trusted certificate entry.

    Implements the TrustEntry mixin from crypto pod.
    """

    def __init__(self, cert):
        """Create a trust entry.

        Args:
            cert: Trusted certificate
        """
        super().__init__()
        self._cert = cert

    def cert(self):
        """Get the trusted certificate."""
        return self._cert
