"""
Python implementation of the Pascal DBF.PAS module.
This module provides functionality for working with dBase (.DBF) files.
"""

import os
import struct
from dataclasses import dataclass
from typing import List, Dict, Any, Optional, Union, BinaryIO, Tuple


# Constants
DBF_MAX_FIELDS = 64
DBF_MAX_RECORD_SIZE = 4096
DBF_MAX_ROW_IDS = 2000
DBF_LANG_US = 0x01
DBF_LANG_WESTERN_EUROPE = 0x02
DBF_LANG_JAPAN = 0x7B
DBF_MEMO_BLOCK_SIZE = 512


# Data structures
@dataclass
class DBFColumn:
    """Represents a column/field in a DBF file."""
    name: str  # Field name (max 11 chars)
    field_type: str  # 'C', 'N', 'L', etc.
    length: int  # Field length in bytes
    decimals: int  # Number of decimal places (for numeric)
    offset: int = 0  # offset within record; first field starts at 1


@dataclass
class DBFHeader:
    """Represents the header of a DBF file."""
    version: int = 0  # dBase version, e.g., 0x03 for dBase III
    year: int = 0  # Last update year (since 1900)
    month: int = 0  # Last update month
    day: int = 0  # Last update day
    record_count: int = 0  # Number of records
    header_size: int = 0  # Header size in bytes
    record_size: int = 0  # Record size in bytes
    table_flags: int = 0  # dBase IV table flags
    language_driver: int = 0  # dBase IV language driver id
    fields: List[DBFColumn] = None  # Field descriptors
    field_count: int = 0  # Actual number of fields used

    def __post_init__(self):
        if self.fields is None:
            self.fields = []


class DBFFile:
    """Internal representation of a DBF file."""
    def __init__(self):
        self.file = None
        self.header = DBFHeader()
        self.is_open = False


# Helper functions
def read_dbf_header(file: BinaryIO) -> DBFHeader:
    """Read a DBF header from a file."""
    header = DBFHeader()
    
    # Read main file header (32 bytes)
    buf = file.read(32)
    header.version = buf[0]
    header.year = buf[1]
    header.month = buf[2]
    header.day = buf[3]
    header.record_count = struct.unpack("<L", buf[4:8])[0]
    header.header_size = struct.unpack("<H", buf[8:10])[0]
    header.record_size = struct.unpack("<H", buf[10:12])[0]
    header.table_flags = buf[28]
    header.language_driver = buf[29]
    
    # Read field descriptors until 0x0D (field descriptor terminator)
    fields = []
    i = 0
    while i < DBF_MAX_FIELDS:
        # Peek 1 byte
        peek_byte = file.read(1)
        if not peek_byte or peek_byte[0] == 0x0D:
            break
        
        # Rewind 1 byte and read descriptor
        file.seek(file.tell() - 1)
        field_buf = file.read(32)
        
        # Extract field name (up to 11 bytes, null-terminated)
        field_name = ""
        for j in range(11):
            if field_buf[j] != 0:
                field_name += chr(field_buf[j])
        
        # Create field descriptor
        field = DBFColumn(
            name=field_name,
            field_type=chr(field_buf[11]),
            length=field_buf[16],
            decimals=field_buf[17],
            offset=0  # Will be calculated later
        )
        fields.append(field)
        i += 1
    
    header.fields = fields
    header.field_count = len(fields)
    
    # Calculate field offsets
    offset = 1  # First byte is delete flag
    for field in header.fields:
        field.offset = offset
        offset += field.length
    
    header.record_size = offset
    
    return header


def trim_string(text: str) -> str:
    """Trim whitespace from both ends of a string."""
    return text.strip()


def pad_string(text: str, length: int) -> str:
    """Pad a string to the specified length with spaces."""
    if len(text) > length:
        return text[:length]
    return text.ljust(length)


def parse_int(text: str) -> int:
    """Parse a string to an integer."""
    try:
        return int(trim_string(text))
    except ValueError:
        return 0


def parse_bool(text: str) -> bool:
    """Parse a string to a boolean."""
    text = trim_string(text)
    if not text:
        return False
    return text[0].upper() in ('T', 'Y', '1')


def has_memo_field(header: DBFHeader) -> bool:
    """Check if the DBF header contains memo fields."""
    for field in header.fields:
        if field.field_type.upper() == 'M':
            return True
    return False


def init_dbf_header(header: DBFHeader) -> None:
    """Initialize a DBF header with proper values."""
    has_memo = has_memo_field(header)
    
    # For dBase III, both table_flags and language_driver should be 0 (unused)
    if header.version == 0x03:
        header.table_flags = 0
        header.language_driver = 0
    else:
        # For dBase IV and V
        header.table_flags = 0
        # Only set language driver if not already set
        if header.language_driver == 0:
            header.language_driver = DBF_LANG_US
    
    # Set version based on memo field presence
    if header.version == 0:
        if has_memo:
            header.version = 0x05
        else:
            header.version = 0x04
    elif header.version == 0x04 and has_memo:
        header.version = 0x05
    elif header.version == 0x05 and not has_memo:
        header.version = 0x04
    
    header.record_count = 0
    
    # Calculate field offsets and record size
    offset = 1  # First byte is delete flag
    for i, field in enumerate(header.fields):
        field.offset = offset
        offset += field.length
    
    header.record_size = offset
    header.header_size = 32 + (header.field_count * 32) + 1


def write_dbf_header(file: BinaryIO, header: DBFHeader) -> None:
    """Write the DBF header to a file."""
    # Write main file header (32 bytes)
    buf = bytearray(32)
    buf[0] = header.version
    buf[1] = header.year
    buf[2] = header.month
    buf[3] = header.day
    buf[4:8] = struct.pack("<L", header.record_count)
    buf[8:10] = struct.pack("<H", header.header_size)
    buf[10:12] = struct.pack("<H", header.record_size)
    buf[28] = header.table_flags
    buf[29] = header.language_driver
    file.write(buf)
    
    # Write field descriptors (32 bytes each)
    for field in header.fields[:header.field_count]:
        buf = bytearray(32)
        field_name_bytes = field.name.encode('ascii', errors='replace')
        buf[:len(field_name_bytes)] = field_name_bytes[:11]
        buf[11] = ord(field.field_type)
        buf[16] = field.length
        buf[17] = field.decimals
        file.write(buf)
    
    # Field descriptor terminator (0x0D)
    file.write(bytes([0x0D]))
    
    # Write file terminator (0x1A) to indicate no rows
    file.write(bytes([0x1A]))


