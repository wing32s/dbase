# DBF Query Optimization Guide

## Overview

The `dbf_query.py` module provides efficient multi-field filtering for DBF files by combining:

1. **In-memory heap maps** for numeric/date fields (O(1) lookups)
2. **NDX B-tree indexes** for string prefix searches (O(log n) traversal)
3. **Stream-based result intersection** (memory efficient)

## Problem Statement

**Naive approach** (slow for large files):
```python
# Read all records, filter in Python
results = []
for recno in range(1, record_count + 1):
    dbf_file_seek_to_row(dbf, recno - 1)
    row = dbf_file_read_row(dbf)
    if row[title_idx].startswith("PC") and \
       int(row[year_idx]) == 1984 and \
       int(row[players_idx]) == 4:
        results.append(recno)
```

**Problems:**
- Reads every record from disk (I/O bound)
- No index utilization
- String operations on every row
- Memory intensive for large result sets

## Optimized Approach

### Strategy

1. **Use NDX index for most selective filter** (string prefix)
   - B-tree traversal finds matching records efficiently
   - Returns sorted recnos without reading data records

2. **Build heap maps for numeric filters** (year, maxplayers)
   - One-time scan to build `recno -> value` mapping
   - Reusable for multiple queries
   - Fast O(1) lookups

3. **Stream intersection of filtered recnos**
   - Apply filters sequentially to narrow result set
   - Memory efficient (only stores recnos, not full records)

### Example Query

```python
from dbf_query import DBFQueryBuilder

# Find games: title LIKE 'King%' AND year=1984 AND maxplayers=4
query = DBFQueryBuilder("samples/GAMES3.DBF")

# Most selective filter first (NDX prefix search)
query.filter_by_ndx_prefix("samples/TITLE3.NDX", "King")

# Apply additional filters using heap maps
query.filter_by_value("year", 1984)
query.filter_by_value("maxplayers", 4)

# Execute and get results
recnos = query.execute()
print(f"Found {len(recnos)} matching records")
```

### Performance Benefits

**For GAMES3.DBF (8,000+ records):**

| Query Type | Naive Approach | Optimized | Speedup |
|------------|---------------|-----------|---------|
| String prefix + 2 filters | ~8,000 reads | ~200 reads | **40x** |
| Numeric range | ~8,000 reads | 1 scan + O(1) | **100x+** |
| Exact match + filter | ~8,000 reads | ~50 reads | **160x** |

## API Reference

### DBFHeapMap

Build an in-memory index for a single field.

```python
from dbf_query import DBFHeapMap

# Build heap map for year field
heap_map = DBFHeapMap("games.DBF", "year")

# Find exact matches
recnos = heap_map.find_exact(1984)

# Find range matches
recnos = heap_map.find_range(1982, 1984)

# Filter existing recnos
filtered = heap_map.filter_recnos(candidate_recnos, 1984)
```

**Use cases:**
- Numeric fields (year, count, score)
- Date fields (stored as YYYYMMDD)
- Small cardinality fields (status codes, categories)

### DBFQueryBuilder

Fluent API for building complex queries.

```python
from dbf_query import DBFQueryBuilder

query = DBFQueryBuilder("data.DBF")

# Chain filters
query.filter_by_ndx_prefix("title.NDX", "King")  # NDX index
query.filter_by_value("year", 1984)              # Heap map
query.filter_by_range("score", 80, 100)          # Heap map range

# Execute
recnos = query.execute()

# Or stream results (memory efficient)
for recno in query.execute_stream():
    process_record(recno)
```

**Methods:**

- `filter_by_ndx_prefix(ndx_file, prefix)` - Use NDX for prefix search
- `filter_by_ndx_exact(ndx_file, value)` - Use NDX for exact match
- `filter_by_value(field, value)` - Exact match using heap map
- `filter_by_range(field, min, max)` - Range filter using heap map
- `execute()` - Return list of matching recnos
- `execute_stream()` - Stream matching recnos (memory efficient)

## Query Optimization Tips

### 1. Apply Most Selective Filter First

```python
# ✅ GOOD: NDX prefix first (most selective)
query.filter_by_ndx_prefix("title.NDX", "Zork")  # ~10 matches
query.filter_by_value("year", 1984)              # Filter 10 records

# ❌ BAD: Broad filter first
query.filter_by_value("year", 1984)              # ~500 matches
query.filter_by_ndx_prefix("title.NDX", "Zork")  # Still need to check 500
```

### 2. Use NDX Indexes for String Searches

```python
# ✅ GOOD: Use NDX index
query.filter_by_ndx_prefix("devname.NDX", "Sierra")

# ❌ BAD: Scan all records
# (No built-in support - would need custom filter)
```

### 3. Build Heap Maps for Repeated Queries

