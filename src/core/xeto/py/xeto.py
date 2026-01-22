"""
Xeto Python API - Pythonic wrapper for Fantom/Haystack/Xeto

This module provides a clean, Pythonic interface to the transpiled Fantom
runtime for working with Haystack data and Xeto schemas.

Usage:
    from xeto import Namespace, Ref, Marker, Number, Coord, Grid

    # Create a namespace with libs
    ns = Namespace(['sys', 'ph'])

    # Create haystack values using Python-friendly constructors
    site = {
        "id": Ref("site-1", "Building 1"),
        "site": Marker(),
        "area": Number(10000, "ft²"),
        "geoCoord": Coord(37.7749, -122.4194),
    }

    # Validate against Xeto schema
    if ns.fits(site, 'ph::Site'):
        print("Valid site!")

    # Convert Grid to Python list of dicts
    results = grid.to_py(deep=True)
"""

import sys as _sys
import os as _os

# Add gen/py to path if not already present
# This assumes the python-fantom repo structure
_repo_root = _os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.dirname(_os.path.dirname(__file__))))))
_gen_py = _os.path.join(_repo_root, 'gen', 'py')
if _gen_py not in _sys.path:
    _sys.path.insert(0, _gen_py)

# Import haystack module to trigger patches (must happen first)
import fan.haystack

from fan.sys.ObjUtil import ObjUtil as _ObjUtil

# =============================================================================
# Core Haystack Value Types
# =============================================================================

class Ref:
    """Haystack reference (pointer to a record by id).

    Examples:
        >>> Ref("site-1")
        @site-1
        >>> Ref("site-1", "Building 1")
        @site-1 "Building 1"
        >>> Ref.from_py({'id': 'site-1', 'dis': 'Building 1'})
        @site-1 "Building 1"
    """
    _cls = None

    @staticmethod
    def _get_cls():
        if Ref._cls is None:
            from fan.xeto.Ref import Ref as _FanRef
            Ref._cls = _FanRef
        return Ref._cls

    def __new__(cls, id_: str, dis: str = None):
        """Create a new Ref.

        Args:
            id_: The unique identifier string
            dis: Optional display name
        """
        return cls._get_cls().make(id_, dis)

    @staticmethod
    def from_py(val):
        """Create Ref from Python dict or string.

        Args:
            val: str (id only) or dict with 'id' and optional 'dis' keys
        """
        return Ref._get_cls().from_py(val)


class Number:
    """Haystack number with optional unit.

    Examples:
        >>> Number(72.5)
        72.5
        >>> Number(72.5, "fahrenheit")
        72.5°F
        >>> Number(100, "%")
        100%
    """
    _cls = None

    @staticmethod
    def _get_cls():
        if Number._cls is None:
            from fan.haystack.Number import Number as _FanNumber
            Number._cls = _FanNumber
        return Number._cls

    def __new__(cls, val: float, unit: str = None):
        """Create a new Number.

        Args:
            val: The numeric value
            unit: Optional unit string (e.g., "fahrenheit", "kW", "%")
        """
        return cls._get_cls().from_py(val, unit)

    @staticmethod
    def from_py(val, unit=None):
        """Create Number from Python float or tuple.

        Args:
            val: float or tuple(val, unit_str)
            unit: Optional unit string (ignored if val is tuple)
        """
        return Number._get_cls().from_py(val, unit)


class Coord:
    """Geographic coordinate (latitude/longitude).

    Examples:
        >>> Coord(37.7749, -122.4194)
        C(37.7749,-122.4194)
    """
    _cls = None

    @staticmethod
    def _get_cls():
        if Coord._cls is None:
            from fan.haystack.Coord import Coord as _FanCoord
            Coord._cls = _FanCoord
        return Coord._cls

    def __new__(cls, lat: float, lng: float):
        """Create a new Coord.

        Args:
            lat: Latitude (-90 to 90)
            lng: Longitude (-180 to 180)
        """
        return cls._get_cls().make(lat, lng)

    @staticmethod
    def from_py(val):
        """Create Coord from Python tuple or dict.

        Args:
            val: tuple(lat, lng) or dict with 'lat'/'lng' keys
        """
        return Coord._get_cls().from_py(val)


class Marker:
    """Marker tag singleton (indicates presence of a tag).

    Examples:
        >>> site = {"site": Marker()}  # Tag the record as a site
    """
    _instance = None

    def __new__(cls):
        """Return the Marker singleton."""
        if Marker._instance is None:
            from fan.xeto.Marker import Marker as _FanMarker
            Marker._instance = _FanMarker.val()
        return Marker._instance


class NA:
    """Not Available singleton (explicitly missing data).

    Examples:
        >>> point["curVal"] = NA()  # Sensor value not available
    """
    _instance = None

    def __new__(cls):
        """Return the NA singleton."""
        if NA._instance is None:
            from fan.haystack.NA import NA as _FanNA
            NA._instance = _FanNA.val()
        return NA._instance


class Remove:
    """Remove tag singleton (used in diffs to indicate tag removal).

    Examples:
        >>> diff = {"oldTag": Remove()}  # Remove the tag
    """
    _instance = None

    def __new__(cls):
        """Return the Remove singleton."""
        if Remove._instance is None:
            from fan.haystack.Remove import Remove as _FanRemove
            Remove._instance = _FanRemove.val()
        return Remove._instance