def dbf_memo_create(filename: str) -> None:
    """Create an empty memo file with proper header."""
    with open(f"{filename}.DBT", "wb") as f:
        # Initialize memo file with header block
        buf = bytearray(DBF_MEMO_BLOCK_SIZE)
        # Next free block = 1 (first block after header)
        next_free = 1
        buf[0:4] = struct.pack("<L", next_free)
        # Block size
        buf[4:6] = struct.pack("<H", DBF_MEMO_BLOCK_SIZE)
        f.write(buf)


# Main DBF functions
def dbf_file_open(filename: str) -> DBFFile:
    """
    Open an existing DBF file.
    
    Args:
        filename: The path to the DBF file (with or without extension)
        
    Returns:
        A DBFFile object representing the opened file
    """
    # Ensure the filename has .DBF extension
    if not filename.upper().endswith('.DBF'):
        filename = filename + '.DBF'
    
    # Create DBF object
    dbf = DBFFile()
    
    try:
        # Open the file for reading and writing
        dbf.file = open(filename, "rb+")
        
        # Read the header
        dbf.header = read_dbf_header(dbf.file)
        dbf.is_open = True
        
        return dbf
    except Exception as e:
        if dbf.file:
            dbf.file.close()
        raise IOError(f"Error opening DBF file: {str(e)}")


def dbf_file_create(filename: str, header: DBFHeader) -> DBFFile:
    """
    Create a new DBF file with the specified header.
    
    Args:
        filename: The base name of the file (without extension)
        header: The DBF header structure
        
    Returns:
        A DBFFile object representing the created file (opened in read-write mode)
    """
    dbf = DBFFile()
    
    # Open the file for writing
    with open(f"{filename}.DBF", "wb") as f:
        # Initialize the header
        init_dbf_header(header)
        
        # Write the header to the file
        write_dbf_header(f, header)
    
    # Create memo file if needed
    if header.version == 0x05:
        dbf_memo_create(filename)
    
    # Reopen in read-write mode
    dbf.file = open(f"{filename}.DBF", "rb+")
    dbf.header = header
    dbf.is_open = True
    
    return dbf


def dbf_file_create_dbase3(filename: str, header: DBFHeader) -> DBFFile:
    """
    Create a new dBase III file with the specified header.
    
    Args:
        filename: The base name of the file (without extension)
        header: The DBF header structure
        
    Returns:
        A DBFFile object representing the created file
    """
    header.version = 0x03
    header.table_flags = 0
    header.language_driver = 0
    return dbf_file_create(filename, header)


def dbf_file_close(dbf: DBFFile) -> None:
    """Close a DBF file."""
    if dbf and dbf.is_open and dbf.file:
        dbf.file.close()
        dbf.is_open = False


def dbf_file_append_row(dbf: DBFFile, values: list) -> None:
    """
    Append a row to the DBF file.
    
    Args:
        dbf: The DBF file object
        values: List of field values as strings (1-indexed, so values[0] is ignored)
    """
    if not dbf or not dbf.is_open or not dbf.file:
        return
    
    # Seek to end of file (before EOF marker)
    dbf.file.seek(0, 2)  # Seek to end
    file_size = dbf.file.tell()
    
    # Back up 1 byte to overwrite the EOF marker
    if file_size > 0:
        dbf.file.seek(file_size - 1)
    
    # Build the row buffer
    row_buffer = bytearray(dbf.header.record_size)
    
    # First byte is delete flag (space = not deleted)
    row_buffer[0] = ord(' ')
    
    # Fill in each field
    for i in range(1, dbf.header.field_count + 1):
        field = dbf.header.fields[i - 1]
        value = values[i] if i < len(values) else ''
        
        # Get field offset and length
        offset = field.offset
        length = field.length
        
        # Truncate or pad value to field length
        if len(value) > length:
            value = value[:length]
        else:
            value = value.ljust(length, ' ')
        
        # Write value to buffer
        for j in range(length):
            row_buffer[offset + j] = ord(value[j])
    
    # Write the row
    dbf.file.write(row_buffer)
    
    # Update record count
    dbf.header.record_count += 1
    
    # Update record count in header
    old_pos = dbf.file.tell()
    dbf.file.seek(4)
    dbf.file.write(struct.pack("<L", dbf.header.record_count))
    dbf.file.seek(old_pos)
    
    # Write EOF marker
    dbf.file.write(b'\x1A')
    
    # Flush to disk
    dbf.file.flush()


def dbf_file_read_row(dbf: DBFFile) -> list:
    """
    Read a row from the current position in the DBF file.
    
    Args:
        dbf: The DBF file object
        
    Returns:
        List of field values as strings (1-indexed, so result[0] is delete flag)
    """
    if not dbf or not dbf.is_open or not dbf.file:
        return []
    
    # Read the row data
    row_data = dbf.file.read(dbf.header.record_size)
    
    if len(row_data) < dbf.header.record_size:
        return []
    
    # Parse fields
    result = [''] * (dbf.header.field_count + 1)
    
    # First byte is delete flag
    result[0] = chr(row_data[0])
    
    # Extract each field
    for i in range(1, dbf.header.field_count + 1):
        field = dbf.header.fields[i - 1]
        offset = field.offset
        length = field.length
        
        # Extract field value
        field_bytes = row_data[offset:offset + length]
        field_value = field_bytes.decode('utf-8', errors='replace')
        
        result[i] = field_value
    
    return result


def dbf_file_seek_to_row(dbf: DBFFile, row_index: int) -> None:
    """
    Seek to a specific row in the DBF file.
    
    Args:
        dbf: The DBF file object
        row_index: Zero-based row index
    """
    if not dbf or not dbf.is_open or not dbf.file:
        return
    
    # Calculate position: header + (row_index * record_size)
    position = dbf.header.header_size + (row_index * dbf.header.record_size)
    dbf.file.seek(position)


