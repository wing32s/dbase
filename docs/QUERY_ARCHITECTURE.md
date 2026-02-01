# DBF Query Architecture v2

## Design Overview

Advanced query system with filter groups and unified heap maps.

### Key Features

1. **Filter Groups** - Up to 8 filters per group with OR/AND logic
2. **Multiple Groups** - Up to 4 groups combined with AND
3. **Unified Heap Map** - Single in-memory map for all non-string columns
4. **Queue-based String Filters** - Lazy evaluation for string comparisons
5. **NDX Integration** - Use B-tree indexes for selective string searches

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                        DBFQuery                              │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Group 1 (OR/AND)                                      │  │
│  │  ├─ Filter 1: title LIKE 'King%' (NDX)              │  │
│  │  ├─ Filter 2: title LIKE 'Queen%' (NDX)             │  │
│  │  └─ ... (up to 8 filters)                           │  │
│  └───────────────────────────────────────────────────────┘  │
│                          AND                                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Group 2 (OR/AND)                                      │  │
│  │  ├─ Filter 1: year = 1984 (Heap Map)                │  │
│  │  ├─ Filter 2: year = 1985 (Heap Map)                │  │
│  │  └─ ... (up to 8 filters)                           │  │
│  └───────────────────────────────────────────────────────┘  │
│                          AND                                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Group 3 (OR/AND)                                      │  │
│  │  └─ Filter 1: maxplay >= 2 (Heap Map)               │  │
│  └───────────────────────────────────────────────────────┘  │
│                          AND                                 │
│  ┌───────────────────────────────────────────────────────┐  │
│  │ Group 4 (OR/AND)                                      │  │
│  │  └─ ... (up to 8 filters)                           │  │
│  └───────────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────────┘
                           ↓
              ┌─────────────────────────┐
              │   Unified Heap Map      │
              │  ┌──────────────────┐   │
              │  │ recno → values   │   │
              │  │  1 → {year:1984, │   │
              │  │       maxplay:4} │   │
              │  │  2 → {year:1985, │   │
              │  │       maxplay:2} │   │
              │  └──────────────────┘   │
              └─────────────────────────┘
```

## Query Execution Flow

### Short-Circuit Evaluation

The query system uses short-circuit evaluation for optimal performance:

**Within AND Groups:**
```python
# Stop as soon as any filter returns 0 results
for filter in filters:
    result = evaluate(filter)
    if not result:  # ← SHORT-CIRCUIT
        break
```

**Between Groups (AND logic):**
```python
# Stop as soon as any group returns 0 results
for group in groups:
    recnos = group.evaluate(recnos)
    if not recnos:  # ← SHORT-CIRCUIT
        break
```

**Within OR Groups:**
```python
# Stop if all input records have been matched
for filter in filters:
    results.update(evaluate(filter))
    if len(results) == len(input):  # ← SHORT-CIRCUIT
        break
```

**Performance Impact:**
- Best case: 1 filter evaluated (first filter returns 0 results)
- Worst case: All filters evaluated (all return results)
- Typical case: 2-3 filters evaluated before short-circuit

### Phase 1: Build Unified Heap Map

```python
# Scan DBF file ONCE
# Extract ALL non-string fields into single map
# Dates converted to integers, logicals to booleans
heap_map = {
    recno: {
        'year': 1984,           # Numeric field (int)
        'maxplay': 4,           # Numeric field (int)
        'dateadd': 20220825,    # Date field (YYYYMMDD as int)
        'is_active': True,      # Logical field (bool)
        'flags': 42             # Numeric field (can be used as bit flags)
    }
}
```

**Benefits:**
- Single pass through DBF file
- All numeric/date/logical fields indexed together
- Dates as integers enable fast comparison (>, <, BETWEEN)
- Logicals as booleans enable fast equality checks
- Bit operations on numeric fields (no conversion needed)
- Reusable across multiple filter groups

### Phase 2: Apply Filter Groups (AND logic)

```
Start: All records (7,665)
  ↓
Group 1 (OR): title LIKE 'King%' OR title LIKE 'Queen%'
  → NDX lookup: 33 records
  ↓
Group 2 (OR): year = 1984 OR year = 1985
  → Heap map filter on 33 records: 2 records
  ↓
Group 3 (AND): maxplay >= 2
  → Heap map filter on 2 records: 0 records
  ↓
Result: 0 records
```

### Phase 3: String Filter Evaluation

**Option A: NDX Index (Preferred)**
```python
# Use B-tree index for fast lookup
filter = like("title", "King", "samples/TITLE3.NDX")
# Returns sorted recnos without reading data records
```

**Option B: Queue-based Lazy Evaluation**
```python
# For non-indexed string fields
# Pull next record, compare, keep or skip
for recno in candidate_recnos:
    row = read_row(recno)
    if row['title'].startswith("King"):
        keep(recno)
