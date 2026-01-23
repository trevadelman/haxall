# Hand-written haystack module for Python
# Contains native implementations that mirror the ES/JavaScript versions

# Import fan.sys FIRST to trigger import caching optimization.
# The sys pod's __init__.py installs a cached __import__ that reduces
# xeto namespace creation from ~25s to ~6s.
import fan.sys

#################################################################
# Number patches
#################################################################

def _patch_number():
    from fan.haystack.Number import Number
    from fan.sys.ObjUtil import ObjUtil
    from fan.sys.Duration import Duration

    # Fix negative duration unit selection
    def _make_duration_body_fixed(self, dur, unit=None):
        """Fixed version that uses absolute value for magnitude comparison."""
        if unit is None:
            # Use absolute value for magnitude comparison (fixes negative duration unit selection)
            abs_dur = dur.abs_()
            if ObjUtil.compare_lt(abs_dur, Duration.make(1000000000)):
                unit = Number.ms()
            elif ObjUtil.compare_lt(abs_dur, Duration.make(60000000000)):
                unit = Number.sec()
            elif ObjUtil.compare_lt(abs_dur, Duration.make(3600000000000)):
                unit = Number.mins()
            elif ObjUtil.compare_lt(abs_dur, Duration.make(86400000000000)):
                unit = Number.hr()
            else:
                unit = Number.day()

        self._float_ = ((ObjUtil.to_float(ObjUtil.coerce(dur.ticks(), "sys::Num")) / 1.0E9) / unit.scale())
        self._unit_ref = unit

    Number._make_duration_body = _make_duration_body_fixed

    # Python interop: to_py() / from_py()
    def number_to_py(self, with_unit=False):
        """Convert to native Python float or tuple.

        Args:
            with_unit: If True, return (val, unit_symbol) tuple. If False, return just float.

        Returns:
            float or tuple(float, str|None)

        Example:
            >>> Number.make(72.5, Unit.from_str("fahrenheit")).to_py()
            72.5
            >>> Number.make(72.5, Unit.from_str("fahrenheit")).to_py(with_unit=True)
            (72.5, 'fahrenheit')
        """
        if with_unit:
            unit_str = self._unit_ref.symbol() if self._unit_ref else None
            return (self._float_, unit_str)
        return self._float_

    def number_from_py(val, unit=None):
        """Create Number from native Python value.

        Args:
            val: Python float, int, or tuple(val, unit_str)
            unit: Optional unit string (ignored if val is tuple)

        Returns:
            haystack::Number

        Example:
            >>> Number.from_py(72.5)
            72.5
            >>> Number.from_py(72.5, "fahrenheit")
            72.5fahrenheit
            >>> Number.from_py((72.5, "fahrenheit"))
            72.5fahrenheit
        """
        from fan.sys.Unit import Unit

        if isinstance(val, tuple):
            val, unit = val

        unit_obj = None
        if unit is not None:
            unit_obj = Unit.from_str(str(unit), False)
            if unit_obj is None:
                unit_obj = Unit.define(str(unit))

        return Number.make(float(val), unit_obj)

    Number.to_py = number_to_py
    Number.from_py = staticmethod(number_from_py)

try:
    _patch_number()
except ImportError:
    pass  # Number not yet loaded


#################################################################
# Coord patches
#################################################################

def _patch_coord():
    from fan.haystack.Coord import Coord

    def coord_to_py(self):
        """Convert to native Python tuple.

        Returns:
            tuple(lat, lng) as floats

        Example:
            >>> Coord.make(37.7749, -122.4194).to_py()
            (37.7749, -122.4194)
        """
        return (self.lat(), self.lng())

    def coord_from_py(val):
        """Create Coord from native Python tuple or values.

        Args:
            val: tuple(lat, lng) or dict with 'lat'/'lng' keys

        Returns:
            haystack::Coord

        Example:
            >>> Coord.from_py((37.7749, -122.4194))
            C(37.7749,-122.4194)
        """
        if isinstance(val, dict):
            return Coord.make(float(val['lat']), float(val['lng']))
        return Coord.make(float(val[0]), float(val[1]))

    Coord.to_py = coord_to_py
    Coord.from_py = staticmethod(coord_from_py)

try:
    _patch_coord()
except ImportError:
    pass


#################################################################
# NA patches
#################################################################

def _patch_na():
    from fan.haystack.NA import NA

    def na_to_py(self):
        """Convert to native Python None.

        Returns:
            None

        Example:
            >>> NA.val().to_py()
            None
        """
        return None

    NA.to_py = na_to_py

try:
    _patch_na()
except ImportError:
    pass