def dbf_file_seek_to_first_row(dbf: DBFFile) -> None:
    """
    Seek to the first row in the DBF file.
    
    Args:
        dbf: The DBF file object
    """
    dbf_file_seek_to_row(dbf, 0)


def dbf_file_get_actual_row_count(dbf: DBFFile) -> int:
    """
    Get the actual row count from the DBF file.
    
    Args:
        dbf: The DBF file object
        
    Returns:
        Number of rows in the file
    """
    if not dbf or not dbf.header:
        return 0
    
    return dbf.header.record_count


def dbf_file_set_row_deleted(dbf: DBFFile, row_index: int, deleted: bool) -> None:
    """
    Mark a row as deleted or undeleted.
    
    Args:
        dbf: The DBF file object
        row_index: Zero-based row index
        deleted: True to mark as deleted, False to undelete
    """
    if not dbf or not dbf.is_open or not dbf.file:
        return
    
    # Seek to the row
    dbf_file_seek_to_row(dbf, row_index)
    
    # Write the delete flag (first byte of the row)
    flag = ord('*') if deleted else ord(' ')
    dbf.file.write(bytes([flag]))
    
    # Flush to disk
    dbf.file.flush()


def dbf_file_write_row(dbf: DBFFile, values: list) -> None:
    """
    Write a row at the current position in the DBF file.
    This overwrites the existing row data.
    
    Args:
        dbf: The DBF file object
        values: List of field values as strings (1-indexed, so values[0] is ignored)
    """
    if not dbf or not dbf.is_open or not dbf.file:
        return
    
    # Build the row buffer
    row_buffer = bytearray(dbf.header.record_size)
    
    # First byte is delete flag (space = not deleted)
    row_buffer[0] = ord(' ')
    
    # Fill in each field
    for i in range(1, dbf.header.field_count + 1):
        field = dbf.header.fields[i - 1]
        value = values[i] if i < len(values) else ''
        
        # Get field offset and length
        offset = field.offset
        length = field.length
        
        # Truncate or pad value to field length
        if len(value) > length:
            value = value[:length]
        else:
            value = value.ljust(length, ' ')
        
        # Write value to buffer
        for j in range(length):
            row_buffer[offset + j] = ord(value[j])
    
    # Write the row at current position
    dbf.file.write(row_buffer)
    
    # Flush to disk
    dbf.file.flush()


def dbf_file_get_field_str(row: list, dbf: DBFFile, field_index: int) -> str:
    """
    Get a field value from a row buffer.
    
    Args:
        row: The row buffer (from dbf_file_read_row)
        dbf: The DBF file object
        field_index: 1-based field index
        
    Returns:
        Field value as string
    """
    if not dbf or not row or field_index < 1 or field_index > dbf.header.field_count:
        return ''
    
    return row[field_index]


def dbf_file_set_field_str(row: list, dbf: DBFFile, field_index: int, value: str) -> None:
    """
    Set a field value in a row buffer.
    
    Args:
        row: The row buffer (from dbf_file_read_row)
        dbf: The DBF file object
        field_index: 1-based field index
        value: New field value
    """
    if not dbf or not row or field_index < 1 or field_index > dbf.header.field_count:
        return
    
    field = dbf.header.fields[field_index - 1]
    length = field.length
    
    # Truncate or pad value to field length
    if len(value) > length:
        value = value[:length]
    else:
        value = value.ljust(length, ' ')
    
    # Update the row buffer
    row[field_index] = value


def dbf_file_get_date(dbf: DBFFile) -> Tuple[int, int, int]:
    """
    Get the last update date from a DBF file.
    
    Args:
        dbf: The DBF file object
        
    Returns:
        A tuple of (year, month, day) where year is since 1900
    """
    if not dbf or not dbf.header:
        return (0, 0, 0)
    
    return (dbf.header.year, dbf.header.month, dbf.header.day)


def dbf_file_set_date(dbf: DBFFile, year: int, month: int, day: int) -> None:
    """
    Set the last update date in a DBF file.
    
    Args:
        dbf: The DBF file object
        year: Year since 1900 (e.g., 126 for 2026)
        month: Month (1-12)
        day: Day (1-31)
    """
    if not dbf or not dbf.is_open or not dbf.file:
        return
    
    # Update the header in memory
    dbf.header.year = year
    dbf.header.month = month
    dbf.header.day = day
    
    # Update the date in the file
    old_pos = dbf.file.tell()
    dbf.file.seek(1)  # Date starts at byte 1
    dbf.file.write(bytes([year, month, day]))
    dbf.file.seek(old_pos)  # Restore position
    dbf.file.flush()  # Ensure it's written to disk


def dbf_file_get_language_driver(dbf: DBFFile) -> int:
    """
    Get the language driver ID from a DBF file.
    
    Args:
        dbf: The DBF file object
        
    Returns:
        The language driver ID (0 for dBase III, 1 for US, etc.)
    """
    if not dbf or not dbf.header:
        return 0
    
    return dbf.header.language_driver


def dbf_file_set_language_driver(dbf: DBFFile, language_driver: int) -> None:
    """
    Set the language driver ID in a DBF file.
    
    Note: This should only be used with dBase IV and later versions.
    For dBase III, the language driver field is unused and should remain 0.
    
    Args:
        dbf: The DBF file object
        language_driver: The language driver ID (e.g., 1 for US, 2 for Western Europe)
    """
    if not dbf or not dbf.is_open or not dbf.file:
        return
    
    # Update the header in memory
    dbf.header.language_driver = language_driver
    
    # Update the language driver in the file
    old_pos = dbf.file.tell()
    dbf.file.seek(29)  # Language driver is at byte 29
    dbf.file.write(bytes([language_driver]))
    dbf.file.seek(old_pos)  # Restore position
    dbf.file.flush()  # Ensure it's written to disk