```

## API Reference

### DBFQuery

Main query builder class.

```python
from dbf_query_v2 import DBFQuery, FilterGroup, GroupOp, equal, like, between

# Create query
query = DBFQuery("data.DBF")

# Add filter groups
group1 = FilterGroup(GroupOp.OR)
group1.add_filter(like("title", "King", "title.NDX"))
group1.add_filter(like("title", "Queen", "title.NDX"))
query.add_group(group1)

group2 = FilterGroup(GroupOp.AND)
group2.add_filter(equal("year", 1984))
group2.add_filter(between("maxplay", 2, 8))
query.add_group(group2)

# Execute
recnos = query.execute()
```

**Limits:**
- Max 4 filter groups per query
- Max 8 filters per group

### FilterGroup

Group of filters with OR/AND logic.

```python
# AND group (all filters must match)
group = FilterGroup(GroupOp.AND)
group.add_filter(equal("year", 1984))
group.add_filter(equal("maxplay", 4))

# OR group (any filter can match)
group = FilterGroup(GroupOp.OR)
group.add_filter(equal("year", 1984))
group.add_filter(equal("year", 1985))
```

### Filter Operations

```python
# Equality
equal("year", 1984)
not_equal("year", 1984)

# Comparison
less_than("year", 1985)
less_equal("year", 1984)
greater_than("year", 1983)
greater_equal("year", 1984)

# Range
between("year", 1982, 1984)

# List membership
in_list("year", [1982, 1983, 1984])

# String matching (requires NDX)
like("title", "King", "title.NDX")
equal("devname", "Sierra On-Line, Inc.", "devname.NDX")

# Date operations (dates stored as YYYYMMDD integers)
date_equal("dateadd", 2022, 8, 25)           # Exact date
date_between("dateadd", 2022, 1, 1, 2022, 12, 31)  # Date range
date_after("dateadd", 2022, 6, 30)           # After date
date_before("dateadd", 2023, 1, 1)           # Before date
date_year("dateadd", 2022)                   # All dates in 2022

# Logical field operations
logical_true("is_active")                    # Where field is TRUE
logical_false("is_deleted")                  # Where field is FALSE

# Bit flag operations (for numeric fields with bit flags)
bit_set("flags", 3)                          # Check if bit 3 is set
bit_clear("flags", 5)                        # Check if bit 5 is clear
bit_mask_all("flags", 0b1010)                # Check if bits 1 AND 3 are set
bit_mask_any("flags", 0b1010)                # Check if bit 1 OR bit 3 is set
```

### UnifiedHeapMap

Single heap map for all non-string columns.

```python
from dbf_query_v2 import UnifiedHeapMap

# Build map for multiple fields
heap_map = UnifiedHeapMap("data.DBF", ["year", "maxplay", "dateadd"])

# Access data
record_values = heap_map.recno_to_values[100]
# {'year': 1984, 'maxplay': 4, 'dateadd': '20220825'}

# Evaluate filter
from dbf_query_v2 import FilterOp
filtered = heap_map.evaluate_filter(
    recnos=[1, 2, 3, 100],
    field_name="year",
    op=FilterOp.EQUAL,
    value=1984
)
```

## Query Examples

### Example 1: Simple AND Query

```python
# Query: year = 1984 AND maxplay = 4

query = DBFQuery("games.DBF")

group = FilterGroup(GroupOp.AND)
group.add_filter(equal("year", 1984))
group.add_filter(equal("maxplay", 4))
query.add_group(group)

recnos = query.execute()
# Result: [1413, 1716, 3635, 3660, 5009, 5338, 6760]
```

### Example 2: OR Within Group

```python
# Query: year = 1984 OR year = 1985

query = DBFQuery("games.DBF")

group = FilterGroup(GroupOp.OR)
group.add_filter(equal("year", 1984))
group.add_filter(equal("year", 1985))
query.add_group(group)

recnos = query.execute()
```

### Example 3: Complex Multi-Group Query

```python
# Query: (title LIKE 'King%' OR title LIKE 'Queen%')
#        AND (year BETWEEN 1982 AND 1984)
#        AND (maxplay >= 2)
#        AND (devname = 'Sierra On-Line, Inc.')

query = DBFQuery("games.DBF")

# Group 1: Title filters (OR)
group1 = FilterGroup(GroupOp.OR)
group1.add_filter(like("title", "King", "title.NDX"))
group1.add_filter(like("title", "Queen", "title.NDX"))
query.add_group(group1)

