# Python Developer's Guide

A guide for Python developers using transpiled Fantom libraries (Haystack, Xeto, etc.).

> **Note:** This guide is for Python developers *consuming* Fantom APIs.
> For information on how the transpiler generates Python code, see `design.md`.

---

## Quick Start with xeto.py (Recommended)

The `xeto.py` wrapper module provides a clean, Pythonic API for working with
Haystack data and Xeto schemas. This is the recommended way to use the library.

**Location:** `haxall/src/core/xeto/py/xeto.py`

```python
from xeto import Namespace, Ref, Marker, Number, Coord, to_dict, to_grid, parse_filter

# Create a namespace with xeto libraries
ns = Namespace(['sys', 'ph'])

# Create haystack data using Python-friendly constructors
site = {
    'id': Ref('site-1', 'Building 1'),
    'site': Marker(),
    'area': Number(50000, 'ft²'),
    'geoCoord': Coord(37.7749, -122.4194),
}

# Validate against Xeto schema - Python dicts work directly!
if ns.fits(site, 'ph::Site'):
    print("Valid site!")

# Parse filters
f = parse_filter('site and area > 10000')

# Build grids from Python dicts
grid = to_grid([
    {'id': Ref('site-1'), 'dis': 'Building 1'},
    {'id': Ref('site-2'), 'dis': 'Building 2'},
])

# Convert back to Python
py_rows = grid.to_py(deep=True)  # List of dicts with Python values
```

### xeto.py Value Types

| Type | Usage | Example |
|------|-------|---------|
| `Ref` | Record reference | `Ref('site-1')` or `Ref('site-1', 'Building')` |
| `Number` | Value with unit | `Number(72.5, 'fahrenheit')` or `Number(100)` |
| `Coord` | Geo coordinate | `Coord(37.7749, -122.4194)` |
| `Marker` | Tag marker | `Marker()` (singleton) |
| `NA` | Not available | `NA()` (singleton) |
| `Remove` | Remove tag | `Remove()` (singleton) |

### xeto.py Utilities

| Function | Purpose |
|----------|---------|
| `to_dict(py_dict)` | Convert Python dict to Haystack Dict |
| `to_grid(rows, meta)` | Convert list of dicts to Haystack Grid |
| `parse_filter(s)` | Parse Haystack filter string |
| `parse_zinc(s)` | Parse Zinc-encoded string |
| `to_zinc(val)` | Encode value to Zinc format |

### Converting Fantom Types to Python

All Fantom types support `to_py()` for conversion to native Python types:

```python
# Sys types
datetime_val = fantom_datetime.to_py()  # -> datetime.datetime
date_val = fantom_date.to_py()          # -> datetime.date
time_val = fantom_time.to_py()          # -> datetime.time
duration_val = fantom_dur.to_py()       # -> datetime.timedelta
uri_val = fantom_uri.to_py()            # -> str
buf_val = fantom_buf.to_py()            # -> bytes
range_val = fantom_range.to_py()        # -> range

# Haystack types
num_val = fantom_number.to_py()                    # -> float
num_with_unit = fantom_number.to_py(with_unit=True)  # -> (val, 'unit')
coord_val = fantom_coord.to_py()                   # -> (lat, lng)
ref_val = fantom_ref.to_py()                       # -> str (id only)
ref_full = fantom_ref.to_py(with_dis=True)         # -> {'id': ..., 'dis': ...}
grid_rows = fantom_grid.to_py(deep=True)           # -> list of dicts
```

### Pythonic Grid Operations

Grids support Python protocols for natural iteration and length:

```python
# Iterate over rows (instead of index-based loops)
for row in grid:
    print(row.get("dis"))

# Get length (instead of grid.size())
print(f"Grid has {len(grid)} rows")

# Access rows by index
first_row = grid[0]
last_row = grid[-1]
```

### Pythonic Row Access

Rows support Python dict-like access with defaults:

```python
# Get with default (instead of: row.get("dis") if row.has("dis") else "Unknown")
dis = row.get("dis", "Unknown")

# Dict-style access (raises KeyError if missing)
id = row["id"]

# Iterate over tag names
for key in row:
    print(f"{key}: {row[key]}")
```

### Converting Grids to DataFrames

Grids support direct conversion to pandas and polars DataFrames:

```python
# Convert to pandas DataFrame
df = grid.to_pandas()

# Convert to polars DataFrame
df = grid.to_polars()
```

**Requirements:** Install pandas and/or polars as needed:
```bash
pip install pandas
pip install polars
```