def build_field_spec(field: DBFColumn) -> str:
    """
    Build a field specification string (e.g., 'C(30)' or 'N(10,2)').
    
    Args:
        field: The field column definition
        
    Returns:
        Field specification string
    """
    spec = f"{field.field_type}({field.length}"
    if field.decimals > 0:
        spec += f",{field.decimals}"
    spec += ")"
    return spec


def parse_field_spec(spec: str) -> Tuple[str, int, int]:
    """
    Parse a field specification string.
    
    Args:
        spec: Field specification string (e.g., 'C(30)' or 'N(10,2)')
        
    Returns:
        Tuple of (field_type, length, decimals)
    """
    spec = spec.strip()
    if len(spec) < 3:
        return ('C', 1, 0)
    
    field_type = spec[0].upper()
    
    # Find parentheses
    paren_start = spec.find('(')
    paren_end = spec.find(')')
    
    if paren_start == -1 or paren_end == -1 or paren_end <= paren_start + 1:
        return ('C', 1, 0)
    
    # Extract content between parentheses
    content = spec[paren_start + 1:paren_end]
    
    # Check for comma (decimals)
    if ',' in content:
        parts = content.split(',')
        try:
            length = int(parts[0].strip())
            decimals = int(parts[1].strip())
        except ValueError:
            return ('C', 1, 0)
    else:
        try:
            length = int(content.strip())
            decimals = 0
        except ValueError:
            return ('C', 1, 0)
    
    if length <= 0 or length > 255:
        return ('C', 1, 0)
    
    return (field_type, length, decimals)


def export_dbf_to_text(filename: str) -> None:
    """
    Export a DBF file to a pipe-delimited text file.
    
    The text file format:
    - Line 1: Field names separated by pipes (|)
    - Line 2: Field specifications separated by pipes (|)
    - Line 3+: Data rows separated by pipes (|)
    
    Args:
        filename: Base filename (without extension)
    """
    dbf_filename = filename if filename.endswith('.DBF') else filename + '.DBF'
    txt_filename = filename.replace('.DBF', '') + '.TXT'
    
    # Open the DBF file
    dbf = dbf_file_open(dbf_filename)
    
    # Open text file for writing
    with open(txt_filename, 'w', encoding='utf-8') as f:
        # Write field names
        field_names = [field.name for field in dbf.header.fields]
        f.write('|'.join(field_names) + '\n')
        
        # Write field specifications
        field_specs = [build_field_spec(field) for field in dbf.header.fields]
        f.write('|'.join(field_specs) + '\n')
        
        # Write data rows (skip deleted rows)
        row_count = dbf_file_get_actual_row_count(dbf)
        for row_idx in range(row_count):
            dbf_file_seek_to_row(dbf, row_idx)
            row = dbf_file_read_row(dbf)
            
            # Skip deleted rows
            if row[0] == '*':
                continue
            
            # Skip delete flag (row[0]), write fields 1 to field_count
            row_values = [row[i].strip() for i in range(1, dbf.header.field_count + 1)]
            f.write('|'.join(row_values) + '\n')
    
    # Close the DBF file
    dbf_file_close(dbf)