# Group 2: Year range
group2 = FilterGroup(GroupOp.AND)
group2.add_filter(between("year", 1982, 1984))
query.add_group(group2)

# Group 3: Player count
group3 = FilterGroup(GroupOp.AND)
group3.add_filter(greater_equal("maxplay", 2))
query.add_group(group3)

# Group 4: Developer
group4 = FilterGroup(GroupOp.AND)
group4.add_filter(equal("devname", "Sierra On-Line, Inc.", "devname.NDX"))
query.add_group(group4)

recnos = query.execute()
```

### Example 4: Range and List Queries

```python
# Query: year IN (1982, 1983, 1984) AND maxplay BETWEEN 2 AND 8

query = DBFQuery("games.DBF")

group = FilterGroup(GroupOp.AND)
group.add_filter(in_list("year", [1982, 1983, 1984]))
group.add_filter(between("maxplay", 2, 8))
query.add_group(group)

recnos = query.execute()
```

### Example 5: Date Queries

```python
# Query: dateadd in 2018 AND year >= 1985

from dbf_query_v2 import date_between, greater_equal

query = DBFQuery("games.DBF")

# Group 1: Date range (all of 2018)
group1 = FilterGroup(GroupOp.AND)
group1.add_filter(date_between("dateadd", 2018, 1, 1, 2018, 12, 31))
query.add_group(group1)

# Group 2: Year filter
group2 = FilterGroup(GroupOp.AND)
group2.add_filter(greater_equal("year", 1985))
query.add_group(group2)

recnos = query.execute()
```

**Date Storage:**
- DBF dates stored as 8-character strings: "20180611"
- Converted to integers in heap map: 20180611
- Enables fast numeric comparison
- Example comparisons:
  - `20180611 > 20180101` (after Jan 1, 2018)
  - `20180611 < 20190101` (before Jan 1, 2019)
  - `20180101 <= 20180611 <= 20181231` (in 2018)

### Example 6: Bit Flag Queries

```python
# Query: Check if bit 3 is set AND bit 5 is clear in flags field

from dbf_query_v2 import bit_set, bit_clear

query = DBFQuery("data.DBF")

group = FilterGroup(GroupOp.AND)
group.add_filter(bit_set("flags", 3))      # Bit 3 must be set
group.add_filter(bit_clear("flags", 5))    # Bit 5 must be clear
query.add_group(group)

recnos = query.execute()
```

**Bit Flag Operations:**

| Operation | Description | Example |
|-----------|-------------|---------|
| `bit_set(field, n)` | Check if bit n is set | `flags & (1 << 3) != 0` |
| `bit_clear(field, n)` | Check if bit n is clear | `flags & (1 << 3) == 0` |
| `bit_mask_all(field, mask)` | All mask bits set | `(flags & 0b1010) == 0b1010` |
| `bit_mask_any(field, mask)` | Any mask bits set | `(flags & 0b1010) != 0` |

**Bit Positions (0-based, LSB = 0):**
```
Value: 42 (decimal) = 0b00101010 (binary)

Bit:    7  6  5  4  3  2  1  0
Value:  0  0  1  0  1  0  1  0
        ↑     ↑     ↑     ↑
        |     |     |     └─ Bit 1 is set
        |     |     └─────── Bit 3 is set
        |     └───────────── Bit 5 is set
        └─────────────────── Bit 7 is clear
```

**Common Use Cases:**
- Feature flags (e.g., bit 0 = multiplayer, bit 1 = online, bit 2 = VR)
- Status flags (e.g., bit 0 = active, bit 1 = verified, bit 2 = premium)
- Permission bits (e.g., bit 0 = read, bit 1 = write, bit 2 = delete)

### Example 7: Logical Field Queries

```python
# Query: Active records that are not deleted

from dbf_query_v2 import logical_true, logical_false

query = DBFQuery("data.DBF")

group = FilterGroup(GroupOp.AND)
group.add_filter(logical_true("is_active"))
group.add_filter(logical_false("is_deleted"))
query.add_group(group)