# =============================================================================
# Dict / Grid Utilities
# =============================================================================

def to_dict(py_dict: dict):
    """Convert Python dict to Haystack Dict.

    Values are automatically converted:
    - Python primitives (str, int, float, bool) pass through
    - Use Ref(), Number(), Marker(), etc. for haystack types

    Args:
        py_dict: Python dictionary

    Returns:
        haystack::Dict

    Example:
        >>> d = to_dict({"id": Ref("site-1"), "site": Marker(), "dis": "Building"})
    """
    from fan.haystack.Etc import Etc
    from fan.sys.Map import Map
    # Convert Python dict to Fantom Map first
    fantom_map = Map.from_dict(py_dict)
    return Etc.dict_from_map(fantom_map)


def to_grid(rows: list, meta: dict = None):
    """Convert list of Python dicts to Haystack Grid.

    Args:
        rows: List of Python dicts (each dict is a row)
        meta: Optional grid-level metadata dict

    Returns:
        haystack::Grid

    Example:
        >>> grid = to_grid([
        ...     {"id": Ref("site-1"), "dis": "Building 1"},
        ...     {"id": Ref("site-2"), "dis": "Building 2"},
        ... ])
    """
    from fan.haystack.GridBuilder import GridBuilder
    from fan.sys.List import List

    # Collect all column names
    col_names = set()
    for row in rows:
        col_names.update(row.keys())
    col_names = sorted(col_names)

    # Build grid
    gb = GridBuilder.make()

    # Add metadata if provided
    if meta:
        gb.set_meta(to_dict(meta))

    # Add columns
    for name in col_names:
        gb.add_col(name)

    # Add rows
    for row in rows:
        vals = List.from_list([row.get(name) for name in col_names])
        gb.add_row(vals)

    return gb.to_grid()


# =============================================================================
# Namespace (Xeto Schema)
# =============================================================================

class Namespace:
    """Xeto namespace for schema validation and data manipulation.

    A namespace loads Xeto libraries and provides schema validation
    for haystack data.

    Example:
        >>> ns = Namespace(['sys', 'ph'])
        >>> ns.fits({"site": Marker()}, 'ph::Site')
        True
    """

    def __init__(self, libs: list = None):
        """Create a namespace with the given libraries.

        Args:
            libs: List of library names to load (e.g., ['sys', 'ph', 'phIoT'])
        """
        from fan.xeto.XetoEnv import XetoEnv
        from fan.sys.List import List

        self._libs = libs or ['sys']
        env = XetoEnv.cur()
        lib_names = List.from_literal(self._libs, 'sys::Str')
        self._ns = env.create_namespace_from_names(lib_names)

    @property
    def wrapped(self):
        """Access the underlying Fantom namespace object."""
        return self._ns

    def spec(self, qname: str):
        """Get a spec by qualified name.

        Args:
            qname: Qualified spec name (e.g., 'ph::Site', 'sys::Str')

        Returns:
            xeto::Spec or None
        """
        try:
            return self._ns.spec(qname)
        except Exception:
            return None

    def fits(self, val, spec) -> bool:
        """Check if a value fits a spec.

        Args:
            val: Value to check (dict, Haystack type, etc.)
            spec: Spec name string or Spec object

        Returns:
            True if val fits spec

        Example:
            >>> ns.fits({"site": Marker(), "dis": "Building"}, 'ph::Site')
            True
        """
        # Convert dict to haystack Dict if needed
        if isinstance(val, dict):
            val = to_dict(val)

        # Convert spec string to Spec object if needed
        if isinstance(spec, str):
            spec = self.spec(spec)
            if spec is None:
                return False

        return self._ns.fits(val, spec)

    def spec_of(self, val):
        """Get the most specific spec that matches a value.

        Args:
            val: Value to analyze

        Returns:
            xeto::Spec or None
        """
        if isinstance(val, dict):
            val = to_dict(val)
        return self._ns.spec_of(val)


# =============================================================================
# Convenience Functions
# =============================================================================

def parse_filter(s: str):
    """Parse a Haystack filter string.

    Args:
        s: Filter string (e.g., 'site and area > 1000')

    Returns:
        haystack::Filter

    Example:
        >>> f = parse_filter('site and area > 1000')
        >>> f.matches(some_dict)
    """
    from fan.haystack.Filter import Filter
    return Filter.from_str(s)


def parse_zinc(s: str):
    """Parse a Zinc-encoded string.

    Args:
        s: Zinc string

    Returns:
        Parsed value (Grid, Dict, or scalar)
    """
    from fan.haystack.ZincReader import ZincReader
    from fan.sys.Str import Str
    return ZincReader.make(Str.in_(s)).read_val()


def to_zinc(val) -> str:
    """Encode a value to Zinc format.

    Args:
        val: Value to encode

    Returns:
        Zinc string
    """
    from fan.haystack.ZincWriter import ZincWriter
    return ZincWriter.val_to_str(val)


# =============================================================================
# Module initialization
# =============================================================================

__all__ = [
    # Value types
    'Ref',
    'Number',
    'Coord',
    'Marker',
    'NA',
    'Remove',
    # Conversion utilities
    'to_dict',
    'to_grid',
    # Namespace
    'Namespace',
    # Parsing
    'parse_filter',
    'parse_zinc',
    'to_zinc',
]