```python
# ✅ GOOD: Reuse heap maps
year_map = DBFHeapMap("games.DBF", "year")
for year in [1982, 1983, 1984]:
    recnos = year_map.find_exact(year)
    print(f"{year}: {len(recnos)} games")

# ❌ BAD: Rebuild for each query
for year in [1982, 1983, 1984]:
    query = DBFQueryBuilder("games.DBF")
    query.filter_by_value("year", year)  # Rebuilds heap map each time
```

### 4. Use Streaming for Large Result Sets

```python
# ✅ GOOD: Stream results (low memory)
for recno in query.execute_stream():
    dbf_file_seek_to_row(dbf, recno - 1)
    row = dbf_file_read_row(dbf)
    process(row)

# ❌ BAD: Load all results (high memory)
recnos = query.execute()  # Could be 10,000+ recnos
rows = []
for r in recnos:
    dbf_file_seek_to_row(dbf, r - 1)
    rows.append(dbf_file_read_row(dbf))
```

## Real-World Examples

### Example 1: Game Search

Find all Sierra games from 1985-1990 with 2+ players:

```python
query = DBFQueryBuilder("games.DBF")
query.filter_by_ndx_prefix("devname.NDX", "Sierra")  # ~200 matches
query.filter_by_range("year", 1985, 1990)            # ~100 matches
query.filter_by_range("maxplayers", 2, 99)           # ~80 matches

recnos = query.execute()
```

**Performance:**
- NDX search: ~200 recnos (no disk reads for data)
- Heap filters: 2 passes over 200 recnos (in-memory)
- **Total: ~200 operations vs. 8,000+ for full scan**

### Example 2: Date Range Query

Find all records added in August 2022:

```python
query = DBFQueryBuilder("data.DBF")
query.filter_by_range("dateadd", "20220801", "20220831")

recnos = query.execute()
```

**Performance:**
- One-time heap map build: 8,000 reads
- Range filter: O(n) where n = unique dates
- **Reusable for multiple date queries**

### Example 3: Complex Multi-Field Query

```python
# Find: title starts with "King", year 1984, 4 players, score > 80
query = DBFQueryBuilder("games.DBF")
query.filter_by_ndx_prefix("title.NDX", "King")  # ~50 matches
query.filter_by_value("year", 1984)              # ~10 matches
query.filter_by_value("maxplayers", 4)           # ~5 matches
query.filter_by_range("score", 80, 100)          # ~3 matches

recnos = query.execute()
```

**Filter cascade:**
```
8,000 records
  ↓ NDX prefix "King"
  50 records
  ↓ year=1984
  10 records
  ↓ maxplayers=4
  5 records
  ↓ score 80-100
  3 records ✅
```

## Memory Considerations

### Heap Map Memory Usage

For a field with N records:
- `recno_to_value`: ~12 bytes per record (dict overhead + int key + value)
- `value_to_recnos`: ~8 bytes per record (list overhead)

**Example:** 10,000 records = ~200 KB per heap map

### When to Use Heap Maps

✅ **Good candidates:**
- Numeric fields (year, count, id)
- Date fields
- Small cardinality fields (status, category)
- Fields used in multiple queries

❌ **Poor candidates:**
- Large text fields (memo, description)
- High cardinality fields (unique IDs)
- Fields rarely used in queries

## Integration with Existing Code

### With dbf_module.py

```python
from dbf_module import dbf_file_open, dbf_file_read_row, dbf_file_seek_to_row, dbf_file_close
from dbf_query import DBFQueryBuilder

# Build query
query = DBFQueryBuilder("data.DBF")
query.filter_by_value("status", "active")
recnos = query.execute()

# Read matching records
dbf = dbf_file_open("data.DBF")
try:
    for recno in recnos:
        dbf_file_seek_to_row(dbf, recno - 1)
        row = dbf_file_read_row(dbf)
        print(row)
finally:
    dbf_file_close(dbf)
```

### With ndx_module.py

```python
from ndx_module import ndx_create_index
from dbf_query import DBFQueryBuilder

# Create NDX index if needed
if not os.path.exists("title.NDX"):
    ndx_create_index("data.DBF", "title", "title.NDX")

# Use in query
query = DBFQueryBuilder("data.DBF")
query.filter_by_ndx_prefix("title.NDX", "King")
recnos = query.execute()
```

## Testing

Run the test suite:

```bash
# Run all query tests
pytest tests/test_dbf_query.py -v

# Run with demo
python tests/test_dbf_query.py
```

## Future Enhancements

Potential optimizations:
1. **Persistent heap maps** - Cache to disk for reuse
2. **Bitmap indexes** - For very low cardinality fields
3. **Query planner** - Automatic filter ordering
4. **Parallel filtering** - Multi-threaded filter application
5. **Join support** - Multi-table queries

## See Also

- [README_dbf.md](README_dbf.md) - DBF module documentation
- [README_ndx.md](README_ndx.md) - NDX index documentation
- [MEMORY_EFFICIENT_NDX.md](../MEMORY_EFFICIENT_NDX.md) - Index implementation details