recnos = query.execute()
```

**Logical Field Values:**
- **TRUE**: `'T'`, `'Y'`, `'1'`
- **FALSE**: `'F'`, `'N'`, `'0'`, empty

## Performance Characteristics

### Memory Usage

**Unified Heap Map:**
- ~20 bytes per record per field
- Example: 10,000 records × 3 fields = ~600 KB

**vs. Separate Heap Maps:**
- Old approach: 3 separate maps = ~900 KB
- **Savings: 33%**

### Query Performance

| Query Type | Operations | Time Complexity |
|------------|-----------|-----------------|
| Single NDX filter | 1 B-tree traversal | O(log n + k) |
| Single heap filter | 1 hash lookup per recno | O(m) where m = input size |
| OR group (2 filters) | 2 operations + union | O(m × 2) |
| AND group (2 filters) | 2 operations (sequential) | O(m + m/2) |
| 4 groups (AND) | 4 group evaluations | O(m → m/2 → m/4 → m/8) |

**Best Case:** NDX filter first (most selective)
- 8,000 records → 50 records (NDX)
- 50 records → 10 records (heap filter)
- **Total: ~60 operations**

**Worst Case:** Broad filters first
- 8,000 records → 4,000 records (heap filter)
- 4,000 records → 50 records (NDX)
- **Total: ~12,000 operations**

### Optimization Tips

1. **Put most selective filters first (leverages short-circuit)**
   ```python
   # ✅ GOOD: Most selective filter first in AND group
   group.add_filter(like("title", "Zork", "title.NDX"))  # ~10 matches (selective)
   group.add_filter(greater_equal("year", 1980))         # ~7,000 matches (broad)
   # If first filter returns 0, second filter is skipped!
   
   # ❌ BAD: Broad filter first
   group.add_filter(greater_equal("year", 1980))         # ~7,000 matches
   group.add_filter(like("title", "Zork", "title.NDX"))  # ~10 matches
   # Must evaluate broad filter on all 7,665 records first
   ```

2. **Put most selective groups first**
   ```python
   # ✅ GOOD: Selective group first
   query.add_group(group_with_ndx_filter)    # Returns 50 records
   query.add_group(group_with_year_filter)   # Evaluates on 50 records
   # If first group returns 0, second group is skipped!
   
   # ❌ BAD: Broad group first
   query.add_group(group_with_year_filter)   # Returns 4,000 records
   query.add_group(group_with_ndx_filter)    # Evaluates on 4,000 records
   ```

3. **Use AND groups for restrictive filters**
   ```python
   # ✅ GOOD: AND group with selective filters
   group = FilterGroup(GroupOp.AND)
   group.add_filter(equal("year", 1984))     # Selective
   group.add_filter(equal("maxplay", 4))     # Selective
   # Short-circuits if first filter returns 0
   
   # ⚠️  CAREFUL: OR group evaluates all filters
   group = FilterGroup(GroupOp.OR)
   group.add_filter(equal("year", 1984))
   group.add_filter(equal("year", 1985))
   # Must evaluate both (but short-circuits if all records matched)
   ```

4. **Combine related filters in same group**
   ```python
   # ✅ GOOD: Related year filters in one OR group
   group = FilterGroup(GroupOp.OR)
   group.add_filter(equal("year", 1984))
   group.add_filter(equal("year", 1985))
   
   # ❌ BAD: Split across groups (no short-circuit benefit)
   group1.add_filter(equal("year", 1984))
   group2.add_filter(equal("year", 1985))
   # Both groups must be evaluated separately
   ```

5. **Build heap map once, query many times**
   ```python
   # Reuse query object for multiple executions
   query = DBFQuery("data.DBF")
   # ... add groups ...
   
   # First execution builds heap map
   results1 = query.execute()
   
   # Subsequent executions reuse heap map
   results2 = query.execute()  # Fast!
   ```

6. **Order OR filters by expected selectivity**
   ```python
   # ✅ GOOD: Most common values first in OR group
   group = FilterGroup(GroupOp.OR)
   group.add_filter(equal("year", 1984))  # Most common
   group.add_filter(equal("year", 1983))  # Less common
   group.add_filter(equal("year", 1982))  # Least common
   # Short-circuits faster if early filters match all records
   ```

## Comparison: v1 vs v2

| Feature | v1 (Simple) | v2 (Advanced) |
|---------|-------------|---------------|
| Filter groups | No | Yes (up to 4) |
| Filters per group | N/A | Up to 8 |
| Group logic | N/A | OR/AND |
| Heap maps | Separate per field | Unified |
| String filters | NDX only | NDX + lazy queue |
| Memory | Higher | Lower (33% savings) |
| Complexity | Simple | Advanced |

**When to use v1:**
- Simple queries (2-3 filters, all AND)
- Learning/prototyping
- Single-use queries

**When to use v2:**
- Complex queries with OR logic
- Multiple filter groups
- Production systems
- Memory-constrained environments

## See Also

- [QUERY_OPTIMIZATION.md](QUERY_OPTIMIZATION.md) - v1 query system
- [README_ndx.md](README_ndx.md) - NDX index format
- [README_dbf.md](README_dbf.md) - DBF file format
