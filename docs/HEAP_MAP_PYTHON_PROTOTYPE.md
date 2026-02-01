# Heap Map Builder - Python Prototype Documentation

## Overview

The Python prototype (`tests/test_heap_builder.py`) validates the heap map builder design before implementing in Pascal. It demonstrates memory-efficient packing of database fields into fixed-size records for fast in-memory filtering.

## Core Concepts

### Memory-Packed Records

Instead of storing full DBF records in memory, the heap map extracts only the fields needed for filtering and packs them into compact, fixed-size records (8, 16, 24, or 32 bytes).

**Benefits:**
- 50-100x faster than disk I/O
- Fits more records in limited DOS memory (440KB constraint)
- Enables bitmap-based filtering strategies
- Supports multiple data types with optimal packing

## Data Structures

### HeapFieldType Enum

Defines the types of fields that can be stored in the heap map:

```python
class HeapFieldType(Enum):
    NONE = 0
    WORD = 1      # 2 bytes, unsigned (0-65535)
    LONGINT = 2   # 4 bytes, signed (±2 billion)
    BITFLAGS = 3  # 1 bit, boolean (8 per byte)
    NIBBLE = 4    # 4 bits, enum 0-15 (2 per byte)
    BYTE = 5      # 1 byte, enum 0-255
```

### HeapFieldSpec Class

Specifies how to extract and pack a single field:

```python
class HeapFieldSpec:
    def __init__(self, dbf_field_idx, heap_field_type, 
                 convert_to_jdn=False, bit_mask=0, nibble_shift=0):
        self.dbf_field_idx = dbf_field_idx    # Source field (0 = RecNo)
        self.heap_field_type = heap_field_type
        self.heap_offset = 0                   # Auto-calculated
        self.convert_to_jdn = convert_to_jdn   # Date → JDN conversion
        self.bit_mask = bit_mask               # For BITFLAGS: 0x01, 0x02, etc.
        self.nibble_shift = nibble_shift       # For NIBBLE: 0 or 4
```

### HeapMap Class

The complete heap map structure:

```python
class HeapMap:
    def __init__(self, record_size=16):
        self.record_count = 0
        self.record_size = record_size         # 8, 16, 24, or 32 bytes
        self.field_count = 0
        self.field_specs = []                  # List of HeapFieldSpec
        self.records = []                      # List of bytearray
```

## Field Types in Detail

### 1. WORD (2 bytes)

**Use Case:** Integers 0-65535, RecNo, Year, counts

**Alignment:** 2-byte boundary

**Example:**
```python
HeapFieldSpec(0, HeapFieldType.WORD)  # RecNo
HeapFieldSpec(2, HeapFieldType.WORD)  # Year field
```

**Memory Layout:**
```
Offset 0-1: RecNo (Word)
Offset 2-3: Year (Word)
```

### 2. LONGINT (4 bytes)

**Use Case:** Large integers, Julian Day Numbers (dates)

**Alignment:** 4-byte boundary

**Example:**
```python
HeapFieldSpec(4, HeapFieldType.LONGINT, convert_to_jdn=True)  # Date field
```

**Memory Layout:**
```
Offset 0-3: Padding (for alignment)
Offset 4-7: DateAdded (LongInt/JDN)
```

### 3. BITFLAGS (1 bit)

**Use Case:** Boolean fields (True/False)

**Sharing:** Up to 8 booleans per byte

**Example:**
```python
HeapFieldSpec(5, HeapFieldType.BITFLAGS, bit_mask=0x01)  # Active (bit 0)
HeapFieldSpec(6, HeapFieldType.BITFLAGS, bit_mask=0x02)  # Featured (bit 1)
HeapFieldSpec(7, HeapFieldType.BITFLAGS, bit_mask=0x04)  # Deleted (bit 2)
```

**Memory Layout:**
```
Offset 8: BoolFlags byte
  Bit 0 (0x01): Active
  Bit 1 (0x02): Featured
  Bit 2 (0x04): Deleted
  Bits 3-7: Available for 5 more booleans
```

**Packing Logic:**
```python
# Convert value to bit (1 or 0)
if value in (True, 'T', 'Y'):
    record_buffer[offset] |= bit_mask  # OR the bit into the byte
```

### 4. NIBBLE (4 bits)

**Use Case:** Small enums with 0-15 values (video modes, priorities, ratings)

