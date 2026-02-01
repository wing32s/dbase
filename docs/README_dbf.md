# Python DBF Module

This is a Python implementation of the Pascal DBF.PAS module for working with dBase (.DBF) files.

## Features

- Create dBase III, IV, and V format files
- Support for memo fields (.DBT files)
- Various field types: Character, Numeric, Logical, Date, Memo
- Proper handling of file headers and field descriptors

## Current Implementation

The current implementation includes:

- Basic data structures for DBF files (DBFColumn, DBFHeader)
- File creation functionality (dbf_file_create, dbf_file_create_dbase3)
- File opening functionality (dbf_file_open)
- Date management (dbf_file_get_date, dbf_file_set_date)
- Language driver management (dbf_file_get_language_driver, dbf_file_set_language_driver)
- Helper functions for string manipulation and data conversion
- Support for memo fields

## Usage

### Opening an Existing DBF File

```python
from dbf_module import dbf_file_open, dbf_file_close

# Open a DBF file (with or without .DBF extension)
dbf = dbf_file_open("myfile")

# Access header information
print(f"File version: 0x{dbf.header.version:02X}")
print(f"Record count: {dbf.header.record_count}")

# Access field information
for field in dbf.header.fields:
    print(f"{field.name}: {field.field_type} ({field.length})")

# Close the file when done
dbf_file_close(dbf)
```

### Creating a DBF File

```python
from dbf_module import DBFColumn, DBFHeader, dbf_file_create, dbf_file_close

# Define fields
fields = [
    DBFColumn(name="ID", field_type="N", length=5, decimals=0),
    DBFColumn(name="NAME", field_type="C", length=30, decimals=0),
    DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0)
]

# Create header
header = DBFHeader()
header.fields = fields
header.field_count = len(fields)

# Set date (optional)
import datetime
now = datetime.datetime.now()
header.year = now.year - 1900  # dBase stores years since 1900
header.month = now.month
header.day = now.day

# Create the file
dbf = dbf_file_create("myfile", header)

# Close when done
dbf_file_close(dbf)
```

### Creating a dBase III File

```python
from dbf_module import DBFColumn, DBFHeader, dbf_file_create_dbase3, dbf_file_close

# Define fields
fields = [
    DBFColumn(name="ID", field_type="N", length=5, decimals=0),
    DBFColumn(name="NAME", field_type="C", length=30, decimals=0)
]

# Create header
header = DBFHeader()
header.fields = fields
header.field_count = len(fields)

# Create the file
dbf = dbf_file_create_dbase3("myfile", header)

# Close when done
dbf_file_close(dbf)
```

### Getting and Setting the Last Update Date

```python
from dbf_module import dbf_file_open, dbf_file_get_date, dbf_file_set_date, dbf_file_close
import datetime

# Open a DBF file
dbf = dbf_file_open("myfile")

# Get the last update date
year, month, day = dbf_file_get_date(dbf)
print(f"Last updated: {year + 1900}-{month:02d}-{day:02d}")

# Set the date to current date
now = datetime.datetime.now()
dbf_file_set_date(dbf, now.year - 1900, now.month, now.day)

# Close the file
dbf_file_close(dbf)
```

**Note:** The year is stored as years since 1900 (e.g., 126 for 2026).

### Getting and Setting the Language Driver

```python
from dbf_module import (
    dbf_file_open, dbf_file_get_language_driver, dbf_file_set_language_driver,
    dbf_file_close, DBF_LANG_US, DBF_LANG_WESTERN_EUROPE, DBF_LANG_JAPAN
)

# Open a dBase IV file
dbf = dbf_file_open("myfile")

# Get the language driver
lang = dbf_file_get_language_driver(dbf)
print(f"Language driver: {lang}")

# Set the language driver to Western Europe
dbf_file_set_language_driver(dbf, DBF_LANG_WESTERN_EUROPE)

# Close the file
dbf_file_close(dbf)
```

