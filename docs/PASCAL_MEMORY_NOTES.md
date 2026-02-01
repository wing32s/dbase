# Pascal Memory Optimization Notes

## Changes Made

### Removed: `DBFFileBuildNDX` function

**Location**: `DBF.PAS` line 124 (interface) and implementation

**Reason**: This function required ~650KB heap memory for large databases (e.g., GAMES3.DBF with 7700 records)

**Memory breakdown**:
- `GetMem(Entries, SizeOf(TNDXEntry) * RowCount)` = 84 bytes × 7700 = ~647 KB
- Additional node arrays = ~50-100 KB
- **Total**: Required `{$M 65520,0,350000}` directive

**Replacement**: Use Python's `ndx_module.ndx_create_index()` instead

```python
from ndx_module import ndx_create_index

# Create index for any field
ndx_create_index('GAMES3.DBF', 'devname', 'DEVNAME.NDX')
ndx_create_index('GAMES3.DBF', 'year', 'YEAR.NDX')
ndx_create_index('GAMES3.DBF', 'dateadd', 'DATEADD.NDX')
```

## Current Pascal Memory Usage

### For NDX Reading/Searching (DBFINDEX.PAS)

**Stack usage per search**: ~6 KB
- `TNDXBlock` (512 bytes)
- `TNDXKeyArray` (5,184 bytes)
- `TNDXIntArray` (260 bytes)
- `TNDXBlockStack` (128 bytes)
- `TNDXIdxStack` (64 bytes)

**Heap usage**: 0 bytes (no dynamic allocation)

**Recommended directive**:
```pascal
{$M 32768,0,32768}  // Stack: 32KB, Heap: 32KB
```

Or even:
```pascal
{$M 16384,0,16384}  // Stack: 16KB, Heap: 16KB
```

### For DBF Operations (DBF.PAS)

**Typical usage**:
- Record buffer: ~4 KB
- Field arrays: ~2 KB
- Memo operations: Variable (typically < 64 KB)

**Recommended directive**:
```pascal
{$M 65520,0,65520}  // Stack: 64KB, Heap: 64KB
```

## Summary

By removing index creation from Pascal:
- ✅ Reduced heap requirement from 350KB to 64KB (5.4x reduction)
- ✅ All NDX reading/searching operations still work perfectly
- ✅ Index creation available via Python (more flexible)
- ✅ Simpler Pascal codebase to maintain

## If You Need Index Creation in Pascal Later

See `MEMORY_EFFICIENT_NDX.md` for external sort algorithm that uses only ~100KB memory.