**Sharing:** 2 nibbles per byte (low and high)

**Example:**
```python
HeapFieldSpec(8, HeapFieldType.NIBBLE)   # VideoMode (low nibble)
HeapFieldSpec(9, HeapFieldType.NIBBLE)   # SoundCard (high nibble, same byte!)
```

**Memory Layout:**
```
Offset 9: Nibble byte
  Bits 0-3 (low nibble):  VideoMode (0-15)
  Bits 4-7 (high nibble): SoundCard (0-15)
```

**Packing Logic:**
```python
if nibble_shift == 0:
    # Low nibble: clear bits 0-3, set value
    record_buffer[offset] = (record_buffer[offset] & 0xF0) | (value & 0x0F)
else:
    # High nibble: clear bits 4-7, set value
    record_buffer[offset] = (record_buffer[offset] & 0x0F) | ((value & 0x0F) << 4)
```

### 5. BYTE (1 byte)

**Use Case:** Medium enums with 0-255 values (country codes, status codes, percentages)

**Alignment:** None required

**Example:**
```python
HeapFieldSpec(10, HeapFieldType.BYTE)  # CountryCode (0-255)
```

**Memory Layout:**
```
Offset 10: CountryCode (Byte, 0-255)
```

## Layout Calculation Algorithm

The `calculate_heap_layout()` function determines field offsets with proper alignment:

### Algorithm Steps

1. **Initialize**: Start at offset 0
2. **Track sharing**: Maintain `last_bitflags_offset` and `last_nibble_offset`
3. **For each field**:
   - Apply alignment rules based on type
   - Check for byte sharing (BITFLAGS, NIBBLE)
   - Calculate offset
   - Advance current offset
4. **Pad to 8-byte boundary**: Round up to next multiple of 8
5. **Validate**: Ensure total size ≤ target size

### Alignment Rules

```python
WORD:
    if current_offset % 2 != 0:
        current_offset += 1  # Align to 2-byte boundary
    field_size = 2

LONGINT:
    while current_offset % 4 != 0:
        current_offset += 1  # Align to 4-byte boundary
    field_size = 4

BITFLAGS:
    if last_bitflags_offset >= 0:
        offset = last_bitflags_offset  # Reuse byte
        field_size = 0
    else:
        offset = current_offset  # New byte
        field_size = 1

NIBBLE:
    if last_nibble_offset >= 0:
        offset = last_nibble_offset  # Reuse byte (high nibble)
        nibble_shift = 4
        field_size = 0
    else:
        offset = current_offset  # New byte (low nibble)
        nibble_shift = 0
        field_size = 1

BYTE:
    offset = current_offset  # No alignment
    field_size = 1
```

### 8-Byte Padding

After all fields are placed:

```python
# Pad to next multiple of 8 bytes
if current_offset % 8 != 0:
    current_offset = ((current_offset // 8) + 1) * 8

# Verify it fits
if current_offset > target_record_size:
    return False  # Layout failed
```

**Examples:**
- 6 bytes used → pad to 8 bytes
- 12 bytes used → pad to 16 bytes
- 18 bytes used → pad to 24 bytes

## Date Conversion (JDN)

### Julian Day Number Algorithm

Converts Gregorian calendar dates to a single integer for fast comparison:

```python
def date_to_jdn(year, month, day):
    """Convert Gregorian date to Julian Day Number"""
    a = (14 - month) // 12
    y = year + 4800 - a
    m = month + (12 * a) - 3
    return (day + ((153 * m + 2) // 5) + (365 * y) + 
            (y // 4) - (y // 100) + (y // 400) - 32045)
```

### dBASE Date String Conversion

```python
def dbf_date_str_to_jdn(date_str):
    """Convert dBASE date string 'YYYYMMDD' to JDN"""
    if len(date_str) != 8:
        return 0
    
    year = int(date_str[0:4])
    month = int(date_str[4:6])
    day = int(date_str[6:8])
    
    # Validate
    if year < 1 or month < 1 or month > 12 or day < 1 or day > 31:
        return 0
    
    return date_to_jdn(year, month, day)
```

**Examples:**
- `"20050101"` → `2453372`
- `"20101231"` → `2455562`
- `"invalid"` → `0`

## Building the Heap Map

### Process Flow