#################################################################
# Grid patches
#################################################################

def _patch_grid():
    from fan.haystack.Grid import Grid

    def grid_to_py(self, deep=False):
        """Convert to native Python list of dicts.

        Args:
            deep: If True, recursively convert nested Fantom types to Python types

        Returns:
            list[dict] - each row as a dict with column names as keys

        Example:
            >>> grid.to_py()
            [{'id': Ref('site-1'), 'dis': 'Building 1'}, ...]
            >>> grid.to_py(deep=True)
            [{'id': 'site-1', 'dis': 'Building 1'}, ...]
        """
        result = []
        cols = self.cols()
        num_cols = cols.size() if callable(cols.size) else cols.size
        col_names = [cols.get(i).name() for i in range(num_cols)]

        num_rows = self.size() if callable(self.size) else self.size
        for i in range(num_rows):
            row = self.get(i)
            row_dict = {}
            for name in col_names:
                try:
                    val = row.get(name)  # Returns None if missing
                except:
                    val = None
                if val is not None:
                    if deep and hasattr(val, 'to_py'):
                        val = val.to_py() if not callable(getattr(val, 'to_py', None)) else val.to_py()
                    row_dict[name] = val
            result.append(row_dict)
        return result

    def grid_to_pandas(self):
        """Convert Grid to pandas DataFrame.

        Requires pandas to be installed: pip install pandas

        Returns:
            pandas.DataFrame with column names from the Grid

        Example:
            >>> df = grid.to_pandas()
            >>> df.head()
        """
        try:
            import pandas as pd
        except ImportError:
            raise ImportError("pandas is required: pip install pandas")

        return pd.DataFrame(self.to_py(deep=True))

    def grid_to_polars(self):
        """Convert Grid to polars DataFrame.

        Requires polars to be installed: pip install polars

        Returns:
            polars.DataFrame with column names from the Grid

        Example:
            >>> df = grid.to_polars()
            >>> df.head()
        """
        try:
            import polars as pl
        except ImportError:
            raise ImportError("polars is required: pip install polars")

        return pl.DataFrame(self.to_py(deep=True))

    Grid.to_py = grid_to_py
    Grid.to_pandas = grid_to_pandas
    Grid.to_polars = grid_to_polars

try:
    _patch_grid()
except ImportError:
    pass


#################################################################
# Ref patches (haystack::Ref is in xeto pod)
#################################################################

def _patch_ref():
    from fan.xeto.Ref import Ref

    def ref_to_py(self, with_dis=False):
        """Convert to native Python string or dict.

        Args:
            with_dis: If True, return dict with 'id' and 'dis' keys. If False, return just id string.

        Returns:
            str or dict

        Example:
            >>> Ref.make("site-1", "Building 1").to_py()
            'site-1'
            >>> Ref.make("site-1", "Building 1").to_py(with_dis=True)
            {'id': 'site-1', 'dis': 'Building 1'}
        """
        if with_dis:
            return {'id': self.id_(), 'dis': self.dis()}
        return self.id_()

    def ref_from_py(val, dis=None):
        """Create Ref from native Python value.

        Args:
            val: Python string (id) or dict with 'id' key
            dis: Optional display string (ignored if val is dict)

        Returns:
            xeto::Ref

        Example:
            >>> Ref.from_py("site-1")
            @site-1
            >>> Ref.from_py("site-1", "Building 1")
            @site-1 "Building 1"
            >>> Ref.from_py({'id': 'site-1', 'dis': 'Building 1'})
            @site-1 "Building 1"
        """
        if isinstance(val, dict):
            return Ref.make(str(val['id']), val.get('dis'))
        return Ref.make(str(val), dis)

    Ref.to_py = ref_to_py
    Ref.from_py = staticmethod(ref_from_py)

try:
    _patch_ref()
except ImportError:
    pass


#################################################################
# Marker patches
#################################################################

def _patch_marker():
    # Marker is typically accessed via haystack.Etc.MARKER or similar
    # Check where it's defined
    try:
        from fan.haystack.Etc import Etc
        # Marker is Etc.MARKER singleton

        class Marker:
            """Marker singleton for Python interop."""
            _instance = None

            @staticmethod
            def val():
                return Etc.MARKER

            def to_py(self):
                return True

            @staticmethod
            def from_py(val):
                return Etc.MARKER if val else None

        # Try to patch Etc.MARKER if it has a class
        marker_val = Etc.MARKER
        if marker_val is not None:
            marker_val.__class__.to_py = lambda self: True

    except (ImportError, AttributeError):
        pass

try:
    _patch_marker()
except ImportError:
    pass
