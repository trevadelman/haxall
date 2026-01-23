"""
Haystack Python API

A thin wrapper around the transpiled Fantom runtime for working with
Haystack servers. Inspired by the phable library's clean API design.

Usage:
    from haystack import open_haystack_client, Marker, Number, Ref, DateRange
    from datetime import timedelta

    with open_haystack_client(uri, username, password) as client:
        sites = client.read_all("site")
        for row in sites:
            print(row.get("dis", "Unknown"))

        # History reads - use .to_py() to convert Fantom dates
        point = client.read("point and his")
        end_date = point["hisEnd"].to_py().date()  # Fantom DateTime -> Python date
        history = client.his_read_by_id(point["id"], DateRange(end_date - timedelta(days=7), end_date))
        df = history.to_pandas()
"""

from __future__ import annotations

import sys as _sys
import os as _os
from contextlib import contextmanager
from dataclasses import dataclass
from datetime import date, datetime
from typing import Any, Generator

# Add gen/py to path if not already present
_repo_root = _os.path.dirname(_os.path.dirname(_os.path.dirname(
    _os.path.dirname(_os.path.dirname(_os.path.dirname(__file__))))))
_gen_py = _os.path.join(_repo_root, 'gen', 'py')
if _gen_py not in _sys.path:
    _sys.path.insert(0, _gen_py)

# Import haystack module to trigger patches (to_pandas, to_polars, __iter__, etc.)
import fan.haystack


# =============================================================================
# Data Types (re-exports + DateRange helper)
# =============================================================================

from fan.xeto.Ref import Ref
from fan.xeto.Marker import Marker
from fan.haystack.Number import Number
from fan.haystack.Coord import Coord
from fan.haystack.NA import NA
from fan.haystack.Remove import Remove
from fan.haystack.Grid import Grid


@dataclass(frozen=True)
class DateRange:
    """Date range for history queries.

    Example:
        >>> from datetime import date, timedelta
        >>> end = date.today()
        >>> start = end - timedelta(days=7)
        >>> history = client.his_read_by_id(point_id, DateRange(start, end))
    """
    start: date
    end: date

    def __str__(self):
        return f"{self.start.isoformat()},{self.end.isoformat()}"


# =============================================================================
# HaystackClient
# =============================================================================

class HaystackClient:
    """Client for connecting to Project Haystack servers.

    Use `open_haystack_client()` context manager for automatic cleanup.
    """

    def __init__(self, client):
        """Wrap the transpiled Fan client."""
        self._client = client

    @classmethod
    def open(cls, uri: str, username: str, password: str) -> "HaystackClient":
        """Open a connection to the server."""
        from fan.haystack.Client import Client as FanClient
        from fan.sys.Uri import Uri

        fan_uri = Uri.from_str(uri)
        fan_client = FanClient.open_(fan_uri, username, password)
        return cls(fan_client)

    def close(self):
        """Close the connection."""
        try:
            self._client.close()
        except:
            pass

    @property
    def uri(self) -> str:
        """Get the server URI."""
        return str(self._client.uri())

    def about(self) -> dict[str, Any]:
        """Query basic information about the server."""
        about_dict = self._client.about()
        result = {}
        about_dict.each(lambda v, k: result.__setitem__(k, v))
        return result

    def read(self, filter: str, checked: bool = True) -> dict[str, Any] | None:
        """Read single record matching filter."""
        row = self._client.read(filter, checked)
        if row is None:
            return None
        return self._row_to_dict(row)

    def read_all(self, filter: str) -> Grid:
        """Read all records matching filter."""
        return self._client.read_all(filter)

    def read_by_id(self, id: Ref, checked: bool = True) -> dict[str, Any] | None:
        """Read record by ID."""
        row = self._client.read_by_id(id, checked)
        if row is None:
            return None
        return self._row_to_dict(row)

    def his_read_by_id(self, id: Ref, range: date | DateRange | str) -> Grid:
        """Read history for a point.

        Args:
            id: Point Ref
            range: Date, DateRange, or range string (e.g., "2024-01-01,2024-01-07")

        Returns:
            Grid with history data (ts, val columns)
        """
        from fan.haystack.Etc import Etc
        from fan.sys.List import List

        # Convert range to string
        if isinstance(range, date):
            range_str = range.isoformat()
        else:
            range_str = str(range)

        req = Etc.make_lists_grid(
            None,
            List.from_list(["id", "range"]),
            None,
            List.from_list([List.from_list([id, range_str])])
        )

        return self._client.call("hisRead", req)

    def call(self, op: str, grid: Grid | None = None) -> Grid:
        """Call a server operation."""
        if grid is None:
            from fan.haystack.Etc import Etc
            grid = Etc.empty_grid()
        return self._client.call(op, grid)

    def _row_to_dict(self, row) -> dict[str, Any]:
        """Convert a Row to a Python dict."""
        result = {}
        row.each(lambda v, k: result.__setitem__(k, v))
        return result


# =============================================================================
# HaxallClient (extends HaystackClient with Axon eval)
# =============================================================================

class HaxallClient(HaystackClient):
    """Client for Haxall/SkySpark servers with Axon eval support."""

    @classmethod
    def open(cls, uri: str, username: str, password: str) -> "HaxallClient":
        """Open a connection to a Haxall server."""
        from fan.haystack.Client import Client as FanClient
        from fan.sys.Uri import Uri

        fan_uri = Uri.from_str(uri)
        fan_client = FanClient.open_(fan_uri, username, password)
        return cls(fan_client)

    def eval(self, expr: str) -> Grid:
        """Evaluate an Axon expression."""
        return self._client.eval(expr)


# =============================================================================
# Context Managers
# =============================================================================

@contextmanager
def open_haystack_client(
    uri: str,
    username: str,
    password: str,
) -> Generator[HaystackClient, None, None]:
    """Context manager for Haystack client connections.

    Example:
        >>> with open_haystack_client(uri, "su", "password") as client:
        ...     sites = client.read_all("site")
    """
    client = HaystackClient.open(uri, username, password)
    try:
        yield client
    finally:
        client.close()


@contextmanager
def open_haxall_client(
    uri: str,
    username: str,
    password: str,
) -> Generator[HaxallClient, None, None]:
    """Context manager for Haxall client connections.

    Example:
        >>> with open_haxall_client(uri, "su", "password") as client:
        ...     result = client.eval("readAll(site)")
    """
    client = HaxallClient.open(uri, username, password)
    try:
        yield client
    finally:
        client.close()


# =============================================================================
# Module exports
# =============================================================================

__all__ = [
    # Clients
    "HaystackClient",
    "HaxallClient",
    "open_haystack_client",
    "open_haxall_client",
    # Data types
    "Ref",
    "Marker",
    "Number",
    "Coord",
    "NA",
    "Remove",
    "Grid",
    "DateRange",
]