```python
def build_heap_map(records, field_specs, target_record_size):
    # 1. Calculate layout
    if not calculate_heap_layout(field_specs, target_record_size):
        return empty_heap_map  # Fields don't fit
    
    # 2. For each record
    for record in records:
        record_buffer = bytearray(target_record_size)  # Zero-filled
        
        # 3. Pack each field
        for spec in field_specs:
            value = get_field_value(record, spec)
            
            # Convert dates to JDN if requested
            if spec.convert_to_jdn:
                value = dbf_date_str_to_jdn(value)
            
            # Pack based on type
            pack_field(record_buffer, spec, value)
        
        heap_map.records.append(record_buffer)
    
    return heap_map
```

### Packing by Type

**WORD:**
```python
struct.pack_into('<H', buffer, offset, value & 0xFFFF)
```

**LONGINT:**
```python
struct.pack_into('<i', buffer, offset, value)
```

**BITFLAGS:**
```python
if value:  # True
    buffer[offset] |= bit_mask
```

**NIBBLE:**
```python
if nibble_shift == 0:
    buffer[offset] = (buffer[offset] & 0xF0) | (value & 0x0F)
else:
    buffer[offset] = (buffer[offset] & 0x0F) | ((value & 0x0F) << 4)
```

**BYTE:**
```python
buffer[offset] = value & 0xFF
```

## Accessing Heap Data

### Type-Safe Accessors

Each field type has a dedicated accessor function:

```python
def heap_get_word(heap_map, record_idx, field_idx):
    """Read Word value (2 bytes, unsigned)"""
    spec = heap_map.field_specs[field_idx - 1]
    if spec.heap_field_type != HeapFieldType.WORD:
        return 0
    return struct.unpack_from('<H', heap_map.records[record_idx], spec.heap_offset)[0]

def heap_get_longint(heap_map, record_idx, field_idx):
    """Read LongInt value (4 bytes, signed)"""
    spec = heap_map.field_specs[field_idx - 1]
    if spec.heap_field_type != HeapFieldType.LONGINT:
        return 0
    return struct.unpack_from('<i', heap_map.records[record_idx], spec.heap_offset)[0]

def heap_get_bitflag(heap_map, record_idx, field_idx):
    """Read bit flag value (boolean)"""
    spec = heap_map.field_specs[field_idx - 1]
    if spec.heap_field_type != HeapFieldType.BITFLAGS:
        return False
    byte_value = heap_map.records[record_idx][spec.heap_offset]
    return (byte_value & spec.bit_mask) != 0

def heap_get_nibble(heap_map, record_idx, field_idx):
    """Read nibble value (0-15)"""
    spec = heap_map.field_specs[field_idx - 1]
    if spec.heap_field_type != HeapFieldType.NIBBLE:
        return 0
    byte_value = heap_map.records[record_idx][spec.heap_offset]
    if spec.nibble_shift == 0:
        return byte_value & 0x0F
    else:
        return (byte_value >> 4) & 0x0F

def heap_get_byte(heap_map, record_idx, field_idx):
    """Read byte value (0-255)"""
    spec = heap_map.field_specs[field_idx - 1]
    if spec.heap_field_type != HeapFieldType.BYTE:
        return 0
    return heap_map.records[record_idx][spec.heap_offset]
```

## Complete Example

### Scenario: Game Database

```python
# Create test records
records = [
    DBFRecord(rec_no=0, Year=2005, DateAdded="20050115", 
              Active=True, Featured=False, VideoMode=3, SoundCard=2, Genre=5),
    DBFRecord(rec_no=1, Year=2008, DateAdded="20080620", 
              Active=True, Featured=True, VideoMode=4, SoundCard=3, Genre=7),
    # ... more records
]

# Define field specifications
field_specs = [
    HeapFieldSpec(0, HeapFieldType.WORD),                          # RecNo
    HeapFieldSpec(1, HeapFieldType.WORD),                          # Year
    HeapFieldSpec(2, HeapFieldType.LONGINT, convert_to_jdn=True),  # DateAdded → JDN
    HeapFieldSpec(3, HeapFieldType.BITFLAGS, bit_mask=0x01),       # Active (bit 0)
    HeapFieldSpec(4, HeapFieldType.BITFLAGS, bit_mask=0x02),       # Featured (bit 1)
    HeapFieldSpec(5, HeapFieldType.NIBBLE),                        # VideoMode (low)
    HeapFieldSpec(6, HeapFieldType.NIBBLE),                        # SoundCard (high)
    HeapFieldSpec(7, HeapFieldType.BYTE),                          # Genre (0-255)
]

# Build heap map (16-byte records)
heap_map = build_heap_map(records, field_specs, 16)

# Memory layout:
# Offset 0-1:   RecNo (Word)
# Offset 2-3:   Year (Word)
# Offset 4-7:   DateAdded (LongInt/JDN)
# Offset 8:     BoolFlags (Active=0x01, Featured=0x02)
# Offset 9:     Nibbles (VideoMode low, SoundCard high)
# Offset 10:    Genre (Byte)
# Offset 11-15: Padding
# Total: 16 bytes

# Access data
rec_no = heap_get_word(heap_map, 0, 1)           # 0
year = heap_get_word(heap_map, 0, 2)             # 2005
date_jdn = heap_get_longint(heap_map, 0, 3)     # 2453385
active = heap_get_bitflag(heap_map, 0, 4)       # True
featured = heap_get_bitflag(heap_map, 0, 5)     # False
video = heap_get_nibble(heap_map, 0, 6)         # 3
sound = heap_get_nibble(heap_map, 0, 7)         # 2
genre = heap_get_byte(heap_map, 0, 8)           # 5
```

