# NDX Index File Module

## Overview

The `ndx_module.py` provides functionality for reading dBase NDX index files. NDX files are B-tree indexes used by dBase III/IV/V to provide fast lookups on database fields.

## Features Implemented

### ✅ NDX Header Reading
- **`ndx_read_header(filename)`** - Read NDX file header
- Supports both V1 (dBase III) and V2 (dBase IV) formats
- Extracts: root block, EOF block, key length, max keys, group length, expression

### ✅ NDX Node Reading
- **`ndx_read_node(filename, block, header)`** - Read a B-tree node
- Extracts: keys, child pointers, record numbers, last child

### ✅ First Entries Dump
- **`ndx_dump_first_entries(filename, count)`** - Get first N entries
- Navigates to leftmost leaf node
- Returns list of (record_number, key) tuples

## NDX File Format

### Header Structure

**V1 Format (dBase III):**
- Offset 0-1: Root block (16-bit)
- Offset 4-5: EOF block (16-bit)
- Offset 6-7: Key length (16-bit)
- Offset 8-9: Keys max (16-bit)
- Offset 10-11: Group length (16-bit)
- Offset 16+: Expression (null-terminated string)

**V2 Format (dBase IV):**
- Offset 0-3: Root block (32-bit)
- Offset 4-7: EOF block (32-bit)
- Offset 12-13: Key length (16-bit)
- Offset 14-15: Keys max (16-bit)
- Offset 18-19: Group length (16-bit)
- Offset 24+: Expression (null-terminated string)

### Node Structure

Each node is 512 bytes:
- Offset 0-1: Number of keys (16-bit)
- Offset 4+: Key groups (repeated)
  - Child pointer (32-bit)
  - Record number (32-bit)
  - Key data (variable length)
- Last: Final child pointer (32-bit)

## Test Results

Successfully tested with sample NDX files:

### DEVNAME3.NDX
- Expression: `devname`
- Key length: 30 bytes
- Keys max: 12 per node
- First entry: Record 990, Key: ""
- Second entry: Record 131, Key: "'PG' Productions"

### Other Sample Files
- **DEVNAMEU.NDX**: Upper case developer names (30 bytes)
- **PUBNAME3.NDX**: Publisher names (30 bytes)
- **TEXT3.NDX**: Text field (10 bytes)
- **TITLE3.NDX**: Game titles (50 bytes)
- **YEAR3.NDX**: Year field (8 bytes, numeric)
- **DATEADD3.NDX**: Date added field (8 bytes, date)

## Usage Example

```python
from ndx_module import ndx_read_header, ndx_dump_first_entries

# Read header
header = ndx_read_header("samples/DEVNAME3.NDX")
print(f"Expression: {header.expr}")
print(f"Key length: {header.key_len}")

# Dump first 10 entries
entries = ndx_dump_first_entries("samples/DEVNAME3.NDX", 10)
for i, (recno, key) in enumerate(entries, 1):
    print(f"{i}. Record {recno}: {key}")
```

## Implementation Status

### Completed ✅
- NDX header reading (V1 and V2 formats)
- NDX node reading
- B-tree navigation (to leftmost leaf)
- First entries dump
- Key cleaning (null byte handling)

### Pending ⏳
- Exact match search
- Prefix match search
- Range search
- Count operations
- Full B-tree traversal

## References

- Sample files: `samples/*.NDX`
- Pascal implementation: `TESTIDX.PAS`
- Test suite: `test_ndx_module.py`
