# Test Files

This directory contains test programs for the DBF/NDX library.

## Pascal Tests

### TESTDBF.PAS
Comprehensive test suite for DBF file operations:
- File creation and opening
- Row reading/writing/updating
- Field operations
- Memo field handling
- Export/import functionality
- Compaction

**Memory**: 8KB stack, 64KB heap

### TESTDBF3.PAS
Creates a small dBase III table for testing NDX index creation.

**Memory**: 8KB stack, 64KB heap

### TESTIDX.PAS
Test suite for NDX index file operations:
- Header reading
- B-tree traversal
- Character search (exact, prefix)
- Numeric search (exact, range)
- Date search (exact, range)

**Memory**: 8KB stack, 16KB heap

## Compiling Pascal Tests

### Free Pascal (FPC)
```bash
# From the tests directory
fpc TESTDBF.PAS -Fu..
fpc TESTDBF3.PAS -Fu..
fpc TESTIDX.PAS -Fu..

# Or from the root directory
fpc tests\TESTDBF.PAS -Fuc:\Users\zphpb\Documents\dbase-main
```

### Turbo Pascal
```bash
# Add parent directory to unit search path
tpc tests\TESTDBF.PAS -Ic:\Users\zphpb\Documents\dbase-main
```

The `{$UNITPATH ..}` directive in each test file tells Free Pascal to look in the parent directory for units (DBF.PAS, DBFINDEX.PAS, ASSERT.PAS).

## Python Tests

All Python test files use pytest:

```bash
# Run all tests
pytest

# Run specific test file
pytest test_dbf_module.py
pytest test_ndx_module.py

# Run with verbose output
pytest -v
```

### Test File Cleanup

**Default behavior**: Test files (DBF, DBT, NDX, TXT, MEM) created during tests are **automatically deleted** after tests pass.

**Keep files for debugging**: Set the `KEEP_TEST_FILES` environment variable:

```bash
# Windows (PowerShell)
$env:KEEP_TEST_FILES=1
pytest test_ndx_module.py

# Windows (CMD)
set KEEP_TEST_FILES=1
pytest test_ndx_module.py

# Linux/Mac
KEEP_TEST_FILES=1 pytest test_ndx_module.py
```

**Note**: Sample files in `samples/` directory (DEVNAME3.NDX, YEAR3.NDX, GAMES3.DBF, etc.) are **never deleted** - they're reference data for validation.

## Memory Optimizations

All Pascal tests have been optimized for minimal memory usage:
- Removed index creation code (use Python instead)
- Pass large structures by reference
- Use global buffers where appropriate
- Reduced buffer sizes to match actual needs

See `../PASCAL_MEMORY_NOTES.md` for details.