## Test Suite

The prototype includes 8 comprehensive tests:

### Test 1: Basic Heap Map
- Validates Word field packing
- Tests data integrity

### Test 2: Memory Alignment
- Verifies 2-byte alignment for Word
- Verifies 4-byte alignment for LongInt
- Tests padding insertion

### Test 3: Overflow Detection
- Ensures layouts that exceed target size are rejected
- Tests boundary conditions

### Test 4: Performance
- Measures build time (1000 records in ~2ms)
- Measures access time (~0.29 µs per field read)
- Validates speed advantage

### Test 5: Different Record Sizes
- Tests 16, 24, and 32-byte records
- Validates flexibility

### Test 6: Date Conversion
- Tests YYYYMMDD → JDN conversion
- Validates date arithmetic
- Tests error handling (invalid dates)

### Test 7: Boolean Packing
- Tests bit flag packing (3 booleans in 1 byte)
- Validates byte sharing
- Tests bit masking

### Test 8: Nibble Packing
- Tests enum packing (4 enums in 2 bytes)
- Validates nibble sharing (low/high)
- Tests 50% space savings

## Performance Characteristics

### Memory Usage

| Records | Record Size | Total Memory |
|---------|-------------|--------------|
| 1,000 | 16 bytes | 16 KB |
| 4,096 | 16 bytes | 64 KB |
| 8,192 | 16 bytes | 128 KB |
| 8,192 | 32 bytes | 256 KB |

### Speed

- **Build time**: ~2 ms per 1000 records
- **Access time**: ~0.29 µs per field read
- **Comparison**: 50-100x faster than disk I/O

### Space Efficiency

| Field Type | Bytes | Efficiency |
|------------|-------|------------|
| BitFlags | 0.125 | 87.5% savings vs byte |
| Nibble | 0.5 | 50% savings vs byte |
| Byte | 1 | 50% savings vs word |
| Word | 2 | Standard |
| LongInt | 4 | Standard |

## Running the Tests

```bash
python tests/test_heap_builder.py
```

**Expected output:**
```
✓ PASS: Basic Heap Map
✓ PASS: Memory Alignment
✓ PASS: Overflow Detection
✓ PASS: Performance
✓ PASS: Different Sizes
✓ PASS: Date Conversion
✓ PASS: Boolean Packing
✓ PASS: Nibble Packing

✓✓✓ ALL TESTS PASSED! ✓✓✓
```

## Design Validation

The Python prototype validates:

1. ✅ **Alignment logic** works correctly
2. ✅ **Byte sharing** (BitFlags, Nibbles) functions properly
3. ✅ **Date conversion** produces correct JDN values
4. ✅ **Type-safe accessors** prevent access errors
5. ✅ **8-byte padding** maintains natural boundaries
6. ✅ **Performance** meets requirements (sub-microsecond access)
7. ✅ **Space efficiency** achieves 50-87% savings on packed types

## Next Steps

With the Python prototype validated, the Pascal implementation (DBHEAP.PAS) follows the same design:

1. Identical data structures
2. Same alignment rules
3. Same packing algorithms
4. Same accessor patterns
5. Same 8-byte padding strategy

The Python tests serve as a **specification** for the Pascal implementation.