def import_dbf_from_text(filename: str) -> None:
    """
    Import a DBF file from a pipe-delimited text file.
    
    Args:
        filename: Base filename (without extension)
    """
    txt_filename = filename if filename.endswith('.TXT') else filename + '.TXT'
    dbf_filename = filename.replace('.TXT', '')
    
    # Read the text file
    with open(txt_filename, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    if len(lines) < 2:
        raise ValueError("Text file must have at least 2 lines (field names and specs)")
    
    # Parse field names
    field_names = [name.strip() for name in lines[0].strip().split('|')]
    
    # Parse field specifications
    field_specs = [spec.strip() for spec in lines[1].strip().split('|')]
    
    if len(field_names) != len(field_specs):
        raise ValueError("Number of field names must match number of field specs")
    
    # Build header
    fields = []
    for name, spec in zip(field_names, field_specs):
        field_type, length, decimals = parse_field_spec(spec)
        # Truncate name to 11 characters
        if len(name) > 11:
            name = name[:11]
        fields.append(DBFColumn(name=name, field_type=field_type, length=length, decimals=decimals))
    
    header = DBFHeader()
    header.fields = fields
    header.field_count = len(fields)
    
    # Set current date
    import datetime
    now = datetime.datetime.now()
    header.year = now.year - 1900
    header.month = now.month
    header.day = now.day
    
    # Create the DBF file
    has_memo = any(field.field_type == 'M' for field in fields)
    if has_memo:
        dbf = dbf_file_create(dbf_filename, header)
    else:
        dbf = dbf_file_create_dbase3(dbf_filename, header)
    
    # Import data rows (lines 2+)
    for i in range(2, len(lines)):
        line = lines[i].strip()
        if not line:
            continue
        
        # Parse row values
        row_values = [val.strip() for val in line.split('|')]
        
        # Build values array (1-indexed, values[0] is ignored)
        values = ['']  # Index 0 is ignored
        values.extend(row_values)
        
        # Append the row
        dbf_file_append_row(dbf, values)
    
    # Close the DBF file
    dbf_file_close(dbf)


def dbf_memo_write(memo_filename: str, memo_type: int, text: str) -> int:
    """
    Write text data to a memo file.
    
    Args:
        memo_filename: Path to the memo file (with .DBT extension)
        memo_type: Memo type (usually 1 for text)
        text: Text to write
        
    Returns:
        Block number where the memo was written
    """
    # Convert text to bytes
    text_bytes = text.encode('utf-8') if isinstance(text, str) else text
    return dbf_memo_write_buffer(memo_filename, memo_type, text_bytes)


def _get_dbf_version(memo_filename: str) -> int:
    """
    Get the DBF version by reading the corresponding DBF file.
    
    Args:
        memo_filename: Path to the memo file (.DBT)
        
    Returns:
        DBF version byte (0x03, 0x04, 0x05, etc.) or 0x04 as default
    """
    # Convert .DBT to .DBF filename
    dbf_filename = memo_filename.replace('.DBT', '.DBF').replace('.dbt', '.dbf')
    
    try:
        with open(dbf_filename, 'rb') as f:
            version = f.read(1)
            if len(version) == 1:
                return version[0]
    except FileNotFoundError:
        pass
    
    # Default to dBase IV format
    return 0x04


def dbf_memo_write_buffer(memo_filename: str, memo_type: int, data: bytes) -> int:
    """
    Write binary data to a memo file.
    
    Format depends on dBase version:
    - dBase III (0x03): Just data + 0x1A terminator (no header)
    - dBase IV+ (0x04, 0x05): Type (4 bytes) + Length (4 bytes) + data + 0x1A
    
    Args:
        memo_filename: Path to the memo file (with .DBT extension)
        memo_type: Memo type (1 for text, 2 for binary, etc.) - ignored for dBase III
        data: Binary data to write
        
    Returns:
        Block number where the memo was written
    """
    if not memo_filename.endswith('.DBT'):
        memo_filename += '.DBT'
    
    # Ensure data is bytes
    if isinstance(data, str):
        data = data.encode('utf-8')
    
    # Detect DBF version
    dbf_version = _get_dbf_version(memo_filename)
    is_dbase3 = (dbf_version == 0x03)
    
    # Open or create the memo file
    try:
        with open(memo_filename, 'rb+') as f:
            # Read next free block from header
            f.seek(0)
            next_free_bytes = f.read(4)
            next_free = struct.unpack("<L", next_free_bytes)[0]
            if next_free < 1:
                next_free = 1
    except FileNotFoundError:
        # Create new memo file
        with open(memo_filename, 'wb') as f:
            buf = bytearray(DBF_MEMO_BLOCK_SIZE)
            next_free = 1
            buf[0:4] = struct.pack("<L", next_free)
            buf[4:6] = struct.pack("<H", DBF_MEMO_BLOCK_SIZE)
            f.write(buf)
    
    # Write the memo data
    with open(memo_filename, 'rb+') as f:
        start_block = next_free
        start_pos = start_block * DBF_MEMO_BLOCK_SIZE
        
        # Seek to start position
        f.seek(start_pos)
        
        if is_dbase3:
            # dBase III format: just data + 0x1A terminator (no header)
            f.write(data)
            f.write(b'\x1A')
            
            # Calculate total length and blocks needed
            total_len = len(data) + 1  # data + EOF
            blocks_needed = (total_len + DBF_MEMO_BLOCK_SIZE - 1) // DBF_MEMO_BLOCK_SIZE
            pad_len = (blocks_needed * DBF_MEMO_BLOCK_SIZE) - total_len
        else:
            # dBase IV+ format: type + length + data + 0x1A
            # Write memo type (4 bytes, little endian)
            f.write(struct.pack("<L", memo_type))
            
            # Write memo length (4 bytes, little endian)
            f.write(struct.pack("<L", len(data)))
            
            # Write data
            f.write(data)
            
            # Write EOF marker (0x1A)
            f.write(b'\x1A')
            
            # Calculate total length and blocks needed
            total_len = 8 + len(data) + 1  # header + data + EOF
            blocks_needed = (total_len + DBF_MEMO_BLOCK_SIZE - 1) // DBF_MEMO_BLOCK_SIZE
            pad_len = (blocks_needed * DBF_MEMO_BLOCK_SIZE) - total_len
        
        # Write padding
        if pad_len > 0:
            f.write(b'\x00' * pad_len)
        
        # Update next free block in header
        next_free = start_block + blocks_needed
        f.seek(0)
        f.write(struct.pack("<L", next_free))
    
    return start_block


def dbf_memo_get_info(memo_filename: str, start_block: int) -> Tuple[int, int]:
    """
    Get information about a memo field.
    
    For dBase III: Returns (1, length) where length is calculated by finding 0x1A
    For dBase IV+: Returns (memo_type, length) from the 8-byte header
    
    Args:
        memo_filename: Path to the memo file
        start_block: Block number where the memo starts
        
    Returns:
        Tuple of (memo_type, length) or (0, 0) if not found
    """
    if not memo_filename.endswith('.DBT'):
        memo_filename += '.DBT'
    
    if start_block <= 0:
        return (0, 0)
    
    # Detect DBF version
    dbf_version = _get_dbf_version(memo_filename)
    is_dbase3 = (dbf_version == 0x03)
    
    try:
        with open(memo_filename, 'rb') as f:
            start_pos = start_block * DBF_MEMO_BLOCK_SIZE
            
            # Check if position is within file
            f.seek(0, 2)  # Seek to end
            file_size = f.tell()
            if file_size <= start_pos:
                return (0, 0)
            
            # Seek to memo position
            f.seek(start_pos)
            
            if is_dbase3:
                # dBase III: no header, find length by scanning for 0x1A
                memo_type = 1  # Always text for dBase III
                memo_len = 0
                
                # Read up to end of file or max reasonable size
                max_read = min(file_size - start_pos, 1048576)  # 1MB max
                data = f.read(max_read)
                
                # Find 0x1A terminator
                terminator_pos = data.find(b'\x1A')
                if terminator_pos >= 0:
                    memo_len = terminator_pos
                else:
                    memo_len = len(data)
                
                return (memo_type, memo_len)
            else:
                # dBase IV+: read header
                # Read memo type
                memo_type_bytes = f.read(4)
                if len(memo_type_bytes) < 4:
                    return (0, 0)
                memo_type = struct.unpack("<L", memo_type_bytes)[0]
                
                # Read memo length
                memo_len_bytes = f.read(4)
                if len(memo_len_bytes) < 4:
                    return (0, 0)
                memo_len = struct.unpack("<L", memo_len_bytes)[0]
                
                if memo_len < 0:
                    memo_len = 0
                
                return (memo_type, memo_len)
    except FileNotFoundError:
        return (0, 0)


def dbf_memo_read_small(memo_filename: str, start_block: int) -> Tuple[int, any]:
    """
    Read a small memo field (up to 64KB).
    
    Args:
        memo_filename: Path to the memo file
        start_block: Block number where the memo starts
        
    Returns:
        Tuple of (memo_type, data) where data is:
        - str for text memos (type 1)
        - bytes for binary memos (type 2)
        - (0, '') if not found
    """
    # Get the actual memo length
    memo_type, memo_len = dbf_memo_get_info(memo_filename, start_block)
    
    if memo_type == 0:
        return (0, '')
    
    # Read only the actual data length (not padded blocks)
    _, data = dbf_memo_read_buffer(memo_filename, start_block, memo_len)
    
    # For text memos (type 1), decode as UTF-8
    # For binary memos (type 2), return raw bytes
    if memo_type == 1:
        text = data.decode('utf-8', errors='replace')
        return (memo_type, text)
    else:
        return (memo_type, data)


def dbf_memo_read_binary(memo_filename: str, start_block: int, max_size: int = 1048576) -> Tuple[int, bytes]:
    """
    Read a memo field as binary data.
    
    Args:
        memo_filename: Path to the memo file
        start_block: Block number where the memo starts
        max_size: Maximum size to read (default 1MB)
        
    Returns:
        Tuple of (memo_type, data) or (0, b'') if not found
    """
    return dbf_memo_read_buffer(memo_filename, start_block, max_size)


def dbf_memo_read_chunk(memo_filename: str, start_block: int, offset: int, buf_size: int) -> Tuple[bool, bytes]:
    """
    Read a chunk of memo data.
    
    Args:
        memo_filename: Path to the memo file
        start_block: Block number where the memo starts
        offset: Offset within the memo data (relative to data start, not block start)
        buf_size: Size of buffer to read
        
    Returns:
        Tuple of (success, data)
    """
    if start_block <= 0 or buf_size == 0 or offset < 0:
        return (False, b'')
    
    memo_type, memo_len = dbf_memo_get_info(memo_filename, start_block)
    
    if memo_type == 0:
        return (False, b'')
    
    if offset >= memo_len:
        return (True, b'')  # Valid but no data to read
    
    if not memo_filename.endswith('.DBT'):
        memo_filename += '.DBT'
    
    # Detect DBF version
    dbf_version = _get_dbf_version(memo_filename)
    is_dbase3 = (dbf_version == 0x03)
    
    try:
        with open(memo_filename, 'rb') as f:
            start_pos = start_block * DBF_MEMO_BLOCK_SIZE
            
            if is_dbase3:
                # dBase III: no header
                f.seek(start_pos + offset)
            else:
                # dBase IV+: skip 8-byte header
                f.seek(start_pos + 8 + offset)
            
            # Calculate how much to read
            to_read = min(buf_size, memo_len - offset)
            
            # Read the data
            data = f.read(to_read)
            
            return (True, data)
    except FileNotFoundError:
        return (False, b'')


def dbf_memo_read_buffer(memo_filename: str, start_block: int, buf_size: int) -> Tuple[int, bytes]:
    """
    Read memo data into a buffer.
    
    Args:
        memo_filename: Path to the memo file
        start_block: Block number where the memo starts
        buf_size: Size of buffer
        
    Returns:
        Tuple of (memo_type, data)
    """
    memo_type, memo_len = dbf_memo_get_info(memo_filename, start_block)
    
    if memo_type == 0:
        return (0, b'')
    
    # Determine how much to read
    read_size = min(buf_size, memo_len)
    
    if not memo_filename.endswith('.DBT'):
        memo_filename += '.DBT'
    
    # Detect DBF version
    dbf_version = _get_dbf_version(memo_filename)
    is_dbase3 = (dbf_version == 0x03)
    
    try:
        with open(memo_filename, 'rb') as f:
            start_pos = start_block * DBF_MEMO_BLOCK_SIZE
            
            if is_dbase3:
                # dBase III: no header, data starts immediately
                f.seek(start_pos)
            else:
                # dBase IV+: skip 8-byte header
                f.seek(start_pos + 8)
            
            # Read the data
            data = f.read(read_size)
            
            return (memo_type, data)
    except FileNotFoundError:
        return (0, b'')


def dbf_memo_write_at_block(memo_filename: str, memo_type: int, text: str, block_num: int) -> int:
    """
    Write text data to a specific block in a memo file.
    
    Args:
        memo_filename: Path to the memo file
        memo_type: Type of memo (1 for text, 2 for binary)
        text: Text data to write
        block_num: Specific block number to write at
        
    Returns:
        The block number where the memo was written
    """
    if not memo_filename.endswith('.DBT'):
        memo_filename += '.DBT'
    
    # Convert text to bytes
    data = text.encode('latin-1')
    
    return dbf_memo_write_buffer_at_block(memo_filename, memo_type, data, block_num)


def dbf_memo_write_buffer_at_block(memo_filename: str, memo_type: int, data: bytes, block_num: int) -> int:
    """
    Write binary data to a specific block in a memo file.
    
    Args:
        memo_filename: Path to the memo file
        memo_type: Type of memo (1 for text, 2 for binary)
        data: Binary data to write
        block_num: Specific block number to write at
        
    Returns:
        The block number where the memo was written
    """
    if not memo_filename.endswith('.DBT'):
        memo_filename += '.DBT'
    
    # Detect DBF version
    dbf_version = _get_dbf_version(memo_filename)
    is_dbase3 = (dbf_version == 0x03)
    
    data_len = len(data)
    
    # Calculate blocks needed
    if is_dbase3:
        # dBase III: data + terminator
        blocks_needed = (data_len + 1 + DBF_MEMO_BLOCK_SIZE - 1) // DBF_MEMO_BLOCK_SIZE
    else:
        # dBase IV+: header (8 bytes) + data
        blocks_needed = (8 + data_len + DBF_MEMO_BLOCK_SIZE - 1) // DBF_MEMO_BLOCK_SIZE
    
    # Write at the specified block
    with open(memo_filename, 'r+b') as f:
        start_pos = block_num * DBF_MEMO_BLOCK_SIZE
        f.seek(start_pos)
        
        if is_dbase3:
            # dBase III format: raw data + 0x1A terminator
            f.write(data)
            f.write(b'\x1A')
            # Pad to block boundary
            bytes_written = data_len + 1
            padding = (blocks_needed * DBF_MEMO_BLOCK_SIZE) - bytes_written
            if padding > 0:
                f.write(b'\x00' * padding)
        else:
            # dBase IV+ format: 8-byte header + data
            # Header: [type:4][length:4] (little-endian)
            f.write(struct.pack("<L", memo_type))
            f.write(struct.pack("<L", data_len))
            f.write(data)
            # Pad to block boundary
            bytes_written = 8 + data_len
            padding = (blocks_needed * DBF_MEMO_BLOCK_SIZE) - bytes_written
            if padding > 0:
                f.write(b'\x00' * padding)
        
        # Update next available block if necessary
        f.seek(0)
        next_block_bytes = f.read(4)
        if len(next_block_bytes) == 4:
            current_next = struct.unpack(">L", next_block_bytes)[0]
            new_next = block_num + blocks_needed
            if new_next > current_next:
                f.seek(0)
                f.write(struct.pack(">L", new_next))
    
    return block_num


def export_dbf_memos_to_text(filename: str) -> None:
    """
    Export memo fields to a text file (.MEM format).
    
    Format: RowIndex|FieldIndex|MemoType|BlockNum|Content
    - RowIndex: Zero-based row index (excluding deleted rows)
    - FieldIndex: 1-based field index
    - MemoType: 1 for text, 2 for binary
    - BlockNum: Memo block number
    - Content: Hex-encoded memo content
    
    Args:
        filename: Base filename (without extension)
    """
    dbf_filename = filename if filename.endswith('.DBF') else filename + '.DBF'
    dbt_filename = filename.replace('.DBF', '') + '.DBT'
    mem_filename = filename.replace('.DBF', '') + '.MEM'
    
    # Open the DBF file
    dbf = dbf_file_open(dbf_filename)
    
    # Open text file for writing
    with open(mem_filename, 'w', encoding='utf-8') as f:
        row_count = dbf_file_get_actual_row_count(dbf)
        export_row_index = 0
        
        for row_idx in range(row_count):
            dbf_file_seek_to_row(dbf, row_idx)
            row = dbf_file_read_row(dbf)
            
            # Skip deleted rows (delete flag is row[0])
            if row[0] == '*':
                continue
            
            # Check each field for memo type
            for field_idx in range(1, dbf.header.field_count + 1):
                field = dbf.header.fields[field_idx - 1]
                if field.field_type.upper() == 'M':
                    memo_block_str = row[field_idx].strip()
                    if memo_block_str and memo_block_str != '0':
                        memo_block = int(memo_block_str)
                        if memo_block > 0:
                            # Get memo info first
                            memo_type, memo_len = dbf_memo_get_info(dbt_filename, memo_block)
                            if memo_type > 0:
                                # Read memo data
                                _, memo_data = dbf_memo_read_buffer(dbt_filename, memo_block, memo_len)
                                
                                # Convert to hex string
                                memo_hex = memo_data.hex().upper()
                                
                                # Write: RowIndex|FieldIdx|MemoType|BlockNum|Content
                                f.write(f"{export_row_index}|{field_idx}|{memo_type}|{memo_block}|{memo_hex}\n")
            
            export_row_index += 1
    
    # Close the DBF file
    dbf_file_close(dbf)


def import_dbf_memos_from_text(filename: str) -> None:
    """
    Import memo fields from a text file (.MEM format).
    Assigns new block numbers.
    
    Args:
        filename: Base filename (without extension)
    """
    import_dbf_memos_from_text_ex(filename, preserve_blocks=False)


def import_dbf_memos_from_text_ex(filename: str, preserve_blocks: bool = False) -> None:
    """
    Import memo fields from a text file (.MEM format).
    
    Args:
        filename: Base filename (without extension)
        preserve_blocks: If True, preserve original block numbers from .MEM file.
                        If False, assign new block numbers.
    """
    dbf_filename = filename if filename.endswith('.DBF') else filename + '.DBF'
    dbt_filename = filename.replace('.DBF', '') + '.DBT'
    mem_filename = filename.replace('.DBF', '') + '.MEM'
    
    # Read the memo file
    with open(mem_filename, 'r', encoding='utf-8') as f:
        lines = f.readlines()
    
    # Open the DBF file
    dbf = dbf_file_open(dbf_filename)
    
    # Process each memo line
    for line in lines:
        line = line.strip()
        if not line:
            continue
        
        # Parse: RowIndex|FieldIdx|MemoType|BlockNum|Content
        parts = line.split('|')
        if len(parts) < 5:
            continue
        
        row_index = int(parts[0])
        field_idx = int(parts[1])
        memo_type = int(parts[2])
        old_block_num = int(parts[3])
        memo_hex = parts[4]
        
        # Convert hex to bytes
        memo_data = bytes.fromhex(memo_hex)
        
        # Write memo to file
        if preserve_blocks:
            # Preserve original block number
            if memo_type == 1:
                # Text memo
                new_block = dbf_memo_write_at_block(dbt_filename, memo_type, memo_data.decode('latin-1'), old_block_num)
            else:
                # Binary memo
                new_block = dbf_memo_write_buffer_at_block(dbt_filename, memo_type, memo_data, old_block_num)
        else:
            # Assign new block number
            if memo_type == 1:
                # Text memo
                new_block = dbf_memo_write(dbt_filename, memo_type, memo_data.decode('latin-1'))
            else:
                # Binary memo
                new_block = dbf_memo_write_buffer(dbt_filename, memo_type, memo_data)
        
        # Update the field in the DBF
        dbf_file_seek_to_row(dbf, row_index)
        row = dbf_file_read_row(dbf)
        dbf_file_set_field_str(row, dbf, field_idx, str(new_block))
        
        # Write the row back
        values = ['']  # Index 0 is ignored
        for i in range(1, dbf.header.field_count + 1):
            values.append(dbf_file_get_field_str(row, dbf, i))
        
        dbf_file_seek_to_row(dbf, row_index)
        dbf_file_write_row(dbf, values)
    
    # Close the DBF file
    dbf_file_close(dbf)


def compact_dbf(in_filename: str, out_filename: str) -> None:
    """
    Compact a DBF file by removing deleted rows and compacting memo file.
    
    This function:
    - Copies only non-deleted rows from input to output
    - Copies memo data and assigns new block numbers
    - Creates a clean, compacted database
    
    Args:
        in_filename: Input filename (without extension)
        out_filename: Output filename (without extension)
    """
    in_dbf_file = in_filename if in_filename.endswith('.DBF') else in_filename + '.DBF'
    in_dbt_file = in_filename.replace('.DBF', '') + '.DBT'
    out_dbf_file = out_filename if out_filename.endswith('.DBF') else out_filename + '.DBF'
    out_dbt_file = out_filename.replace('.DBF', '') + '.DBT'
    
    # Open input DBF
    in_dbf = dbf_file_open(in_dbf_file)
    
    # Create output DBF with same structure
    out_header = DBFHeader()
    out_header.version = in_dbf.header.version
    out_header.year = in_dbf.header.year
    out_header.month = in_dbf.header.month
    out_header.day = in_dbf.header.day
    out_header.record_count = 0  # Will be updated as we add rows
    out_header.header_size = in_dbf.header.header_size
    out_header.record_size = in_dbf.header.record_size
    out_header.table_flags = in_dbf.header.table_flags
    out_header.language_driver = in_dbf.header.language_driver
    out_header.field_count = in_dbf.header.field_count
    out_header.fields = in_dbf.header.fields.copy()
    
    # Create output DBF file
    has_memo = any(field.field_type.upper() == 'M' for field in out_header.fields)
    if has_memo:
        out_dbf = dbf_file_create(out_filename, out_header)
    else:
        out_dbf = dbf_file_create_dbase3(out_filename, out_header)
    
    # Process each row from input
    row_count = dbf_file_get_actual_row_count(in_dbf)
    for row_idx in range(row_count):
        dbf_file_seek_to_row(in_dbf, row_idx)
        row = dbf_file_read_row(in_dbf)
        
        # Skip deleted rows
        if row[0] == '*':
            continue
        
        # Build values array for output
        values = ['']  # Index 0 is ignored
        
        # Process each field
        for field_idx in range(1, in_dbf.header.field_count + 1):
            field = in_dbf.header.fields[field_idx - 1]
            
            if field.field_type.upper() == 'M':
                # Memo field - copy memo data and get new block number
                memo_block_str = row[field_idx].strip()
                if memo_block_str and memo_block_str != '0':
                    old_block = int(memo_block_str)
                    if old_block > 0:
                        # Get memo info
                        memo_type, memo_len = dbf_memo_get_info(in_dbt_file, old_block)
                        if memo_type > 0:
                            # Read memo data
                            _, memo_data = dbf_memo_read_buffer(in_dbt_file, old_block, memo_len)
                            
                            # Write to output memo file
                            if memo_type == 1:
                                # Text memo
                                new_block = dbf_memo_write(out_dbt_file, memo_type, memo_data.decode('latin-1'))
                            else:
                                # Binary memo
                                new_block = dbf_memo_write_buffer(out_dbt_file, memo_type, memo_data)
                            
                            values.append(str(new_block))
                        else:
                            values.append('0')
                    else:
                        values.append('0')
                else:
                    values.append('0')
            else:
                # Regular field - copy value
                values.append(row[field_idx].strip())
        
        # Append row to output
        dbf_file_append_row(out_dbf, values)
    
    # Close files
    dbf_file_close(in_dbf)
    dbf_file_close(out_dbf)


def dbf_file_clear_memo_fields(dbf: DBFFile) -> None:
    """
    Clear all memo fields in a DBF file (set to 0).
    
    Args:
        dbf: The DBF file object
    """
    if not dbf or not dbf.is_open:
        return
    
    row_count = dbf_file_get_actual_row_count(dbf)
    
    for row_idx in range(row_count):
        dbf_file_seek_to_row(dbf, row_idx)
        row = dbf_file_read_row(dbf)
        
        # Clear each memo field
        for field_idx in range(1, dbf.header.field_count + 1):
            field = dbf.header.fields[field_idx - 1]
            if field.field_type.upper() == 'M':
                dbf_file_set_field_str(row, dbf, field_idx, '0')
        
        # Write the row back
        values = ['']  # Index 0 is ignored
        for i in range(1, dbf.header.field_count + 1):
            values.append(dbf_file_get_field_str(row, dbf, i))
        
        dbf_file_seek_to_row(dbf, row_idx)
        dbf_file_write_row(dbf, values)


# Export functions
__all__ = [
    'DBFColumn', 'DBFHeader', 'DBFFile',
    'DBF_MAX_FIELDS', 'DBF_MAX_RECORD_SIZE', 'DBF_MAX_ROW_IDS',
    'DBF_LANG_US', 'DBF_LANG_WESTERN_EUROPE', 'DBF_LANG_JAPAN',
    'DBF_MEMO_BLOCK_SIZE',
    'dbf_file_create', 'dbf_file_create_dbase3', 'dbf_file_close', 'dbf_file_open',
    'dbf_file_get_date', 'dbf_file_set_date',
    'dbf_file_get_language_driver', 'dbf_file_set_language_driver',
    'dbf_file_append_row', 'dbf_file_read_row', 'dbf_file_write_row',
    'dbf_file_seek_to_row', 'dbf_file_seek_to_first_row', 'dbf_file_get_actual_row_count',
    'dbf_file_set_row_deleted', 'dbf_file_get_field_str', 'dbf_file_set_field_str',
    'dbf_file_clear_memo_fields',
    'export_dbf_to_text', 'import_dbf_from_text',
    'export_dbf_memos_to_text', 'import_dbf_memos_from_text', 'import_dbf_memos_from_text_ex',
    'compact_dbf',
    'build_field_spec', 'parse_field_spec',
    'dbf_memo_write', 'dbf_memo_write_buffer', 'dbf_memo_get_info',
    'dbf_memo_read_small', 'dbf_memo_read_binary',
    'dbf_memo_read_chunk', 'dbf_memo_read_buffer',
    'trim_string', 'pad_string', 'parse_int', 'parse_bool'
]