**Example:**
```python
from xeto import Namespace, Ref, Marker, Number, to_grid

# Build a grid
grid = to_grid([
    {'id': Ref('site-1'), 'dis': 'Building 1', 'area': Number(10000)},
    {'id': Ref('site-2'), 'dis': 'Building 2', 'area': Number(25000)},
])

# Convert to pandas
df = grid.to_pandas()
print(df)
#        id         dis     area
# 0  site-1  Building 1  10000.0
# 1  site-2  Building 2  25000.0

# Convert to polars
df = grid.to_polars()
print(df)
# shape: (2, 3)
# ┌────────┬────────────┬─────────┐
# │ id     ┆ dis        ┆ area    │
# │ str    ┆ str        ┆ f64     │
# ╞════════╪════════════╪═════════╡
# │ site-1 ┆ Building 1 ┆ 10000.0 │
# │ site-2 ┆ Building 2 ┆ 25000.0 │
# └────────┴────────────┴─────────┘
```

**Type Conversion:** Both methods use `to_py(deep=True)` internally, so:
- `Ref` -> string (id)
- `Number` -> float
- `Marker` -> True
- `Coord` -> tuple (lat, lng)
- `NA` -> None

### Creating Fantom Types from Python

Use `from_py()` class methods:

```python
from fan.sys.DateTime import DateTime
from fan.sys.Duration import Duration
import datetime

# From Python datetime
fantom_dt = DateTime.from_py(datetime.datetime.now())
fantom_dur = Duration.from_py(datetime.timedelta(hours=2))

# Or use the xeto.py wrappers
from xeto import Number, Ref, Coord

num = Number(72.5, 'fahrenheit')  # Calls from_py internally
ref = Ref('site-1', 'Building')
coord = Coord(37.7749, -122.4194)
```

---

## Haystack Client

Connect to Haystack servers (SkySpark, Haxall, etc.) using the Client class.

### Basic Connection

```python
from fan.haystack.Client import Client
from fan.sys.Uri import Uri

# Connect with context manager (recommended - auto-closes)
uri = Uri.from_str("http://localhost:8080/api/demo/")
with Client.open_(uri, "username", "password") as client:
    # Query server metadata
    about = client.about()
    print(f"Server: {about.get('productName')}")

    # Read records
    sites = client.read_all("site")
    for row in sites:
        print(row.get("dis", "Unknown"))
```

### Read Operations

```python
# Read all records matching filter
sites = client.read_all("site")
equips = client.read_all("equip and siteRef==@my-site")
points = client.read_all("point and his")

# Read single record (returns None if not found when checked=False)
point = client.read("point and temp and sensor", checked=False)

# Complex filters
results = client.read_all("point and his and equipRef->siteRef->geoCity == \"Richmond\"")
```

### History Reads

```python
from fan.haystack.Etc import Etc
from fan.sys.List import List
from fan.sys.Duration import Duration

# Find a point with history
point = client.read("point and his", False)
point_id = point.get("id")

# Calculate date range
his_end = point.get("hisEnd")
end_date = his_end.date()
start_date = end_date.minus(Duration.make(7 * 24 * 60 * 60 * 1_000_000_000))

# Build hisRead request
req = Etc.make_lists_grid(
    None,  # meta
    List.from_list(["id", "range"]),
    None,  # column meta
    List.from_list([List.from_list([point_id, f"{start_date},{end_date}"])])
)

# Call hisRead op
history = client.call("hisRead", req)
print(f"Retrieved {len(history)} samples")

# Convert to pandas for analysis
df = history.to_pandas()
```

### Axon Eval

```python
# Execute Axon expressions on the server
result = client.eval("now()")
result = client.eval("readAll(site).sort(\"dis\")")
result = client.eval("readAll(point and his).size")
```

---

## Xeto Validation

### Basic Validation

```python
from fan.xeto.XetoEnv import XetoEnv
from fan.sys.List import List

# Get environment and create namespace
env = XetoEnv.cur()
lib_names = List.from_literal(['sys', 'ph'], 'sys::Str')
ns = env.create_namespace_from_names(lib_names)

# Validate a dict against a spec
site_spec = ns.spec("ph::Site")
is_valid = ns.fits(my_dict, site_spec)
```

### Validating Server Data

When validating data from a Haystack server, refs point to records on the server
that can't be resolved locally. Use `ignoreRefs` to skip ref validation:

```python
from fan.haystack.Etc import Etc
from fan.xeto.Marker import Marker
from fan.sys.Func import Func
from fan.sys.Unsafe import Unsafe

# Convert GbRow (server row) to proper Dict for validation
site_dict = Etc.make_dict(Etc.dict_to_map(row))

# Collect validation error messages
explain_msgs = []
def explain_callback(log_rec):
    msg = str(log_rec.msg()) if hasattr(log_rec, 'msg') else str(log_rec)
    explain_msgs.append(msg)

# Create explain function (wrapping Python callable for Fantom)
explain_func = Func.make_closure(
    {"returns": "sys::Void", "immutable": "never",
     "params": [{"name": "x", "type": "xeto::XetoLogRec"}]},
    explain_callback
)

# Options: ignoreRefs skips ref resolution, explain captures error details
opts = Etc.dict2(
    "explain", Unsafe.make(explain_func),
    "ignoreRefs", Marker.val()
)

# Validate
if ns.fits(site_dict, site_spec, opts):
    print("Valid!")
else:
    for msg in explain_msgs:
        print(f"  - {msg}")
```

**Why ignoreRefs?** Server data contains refs like `weatherStationRef` that point
to other records on the server. Without `ignoreRefs`, validation fails with
"Unresolved ref" errors because those records aren't available locally.

---

## Low-Level API

For advanced use cases, you can access the transpiled Fantom classes directly.

## Naming Convention

Fantom uses camelCase for method names, but the Python transpiler converts these to
**snake_case** for a Pythonic developer experience:

| Fantom | Python |
|--------|--------|
| `fromStr` | `from_str` |
| `toStr` | `to_str` |
| `isEmpty` | `is_empty` |
| `findAll` | `find_all` |
| `containsKey` | `contains_key` |

Python reserved words and builtins get a trailing underscore:
- `map` -> `map_`
- `hash` -> `hash_`
- `abs` -> `abs_`
- `min` -> `min_`
- `max` -> `max_`
- `any` -> `any_`
- `all` -> `all_`

## Quick Start

```python
import sys
sys.path.insert(0, 'fan/gen/py')

from fan.sys.List import List
from fan.sys.Map import Map

# Create a Fantom list
nums = List.from_literal([1, 2, 3], "sys::Int")

# Use instance methods (natural OO style)
doubled = nums.map_(lambda it: it * 2)
# Result: [2, 4, 6]

# Python protocols work
len(nums)           # 3
nums[0]             # 1
for x in nums:      # iteration
    print(x)
```

## Using Lambdas and Functions

Fantom methods that accept closures work with any Python callable:

### Lambda
```python
nums.map_(lambda it: it * 2)
nums.find_all(lambda it: it % 2 == 0)
nums.find(lambda it: it > 3)
```

### Named Function
```python
def multiply_by_2(x):
    return x * 2

nums.map_(multiply_by_2)
```

### Multi-line Logic
```python
def complex_filter(item):
    if item < 0:
        return False
    if item > 100:
        return False
    return item % 2 == 0

nums.find_all(complex_filter)
```

## Type Interoperability

### List

Fantom's `List` extends `Obj` and implements Python's `MutableSequence` protocol.
It wraps an internal Python list but is **not** a subclass of Python's `list`.

```python
nums = List.from_literal([1, 2, 3], "sys::Int")

# Instance methods (preferred - natural OO style)
nums.map_(lambda it: it * 2)              # [2, 4, 6]
nums.find_all(lambda it: it > 1)          # [2, 3]
nums.reduce(0, lambda acc, it: acc + it)  # 6

# Python protocols work
len(nums)           # 3
nums[0]             # 1
nums[-1]            # 3
3 in nums           # True
for x in nums:      # iteration works
    print(x)

# Note: List is NOT a Python list
isinstance(nums, list)  # False
isinstance(nums, List)  # True
```

### Map

Fantom's `Map` extends `Obj` and implements Python's `MutableMapping` protocol.
It wraps an internal Python dict but is **not** a subclass of Python's `dict`.

```python
from fan.sys.Map import Map

m = Map.from_literal(["a", "b"], [1, 2], "sys::Str", "sys::Int")

# Instance methods
m.each(lambda v, k: print(f"{k}={v}"))
m.get("a")            # 1
m.contains_key("a")   # True

# Python protocols work
len(m)              # 2
m["a"]              # 1
"a" in m            # True

# Note: Map is NOT a Python dict
isinstance(m, dict)  # False
isinstance(m, Map)   # True
```

### Primitives

Fantom primitives map to Python types:

| Fantom | Python | Notes |
|--------|--------|-------|
| `Int` | `int` | Arbitrary precision |
| `Float` | `float` | IEEE 754 |
| `Bool` | `bool` | `True`/`False` |
| `Str` | `str` | Unicode |
| `null` | `None` | Nullable values |

Fantom methods on primitives are called as static methods:

```python
from fan.sys.Int import Int
from fan.sys.Str import Str

# Int methods
Int.times(3, lambda i: print(i))  # 0, 1, 2
Int.to_hex(255)                    # "ff"

# Str methods
Str.size("hello")                  # 5
Str.upper("hello")                 # "HELLO"
```

## Instance Methods (Recommended)

Lists created with `List.from_literal()` support instance methods for a more natural OO style:

```python
from fan.sys.List import List

nums = List.from_literal([1, 2, 3, 4, 5], "sys::Int")

# Transform
nums.map_(lambda it: it * 2)              # [2, 4, 6, 8, 10]
nums.flat_map(lambda it: [it, it * 2])    # flatten nested results
nums.map_not_null(lambda it: it if it > 2 else None)

# Filter/Find
nums.find(lambda it: it > 3)             # 4
nums.find_all(lambda it: it % 2 == 0)    # [2, 4]
nums.find_index(lambda it: it > 3)       # 3
nums.exclude(lambda it: it < 3)          # [3, 4, 5]

# Predicates
nums.any_(lambda it: it > 4)             # True
nums.all_(lambda it: it > 0)             # True

# Aggregate
nums.reduce(0, lambda acc, it: acc + it) # 15
nums.min_()                               # 1
nums.max_()                               # 5
nums.join(", ")                           # "1, 2, 3, 4, 5"

# Sort
nums.sort(lambda a, b: b - a)            # descending
nums.sortr()                              # reverse order
nums.shuffle()                            # random order
nums.reverse()                            # reverse in place

# Iteration
nums.each(lambda it: print(it))
nums.each(lambda it, i: print(f"{i}: {it}"))

# Accessors
nums.first()                              # 1
nums.last()                               # 5
nums.is_empty()                           # False
nums.contains(3)                          # True
nums.index(3)                             # 2

# Modification
nums.add(6)                               # append
nums.insert(0, 0)                         # insert at index
nums.remove(3)                            # remove first occurrence
nums.remove_at(0)                         # remove at index

# Stack operations
nums.push(6)                              # same as add
nums.pop()                                # remove and return last
nums.peek()                               # return last without removing
```

## Common API Patterns

### List Operations (Static Methods)

Static methods are also available for all list operations:

```python
from fan.sys.List import List

nums = List.from_literal([1, 2, 3, 4, 5], "sys::Int")

# Transform
List.map_(nums, lambda it: it * 2)           # [2, 4, 6, 8, 10]

# Filter
List.find_all(nums, lambda it: it % 2 == 0)  # [2, 4]
List.find(nums, lambda it: it > 3)           # 4

# Aggregate
List.reduce(nums, 0, lambda acc, it: acc + it)  # 15
List.any_(nums, lambda it: it > 4)           # True
List.all_(nums, lambda it: it > 0)           # True

# Sort
List.sort(nums, lambda a, b: b - a)          # descending

# Iterate
List.each(nums, lambda it: print(it))
List.each(nums, lambda it, i: print(f"{i}: {it}"))  # with index
```

### Map Operations

```python
from fan.sys.Map import Map

m = Map.from_literal(["a", "b", "c"], [1, 2, 3], "sys::Str", "sys::Int")

# Iterate
m.each(lambda v, k: print(f"{k}={v}"))

# Transform
m.map_(lambda v, k: v * 2)

# Filter
m.find_all(lambda v, k: v > 1)
```

### Int Operations

```python
from fan.sys.Int import Int

# Repeat N times
Int.times(5, lambda i: print(i))

# Range iteration
Int.times(10, lambda i: do_something(i))
```

## Two-Argument Closures

Many Fantom methods support closures with both value and index:

```python
# Value only
nums.each(lambda it: print(it))

# Value and index
nums.each(lambda it, i: print(f"{i}: {it}"))

# Map: value and key
m.each(lambda v, k: print(f"{k}={v}"))
```

## Error Handling

Fantom errors map to Python exceptions:

```python
from fan.sys.Err import Err, ArgErr, NullErr

try:
    # Fantom code that might throw
    result = some_fantom_api()
except ArgErr as e:
    print(f"Invalid argument: {e}")
except NullErr as e:
    print(f"Null value: {e}")
except Err as e:
    print(f"Fantom error: {e}")
```

## Importing Types

Cross-pod imports:

```python
# Core sys types
from fan.sys.List import List
from fan.sys.Map import Map
from fan.sys.Type import Type

# Haystack types (after transpiling)
from fan.haystack.Dict import Dict
from fan.haystack.Grid import Grid

# Xeto types (after transpiling)
from fan.xeto.Spec import Spec
```

## Further Reading

- `design.md` - How the transpiler generates Python code
- `development_guide.md` - Contributing to the transpiler
- Fantom documentation at https://fantom.org/doc/
