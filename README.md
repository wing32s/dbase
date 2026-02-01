# dbase
A clean room implementation of dBase III and IV suitable for low-memory computers like an XT

## Features

### Pascal Implementation (Memory Optimized)
- **DBF.PAS** - dBase III/IV file operations (8KB stack, 64KB heap)
- **DBFINDEX.PAS** - NDX index reading (8KB stack, 16KB heap)
- **ASSERT.PAS** - Unit testing framework
- Optimized for 8088/8086 systems with limited RAM

### Python Implementation (Full Featured)
- **dbf_module.py** - Complete DBF file operations
- **ndx_module.py** - NDX index creation and searching
- **dbf_query.py** - Query optimization with heap maps
- **assert_module.py** - Testing utilities

## Query Optimization

Two query systems available:

### Simple Queries (`dbf_query.py`)
```python
from dbf_query import DBFQueryBuilder

query = DBFQueryBuilder("games.DBF")
query.filter_by_ndx_prefix("title.NDX", "King")
query.filter_by_value("year", 1984)
recnos = query.execute()
```

### Advanced Queries (`dbf_query_v2.py`)
```python
from dbf_query_v2 import DBFQuery, FilterGroup, GroupOp, equal, like

query = DBFQuery("games.DBF")

# Group 1: Title filters (OR)
group1 = FilterGroup(GroupOp.OR)
group1.add_filter(like("title", "King", "title.NDX"))
group1.add_filter(like("title", "Queen", "title.NDX"))
query.add_group(group1)

# Group 2: Year and player filters (AND)
group2 = FilterGroup(GroupOp.AND)
group2.add_filter(equal("year", 1984))
group2.add_filter(equal("maxplay", 4))
query.add_group(group2)

recnos = query.execute()
```

**Features:**
- Up to 4 filter groups with OR/AND logic
- Up to 8 filters per group
- Unified heap map (33% memory savings)
- 40-160x faster than full table scans

See [docs/QUERY_ARCHITECTURE.md](docs/QUERY_ARCHITECTURE.md) for details.

## Documentation

- [README_dbf.md](docs/README_dbf.md) - DBF file format and operations
- [README_ndx.md](docs/README_ndx.md) - NDX index format and searching
- [QUERY_ARCHITECTURE.md](docs/QUERY_ARCHITECTURE.md) - Advanced query system (v2)
- [QUERY_MEMORY_ANALYSIS.md](docs/QUERY_MEMORY_ANALYSIS.md) - Memory analysis for Pascal port
- [QUERY_OPTIMIZATION.md](docs/QUERY_OPTIMIZATION.md) - Simple query system (v1)
- [PASCAL_MEMORY_NOTES.md](PASCAL_MEMORY_NOTES.md) - Memory optimization details
- [IMPLEMENTATION_STATUS.md](docs/IMPLEMENTATION_STATUS.md) - Feature status

## Testing

```bash
# Python tests
pytest tests/

# Keep test files for inspection
$env:KEEP_TEST_FILES=1
pytest tests/test_ndx_module.py

# Pascal tests (from tests directory)
fpc TESTDBF.PAS -Fu..
fpc TESTIDX.PAS -Fu..
```