**Note:** The language driver field is only used in dBase IV and later. For dBase III files, this field is unused and should remain 0.

**Available Language Driver Constants:**
- `DBF_LANG_US` (1) - US English
- `DBF_LANG_WESTERN_EUROPE` (2) - Western European
- `DBF_LANG_JAPAN` (123) - Japanese

### Exporting and Importing DBF Files

```python
from dbf_module import export_dbf_to_text, import_dbf_from_text

# Export a DBF file to pipe-delimited text
export_dbf_to_text("myfile")
# Creates myfile.TXT with format:
# Line 1: ID|NAME|SALARY
# Line 2: N(5)|C(30)|N(10,2)
# Line 3+: Data rows (when implemented)

# Import a DBF file from text
import_dbf_from_text("myfile")
# Creates myfile.DBF from myfile.TXT
```

**Text File Format:**
- Line 1: Field names separated by pipes (`|`)
- Line 2: Field specifications (e.g., `C(30)`, `N(10,2)`, `L(1)`)
- Line 3+: Data rows (future implementation)

## Field Types

- `C` - Character (string)
- `N` - Numeric (integer or decimal)
- `L` - Logical (boolean)
- `D` - Date (YYYYMMDD format)
- `M` - Memo (text stored in separate .DBT file)

## Version Detection and Memo Fields

### Automatic Version Detection
The module automatically adjusts the version byte based on memo field presence:
- If you specify version 0x04 but include memo fields (type 'M'), it will auto-upgrade to 0x05
- If you specify version 0x05 but have no memo fields, it will auto-downgrade to 0x04
- If you specify version 0 (auto-detect), it will choose 0x04 or 0x05 based on memo fields
- dBase III (0x03) files never support memo fields

### dBase Version Support
- **dBase III (0x03)**: TableFlags and LanguageDriver are unused (set to 0), no memo support
- **dBase IV (0x04)**: TableFlags = 0, LanguageDriver = 1 (US) by default, no memo fields
- **dBase V (0x05)**: Same as IV but with memo field support (.DBT file)

### Memo Fields
- Memo fields (type 'M') store large text data in a separate .DBT file
- Presence of memo fields automatically sets version to 0x05
- Memo files use 512-byte blocks
- Each memo field in the DBF stores a block number pointing to the memo data

## Differences from Pascal Version

- Uses Python naming conventions (snake_case instead of PascalCase)
- Takes advantage of Python's dynamic typing and built-in data structures
- Uses dataclasses for cleaner code
- Returns objects instead of using var parameters
- File handling uses Python's context managers where appropriate

## API Reference

### File Operations
- `dbf_file_create(filename, header)` - Create a new DBF file
- `dbf_file_create_dbase3(filename, header)` - Create a dBase III file
- `dbf_file_open(filename)` - Open an existing DBF file
- `dbf_file_close(dbf)` - Close a DBF file

### Date Operations
- `dbf_file_get_date(dbf)` - Get the last update date (returns tuple: year, month, day)
- `dbf_file_set_date(dbf, year, month, day)` - Set the last update date

### Language Driver Operations
- `dbf_file_get_language_driver(dbf)` - Get the language driver ID
- `dbf_file_set_language_driver(dbf, language_driver)` - Set the language driver ID

### Import/Export Operations
- `export_dbf_to_text(filename)` - Export DBF to pipe-delimited text file
- `import_dbf_from_text(filename)` - Import DBF from pipe-delimited text file
- `build_field_spec(field)` - Build field specification string (e.g., 'N(10,2)')
- `parse_field_spec(spec)` - Parse field specification string

### Utility Functions
- `trim_string(text)` - Trim whitespace from both ends
- `pad_string(text, length)` - Pad string to specified length
- `parse_int(text)` - Parse string to integer
- `parse_bool(text)` - Parse string to boolean

## Future Enhancements

- Add record reading and writing
- Implement record appending
- Add support for indexes
- Implement record deletion
- Add search functionality
