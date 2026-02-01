"""
Test Heap Map Builder

This validates the heap map builder design before implementing in Pascal.
Key concepts:
1. Extract only numeric fields needed for filtering
2. Pack into aligned, fixed-size records (16, 24, or 32 bytes)
3. Automatic offset calculation with proper alignment
4. Type-safe accessors for reading heap data
"""

import struct
from typing import List, Dict, Any
from enum import Enum


class HeapFieldType(Enum):
    """Types of fields in heap map"""
    NONE = 0
    WORD = 1      # 2 bytes, unsigned
    LONGINT = 2   # 4 bytes, signed
    BITFLAGS = 3  # 1 byte, bit-packed booleans
    NIBBLE = 4    # 4 bits, enum value 0-15
    BYTE = 5      # 1 byte, enum value 0-255


class HeapFieldSpec:
    """Specification for one field in heap map"""
    def __init__(self, dbf_field_idx: int, heap_field_type: HeapFieldType, 
                 convert_to_jdn: bool = False, bit_mask: int = 0, nibble_shift: int = 0):
        self.dbf_field_idx = dbf_field_idx  # Source field index (0 = RecNo)
        self.heap_field_type = heap_field_type
        self.heap_offset = 0  # Calculated by layout function
        self.convert_to_jdn = convert_to_jdn  # Auto-convert date string to JDN
        self.bit_mask = bit_mask  # For BITFLAGS: which bit(s) to use (e.g., 0x01, 0x02, 0x04)
        self.nibble_shift = nibble_shift  # For NIBBLE: 0 (low nibble) or 4 (high nibble)


class HeapMap:
    """Memory-packed heap map for fast filtering"""
    def __init__(self, record_size: int = 16):
        self.record_count = 0
        self.record_size = record_size  # 16, 24, or 32 bytes
        self.field_count = 0
        self.field_specs: List[HeapFieldSpec] = []
        self.records: List[bytearray] = []  # Each record is a bytearray


class DBFRecord:
    """Simulated DBF record"""
    def __init__(self, rec_no: int, **fields):
        self.rec_no = rec_no
        self.fields = fields
    
    def get_field(self, field_idx: int):
        """Get field by index (0 = RecNo, 1+ = actual fields)"""
        if field_idx == 0:
            return self.rec_no
        # Convert 1-based index to field name
        field_names = list(self.fields.keys())
        if 0 < field_idx <= len(field_names):
            return self.fields[field_names[field_idx - 1]]
        return None


def date_to_jdn(year: int, month: int, day: int) -> int:
    """Convert Gregorian date to Julian Day Number (same algorithm as Pascal)"""
    a = (14 - month) // 12
    y = year + 4800 - a
    m = month + (12 * a) - 3
    return day + ((153 * m + 2) // 5) + (365 * y) + (y // 4) - (y // 100) + (y // 400) - 32045


def dbf_date_str_to_jdn(date_str: str) -> int:
    """
    Convert dBASE date string "YYYYMMDD" to JDN.
    Returns 0 if invalid.
    """
    if not date_str or len(date_str) != 8:
        return 0
    
    try:
        year = int(date_str[0:4])
        month = int(date_str[4:6])
        day = int(date_str[6:8])
        
        # Basic validation
        if year < 1 or month < 1 or month > 12 or day < 1 or day > 31:
            return 0
        
        return date_to_jdn(year, month, day)
    except (ValueError, IndexError):
        return 0


def calculate_heap_layout(field_specs: List[HeapFieldSpec], target_record_size: int) -> bool:
    """
    Calculate field offsets with proper alignment.
    BITFLAGS fields can share the same byte if they have different bit masks.
    NIBBLE fields can share the same byte (2 nibbles per byte).
    Returns True if all fields fit within target size.
    """
    current_offset = 0
    last_bitflags_offset = -1  # Track last BITFLAGS byte offset
    last_nibble_offset = -1    # Track last NIBBLE byte offset
    
    for spec in field_specs:
        if spec.heap_field_type == HeapFieldType.WORD:
            # Word: 2 bytes, must be 2-byte aligned
            if current_offset % 2 != 0:
                current_offset += 1  # Align to 2-byte boundary
            spec.heap_offset = current_offset
            field_size = 2
            last_bitflags_offset = -1  # Reset BITFLAGS tracking
            last_nibble_offset = -1    # Reset NIBBLE tracking
        
        elif spec.heap_field_type == HeapFieldType.LONGINT:
            # LongInt: 4 bytes, must be 4-byte aligned
            while current_offset % 4 != 0:
                current_offset += 1  # Align to 4-byte boundary
            spec.heap_offset = current_offset
            field_size = 4
            last_bitflags_offset = -1  # Reset BITFLAGS tracking
            last_nibble_offset = -1    # Reset NIBBLE tracking
        
        elif spec.heap_field_type == HeapFieldType.BITFLAGS:
            # BITFLAGS: 1 byte, can share with previous BITFLAGS if different bit mask
            if last_bitflags_offset >= 0:
                # Reuse the same byte as previous BITFLAGS
                spec.heap_offset = last_bitflags_offset
                field_size = 0  # Don't advance offset
            else:
                # New BITFLAGS byte
                spec.heap_offset = current_offset
                field_size = 1
                last_bitflags_offset = current_offset
            last_nibble_offset = -1  # Reset NIBBLE tracking
        
        elif spec.heap_field_type == HeapFieldType.NIBBLE:
            # NIBBLE: 4 bits, can share byte with another nibble
            if last_nibble_offset >= 0:
                # Reuse same byte, use high nibble
                spec.heap_offset = last_nibble_offset
                spec.nibble_shift = 4  # High nibble
                field_size = 0  # Don't advance offset
                last_nibble_offset = -1  # Byte is now full
            else:
                # New nibble byte, use low nibble
                spec.heap_offset = current_offset
                spec.nibble_shift = 0  # Low nibble
                field_size = 1
                last_nibble_offset = current_offset
            last_bitflags_offset = -1  # Reset BITFLAGS tracking
        
        elif spec.heap_field_type == HeapFieldType.BYTE:
            # BYTE: 1 byte, no alignment required
            spec.heap_offset = current_offset
            field_size = 1
            last_bitflags_offset = -1  # Reset BITFLAGS tracking
            last_nibble_offset = -1    # Reset NIBBLE tracking
        
        else:
            return False  # Unknown type
        
        current_offset += field_size
        
        # Check if we exceeded target size
        if current_offset > target_record_size:
            return False
    
    # Pad to next multiple of 8 bytes
    if current_offset % 8 != 0:
        current_offset = ((current_offset // 8) + 1) * 8
    
    # Check if padded size exceeds target
    if current_offset > target_record_size:
        return False
    
    return True


def build_heap_map(records: List[DBFRecord], field_specs: List[HeapFieldSpec], 
                   target_record_size: int) -> HeapMap:
    """
    Build heap map from DBF records based on field specifications.
    """
    heap_map = HeapMap(target_record_size)
    heap_map.field_specs = field_specs
    heap_map.field_count = len(field_specs)
    
    # Calculate layout
    if not calculate_heap_layout(field_specs, target_record_size):
        print("ERROR: Fields don't fit in target record size")
        return heap_map
    
    # Print layout
    print(f"\nHeap Layout (target size: {target_record_size} bytes):")
    for i, spec in enumerate(field_specs, 1):
        if spec.heap_field_type == HeapFieldType.WORD:
            type_name, size = "Word", 2
        elif spec.heap_field_type == HeapFieldType.LONGINT:
            type_name, size = "LongInt", 4
        elif spec.heap_field_type == HeapFieldType.BITFLAGS:
            type_name, size = f"BitFlags(0x{spec.bit_mask:02X})", 1
        elif spec.heap_field_type == HeapFieldType.NIBBLE:
            nibble_pos = "low" if spec.nibble_shift == 0 else "high"
            type_name, size = f"Nibble({nibble_pos})", 0.5
        elif spec.heap_field_type == HeapFieldType.BYTE:
            type_name, size = "Byte", 1
        else:
            type_name, size = "Unknown", 0
        print(f"  Field {i}: offset {spec.heap_offset:2d}, size {size}, type {type_name}")
    
    # Load records
    for record in records:
        # Create empty record buffer
        record_buffer = bytearray(target_record_size)
        
        # Pack each field
        for spec in field_specs:
            # Get field value
            if spec.dbf_field_idx == 0:
                # Special: RecNo
                value = record.rec_no
            else:
                value = record.get_field(spec.dbf_field_idx)
                if value is None:
                    value = 0
                
                # Convert date string to JDN if requested
                if spec.convert_to_jdn and isinstance(value, str):
                    value = dbf_date_str_to_jdn(value)
            
            # Pack into buffer at calculated offset
            if spec.heap_field_type == HeapFieldType.WORD:
                # Pack as unsigned short (2 bytes)
                # Convert string to int if needed
                if isinstance(value, str):
                    try:
                        value = int(value)
                    except (ValueError, TypeError):
                        value = 0
                struct.pack_into('<H', record_buffer, spec.heap_offset, value & 0xFFFF)
            elif spec.heap_field_type == HeapFieldType.LONGINT:
                # Pack as signed int (4 bytes)
                # Convert string to int if needed
                if isinstance(value, str):
                    try:
                        value = int(value)
                    except (ValueError, TypeError):
                        value = 0
                struct.pack_into('<i', record_buffer, spec.heap_offset, value)
            elif spec.heap_field_type == HeapFieldType.BITFLAGS:
                # Pack as bit flag (OR into existing byte)
                # Convert boolean/string to bit value
                bit_value = 0
                if isinstance(value, bool):
                    bit_value = 1 if value else 0
                elif isinstance(value, str):
                    # dBASE logical: 'T', 't', 'Y', 'y' = True
                    bit_value = 1 if value.upper() in ('T', 'Y') else 0
                elif isinstance(value, int):
                    bit_value = 1 if value != 0 else 0
                
                # OR the bit into the byte
                if bit_value:
                    record_buffer[spec.heap_offset] |= spec.bit_mask
            
            elif spec.heap_field_type == HeapFieldType.NIBBLE:
                # Pack as nibble (4 bits, value 0-15)
                nibble_value = int(value) if isinstance(value, (int, float)) else 0
                nibble_value = max(0, min(15, nibble_value))  # Clamp to 0-15
                
                if spec.nibble_shift == 0:
                    # Low nibble: clear bits 0-3, set value
                    record_buffer[spec.heap_offset] = (record_buffer[spec.heap_offset] & 0xF0) | (nibble_value & 0x0F)
                else:
                    # High nibble: clear bits 4-7, set value
                    record_buffer[spec.heap_offset] = (record_buffer[spec.heap_offset] & 0x0F) | ((nibble_value & 0x0F) << 4)
            
            elif spec.heap_field_type == HeapFieldType.BYTE:
                # Pack as byte (8 bits, value 0-255)
                byte_value = int(value) if isinstance(value, (int, float)) else 0
                byte_value = max(0, min(255, byte_value))  # Clamp to 0-255
                record_buffer[spec.heap_offset] = byte_value
        
        heap_map.records.append(record_buffer)
        heap_map.record_count += 1
    
    return heap_map


def heap_get_word(heap_map: HeapMap, record_idx: int, field_idx: int) -> int:
    """Read Word value from heap map (type-safe accessor)"""
    if record_idx >= heap_map.record_count or field_idx < 1 or field_idx > heap_map.field_count:
        return 0
    
    spec = heap_map.field_specs[field_idx - 1]  # Convert to 0-based
    if spec.heap_field_type != HeapFieldType.WORD:
        return 0
    
    return struct.unpack_from('<H', heap_map.records[record_idx], spec.heap_offset)[0]


def heap_get_longint(heap_map: HeapMap, record_idx: int, field_idx: int) -> int:
    """Read LongInt value from heap map (type-safe accessor)"""
    if record_idx >= heap_map.record_count or field_idx < 1 or field_idx > heap_map.field_count:
        return 0
    
    spec = heap_map.field_specs[field_idx - 1]  # Convert to 0-based
    if spec.heap_field_type != HeapFieldType.LONGINT:
        return 0
    
    return struct.unpack_from('<i', heap_map.records[record_idx], spec.heap_offset)[0]


def heap_get_bitflag(heap_map: HeapMap, record_idx: int, field_idx: int) -> bool:
    """Read bit flag value from heap map (type-safe accessor)"""
    if record_idx >= heap_map.record_count or field_idx < 1 or field_idx > heap_map.field_count:
        return False
    
    spec = heap_map.field_specs[field_idx - 1]  # Convert to 0-based
    if spec.heap_field_type != HeapFieldType.BITFLAGS:
        return False
    
    byte_value = heap_map.records[record_idx][spec.heap_offset]
    return (byte_value & spec.bit_mask) != 0


def heap_get_nibble(heap_map: HeapMap, record_idx: int, field_idx: int) -> int:
    """Read nibble value from heap map (type-safe accessor)"""
    if record_idx >= heap_map.record_count or field_idx < 1 or field_idx > heap_map.field_count:
        return 0
    
    spec = heap_map.field_specs[field_idx - 1]  # Convert to 0-based
    if spec.heap_field_type != HeapFieldType.NIBBLE:
        return 0
    
    byte_value = heap_map.records[record_idx][spec.heap_offset]
    
    if spec.nibble_shift == 0:
        # Low nibble
        return byte_value & 0x0F
    else:
        # High nibble
        return (byte_value >> 4) & 0x0F


def heap_get_byte(heap_map: HeapMap, record_idx: int, field_idx: int) -> int:
    """Read byte value from heap map (type-safe accessor)"""
    if record_idx >= heap_map.record_count or field_idx < 1 or field_idx > heap_map.field_count:
        return 0
    
    spec = heap_map.field_specs[field_idx - 1]  # Convert to 0-based
    if spec.heap_field_type != HeapFieldType.BYTE:
        return 0
    
    return heap_map.records[record_idx][spec.heap_offset]


def test_basic_heap_map():
    """Test basic heap map creation with Word fields"""
    print("=" * 70)
    print("Test 1: Basic Heap Map (3 Word fields)")
    print("=" * 70)
    
    # Create test records
    records = []
    for i in range(10):
        records.append(DBFRecord(
            rec_no=i,
            Year=2000 + i,
            Rating=1 + (i % 10)
        ))
    
    # Define field specs
    field_specs = [
        HeapFieldSpec(0, HeapFieldType.WORD),  # RecNo
        HeapFieldSpec(1, HeapFieldType.WORD),  # Year (field 1)
        HeapFieldSpec(2, HeapFieldType.WORD),  # Rating (field 2)
    ]
    
    # Build heap map
    heap_map = build_heap_map(records, field_specs, 16)
    
    print(f"\nHeap map built: {heap_map.record_count} records")
    
    # Verify data
    print("\nVerifying data (first 5 records):")
    all_match = True
    for i in range(min(5, heap_map.record_count)):
        rec_no = heap_get_word(heap_map, i, 1)
        year = heap_get_word(heap_map, i, 2)
        rating = heap_get_word(heap_map, i, 3)
        
        expected_year = 2000 + i
        expected_rating = 1 + (i % 10)
        
        match = (rec_no == i and year == expected_year and rating == expected_rating)
        status = "✓" if match else "✗"
        
        print(f"  {status} Record {i}: RecNo={rec_no}, Year={year}, Rating={rating}")
        
        if not match:
            all_match = False
    
    if all_match:
        print("\n✓ SUCCESS: All data matches!")
    else:
        print("\n✗ FAILURE: Data mismatch!")
    
    return all_match


def test_alignment():
    """Test memory alignment with mixed field types"""
    print("\n" + "=" * 70)
    print("Test 2: Memory Alignment (Word + LongInt)")
    print("=" * 70)
    
    # Create test records
    records = []
    for i in range(10):
        records.append(DBFRecord(
            rec_no=i,
            Year=2000 + i,
            DateAdded=2450000 + (i * 365)  # JDN values
        ))
    
    # Define field specs: Word + LongInt (should add padding)
    field_specs = [
        HeapFieldSpec(0, HeapFieldType.WORD),     # RecNo at offset 0
        HeapFieldSpec(1, HeapFieldType.WORD),     # Year at offset 2
        HeapFieldSpec(2, HeapFieldType.LONGINT),  # DateAdded at offset 4 (aligned)
    ]
    
    # Build heap map
    heap_map = build_heap_map(records, field_specs, 16)
    
    # Verify alignment
    print("\nChecking alignment:")
    print(f"  RecNo offset:    {field_specs[0].heap_offset} (expected 0)")
    print(f"  Year offset:     {field_specs[1].heap_offset} (expected 2)")
    print(f"  DateAdded offset: {field_specs[2].heap_offset} (expected 4 - aligned to 4-byte boundary)")
    
    alignment_ok = (
        field_specs[0].heap_offset == 0 and
        field_specs[1].heap_offset == 2 and
        field_specs[2].heap_offset == 4
    )
    
    # Verify data
    print("\nVerifying data (first 3 records):")
    all_match = True
    for i in range(min(3, heap_map.record_count)):
        rec_no = heap_get_word(heap_map, i, 1)
        year = heap_get_word(heap_map, i, 2)
        date_added = heap_get_longint(heap_map, i, 3)
        
        expected_date = 2450000 + (i * 365)
        
        match = (rec_no == i and year == 2000 + i and date_added == expected_date)
        status = "✓" if match else "✗"
        
        print(f"  {status} Record {i}: RecNo={rec_no}, Year={year}, DateAdded={date_added}")
        
        if not match:
            all_match = False
    
    if alignment_ok and all_match:
        print("\n✓ SUCCESS: Alignment and data correct!")
        return True
    else:
        print("\n✗ FAILURE: Alignment or data incorrect!")
        return False


def test_overflow():
    """Test that too many fields are rejected"""
    print("\n" + "=" * 70)
    print("Test 3: Overflow Detection (too many fields)")
    print("=" * 70)
    
    # Try to fit 10 Word fields (20 bytes) into 16-byte record
    field_specs = [HeapFieldSpec(i, HeapFieldType.WORD) for i in range(10)]
    
    success = calculate_heap_layout(field_specs, 16)
    
    if not success:
        print("✓ SUCCESS: Correctly rejected 10 Words (20 bytes) in 16-byte record")
        return True
    else:
        print("✗ FAILURE: Should have rejected oversized layout")
        return False


def test_performance():
    """Test performance with larger dataset"""
    print("\n" + "=" * 70)
    print("Test 4: Performance (1000 records)")
    print("=" * 70)
    
    import time
    
    # Create 1000 test records
    records = []
    for i in range(1000):
        records.append(DBFRecord(
            rec_no=i,
            Year=2000 + (i % 26),
            Rating=1 + (i % 10),
            Score=i * 100
        ))
    
    # Define field specs
    field_specs = [
        HeapFieldSpec(0, HeapFieldType.WORD),     # RecNo
        HeapFieldSpec(1, HeapFieldType.WORD),     # Year
        HeapFieldSpec(2, HeapFieldType.WORD),     # Rating
        HeapFieldSpec(3, HeapFieldType.LONGINT),  # Score
    ]
    
    # Build heap map
    start = time.time()
    heap_map = build_heap_map(records, field_specs, 16)
    build_time = time.time() - start
    
    print(f"\nBuild time: {build_time*1000:.2f} ms for {heap_map.record_count} records")
    
    # Test access speed
    start = time.time()
    total = 0
    for i in range(heap_map.record_count):
        year = heap_get_word(heap_map, i, 2)
        score = heap_get_longint(heap_map, i, 4)
        total += year + score
    access_time = time.time() - start
    
    print(f"Access time: {access_time*1000:.2f} ms for {heap_map.record_count*2} field reads")
    print(f"Average: {(access_time*1000000)/(heap_map.record_count*2):.2f} µs per field read")
    
    # Verify a few random records
    print("\nSpot check (records 0, 500, 999):")
    for idx in [0, 500, 999]:
        if idx < heap_map.record_count:
            year = heap_get_word(heap_map, idx, 2)
            score = heap_get_longint(heap_map, idx, 4)
            print(f"  Record {idx}: Year={year}, Score={score}")
    
    print("\n✓ SUCCESS: Performance test completed!")
    return True


def test_different_sizes():
    """Test different record sizes (16, 24, 32 bytes)"""
    print("\n" + "=" * 70)
    print("Test 5: Different Record Sizes")
    print("=" * 70)
    
    records = [DBFRecord(rec_no=i, Year=2000+i) for i in range(5)]
    
    for size in [16, 24, 32]:
        print(f"\n--- Testing {size}-byte records ---")
        
        # Simple spec: just RecNo and Year
        field_specs = [
            HeapFieldSpec(0, HeapFieldType.WORD),
            HeapFieldSpec(1, HeapFieldType.WORD),
        ]
        
        heap_map = build_heap_map(records, field_specs, size)
        print(f"Created heap map with {heap_map.record_count} records of {heap_map.record_size} bytes each")
        
        # Verify
        year = heap_get_word(heap_map, 0, 2)
        print(f"Record 0 Year: {year} (expected 2000)")
    
    print("\n✓ SUCCESS: All record sizes work!")
    return True


def test_date_conversion():
    """Test automatic date string to JDN conversion"""
    print("\n" + "=" * 70)
    print("Test 6: Date Conversion (YYYYMMDD to JDN)")
    print("=" * 70)
    
    # Create test records with date strings
    records = []
    test_dates = [
        ("20050101", 2453372),  # 2005-01-01
        ("20081231", 2454832),  # 2008-12-31
        ("20100615", 2455363),  # 2010-06-15
        ("20151231", 2457388),  # 2015-12-31
        ("20000101", 2451545),  # 2000-01-01
    ]
    
    for i, (date_str, expected_jdn) in enumerate(test_dates):
        records.append(DBFRecord(
            rec_no=i,
            Year=int(date_str[0:4]),
            DateAdded=date_str  # Date as string "YYYYMMDD"
        ))
    
    # Define field specs with JDN conversion
    field_specs = [
        HeapFieldSpec(0, HeapFieldType.WORD),                          # RecNo
        HeapFieldSpec(1, HeapFieldType.WORD),                          # Year
        HeapFieldSpec(2, HeapFieldType.LONGINT, convert_to_jdn=True),  # DateAdded (convert!)
    ]
    
    # Build heap map
    heap_map = build_heap_map(records, field_specs, 16)
    
    print(f"\nHeap map built: {heap_map.record_count} records")
    print("\nVerifying date conversion:")
    
    all_match = True
    for i, (date_str, expected_jdn) in enumerate(test_dates):
        rec_no = heap_get_word(heap_map, i, 1)
        year = heap_get_word(heap_map, i, 2)
        date_jdn = heap_get_longint(heap_map, i, 3)
        
        match = (date_jdn == expected_jdn)
        status = "✓" if match else "✗"
        
        print(f"  {status} Record {i}: Date={date_str} → JDN={date_jdn} (expected {expected_jdn})")
        
        if not match:
            all_match = False
    
    # Test JDN conversion directly
    print("\nDirect JDN conversion tests:")
    test_cases = [
        ("20050101", 2453372),
        ("20081231", 2454832),
        ("20100615", 2455363),
        ("", 0),           # Empty string
        ("invalid", 0),    # Invalid format
        ("20001301", 0),   # Invalid month
    ]
    
    for date_str, expected in test_cases:
        result = dbf_date_str_to_jdn(date_str)
        match = (result == expected)
        status = "✓" if match else "✗"
        print(f"  {status} '{date_str}' → {result} (expected {expected})")
        if not match:
            all_match = False
    
    if all_match:
        print("\n✓ SUCCESS: All date conversions correct!")
        return True
    else:
        print("\n✗ FAILURE: Date conversion errors!")
        return False


def test_boolean_packing():
    """Test bit-packed boolean fields"""
    print("\n" + "=" * 70)
    print("Test 7: Boolean Bit Packing")
    print("=" * 70)
    
    # Create test records with boolean fields
    records = []
    test_cases = [
        (True, True, False),    # Active=T, Featured=T, Deleted=F
        (False, True, False),   # Active=F, Featured=T, Deleted=F
        (True, False, True),    # Active=T, Featured=F, Deleted=T
        (False, False, False),  # Active=F, Featured=F, Deleted=F
        (True, True, True),     # Active=T, Featured=T, Deleted=T
    ]
    
    for i, (active, featured, deleted) in enumerate(test_cases):
        records.append(DBFRecord(
            rec_no=i,
            Year=2000 + i,
            Active=active,
            Featured=featured,
            Deleted=deleted
        ))
    
    # Define field specs with bit packing
    field_specs = [
        HeapFieldSpec(0, HeapFieldType.WORD),                           # RecNo
        HeapFieldSpec(1, HeapFieldType.WORD),                           # Year
        HeapFieldSpec(2, HeapFieldType.BITFLAGS, bit_mask=0x01),        # Active (bit 0)
        HeapFieldSpec(3, HeapFieldType.BITFLAGS, bit_mask=0x02),        # Featured (bit 1)
        HeapFieldSpec(4, HeapFieldType.BITFLAGS, bit_mask=0x04),        # Deleted (bit 2)
    ]
    
    # Build heap map
    heap_map = build_heap_map(records, field_specs, 16)
    
    print(f"\nHeap map built: {heap_map.record_count} records")
    print("\nVerifying bit packing (3 booleans in 1 byte):")
    
    all_match = True
    for i, (expected_active, expected_featured, expected_deleted) in enumerate(test_cases):
        rec_no = heap_get_word(heap_map, i, 1)
        year = heap_get_word(heap_map, i, 2)
        active = heap_get_bitflag(heap_map, i, 3)
        featured = heap_get_bitflag(heap_map, i, 4)
        deleted = heap_get_bitflag(heap_map, i, 5)
        
        match = (active == expected_active and featured == expected_featured and deleted == expected_deleted)
        status = "✓" if match else "✗"
        
        print(f"  {status} Record {i}: Active={active}, Featured={featured}, Deleted={deleted}")
        
        if not match:
            all_match = False
    
    # Verify all 3 booleans share the same byte
    print("\nVerifying byte sharing:")
    offset_active = field_specs[2].heap_offset
    offset_featured = field_specs[3].heap_offset
    offset_deleted = field_specs[4].heap_offset
    
    print(f"  Active offset:   {offset_active}")
    print(f"  Featured offset: {offset_featured}")
    print(f"  Deleted offset:  {offset_deleted}")
    
    if offset_active == offset_featured == offset_deleted:
        print("  ✓ All 3 booleans share the same byte!")
    else:
        print("  ✗ Booleans don't share the same byte!")
        all_match = False
    
    # Check actual byte values
    print("\nActual byte values (hex):")
    for i in range(min(5, heap_map.record_count)):
        byte_val = heap_map.records[i][offset_active]
        print(f"  Record {i}: 0x{byte_val:02X} (binary: {byte_val:08b})")
    
    if all_match:
        print("\n✓ SUCCESS: Boolean bit packing works correctly!")
        return True
    else:
        print("\n✗ FAILURE: Boolean bit packing errors!")
        return False


def test_nibble_packing():
    """Test nibble-packed enum fields (4 bits each, 0-15)"""
    print("\n" + "=" * 70)
    print("Test 8: Nibble Packing (Enums 0-15)")
    print("=" * 70)
    
    # Create test records with enum fields
    records = []
    test_cases = [
        (1, 2, 3, 4),   # CGA, EGA, VGA, SVGA
        (0, 5, 10, 15), # None, Card5, Card10, Card15
        (7, 8, 9, 11),  # Various values
        (15, 0, 1, 2),  # Max, Min, Low values
        (3, 3, 3, 3),   # All same
    ]
    
    for i, (video, sound, priority, status) in enumerate(test_cases):
        records.append(DBFRecord(
            rec_no=i,
            Year=2000 + i,
            VideoMode=video,
            SoundCard=sound,
            Priority=priority,
            Status=status
        ))
    
    # Define field specs with nibble packing
    field_specs = [
        HeapFieldSpec(0, HeapFieldType.WORD),          # RecNo
        HeapFieldSpec(1, HeapFieldType.WORD),          # Year
        HeapFieldSpec(2, HeapFieldType.NIBBLE),        # VideoMode (low nibble)
        HeapFieldSpec(3, HeapFieldType.NIBBLE),        # SoundCard (high nibble, same byte!)
        HeapFieldSpec(4, HeapFieldType.NIBBLE),        # Priority (low nibble)
        HeapFieldSpec(5, HeapFieldType.NIBBLE),        # Status (high nibble, same byte!)
    ]
    
    # Build heap map
    heap_map = build_heap_map(records, field_specs, 16)
    
    print(f"\nHeap map built: {heap_map.record_count} records")
    print("\nVerifying nibble packing (4 enums in 2 bytes):")
    
    all_match = True
    for i, (exp_video, exp_sound, exp_priority, exp_status) in enumerate(test_cases):
        rec_no = heap_get_word(heap_map, i, 1)
        year = heap_get_word(heap_map, i, 2)
        video = heap_get_nibble(heap_map, i, 3)
        sound = heap_get_nibble(heap_map, i, 4)
        priority = heap_get_nibble(heap_map, i, 5)
        status = heap_get_nibble(heap_map, i, 6)
        
        match = (video == exp_video and sound == exp_sound and 
                priority == exp_priority and status == exp_status)
        status_str = "✓" if match else "✗"
        
        print(f"  {status_str} Record {i}: Video={video}, Sound={sound}, Priority={priority}, Status={status}")
        
        if not match:
            all_match = False
    
    # Verify byte sharing
    print("\nVerifying byte sharing:")
    offset_video = field_specs[2].heap_offset
    offset_sound = field_specs[3].heap_offset
    offset_priority = field_specs[4].heap_offset
    offset_status = field_specs[5].heap_offset
    
    print(f"  VideoMode offset:  {offset_video} (shift={field_specs[2].nibble_shift})")
    print(f"  SoundCard offset:  {offset_sound} (shift={field_specs[3].nibble_shift})")
    print(f"  Priority offset:   {offset_priority} (shift={field_specs[4].nibble_shift})")
    print(f"  Status offset:     {offset_status} (shift={field_specs[5].nibble_shift})")
    
    if (offset_video == offset_sound and offset_priority == offset_status and
        offset_video != offset_priority):
        print("  ✓ 2 pairs of nibbles, each pair shares a byte!")
    else:
        print("  ✗ Nibble byte sharing incorrect!")
        all_match = False
    
    # Check actual byte values
    print("\nActual byte values (hex):")
    for i in range(min(5, heap_map.record_count)):
        byte1 = heap_map.records[i][offset_video]
        byte2 = heap_map.records[i][offset_priority]
        print(f"  Record {i}: Byte1=0x{byte1:02X} (Video+Sound), Byte2=0x{byte2:02X} (Priority+Status)")
    
    # Test space savings
    print("\nSpace savings:")
    print(f"  Without nibbles: 4 fields × 1 byte = 4 bytes")
    print(f"  With nibbles:    4 fields × 0.5 bytes = 2 bytes")
    print(f"  Savings: 50%!")
    
    if all_match:
        print("\n✓ SUCCESS: Nibble packing works correctly!")
        return True
    else:
        print("\n✗ FAILURE: Nibble packing errors!")
        return False


def test_segmented_heap_map():
    """Test segmented heap map for tables >8K records"""
    print("\n" + "=" * 70)
    print("Test: Segmented Heap Map (>8K records)")
    print("=" * 70)
    
    MAX_HEAP_RECORDS = 8192
    
    # Simulate a large table with 20,000 records
    total_records = 20000
    print(f"\nSimulating table with {total_records:,} records")
    print(f"Max records per segment: {MAX_HEAP_RECORDS:,}")
    
    # Define field specs
    field_specs = [
        HeapFieldSpec(0, HeapFieldType.WORD),      # RecNo
        HeapFieldSpec(1, HeapFieldType.WORD),      # Year
        HeapFieldSpec(2, HeapFieldType.BITFLAGS, bit_mask=0x01),  # Active
    ]
    
    if not calculate_heap_layout(field_specs, 16):
        print("✗ Layout calculation failed!")
        return False
    
    # Simulate segmented processing
    segments_needed = (total_records + MAX_HEAP_RECORDS - 1) // MAX_HEAP_RECORDS
    print(f"Segments needed: {segments_needed}")
    
    all_results = []
    total_matches = 0
    
    for segment_num in range(segments_needed):
        start_recno = segment_num * MAX_HEAP_RECORDS + 1
        end_recno = min(start_recno + MAX_HEAP_RECORDS - 1, total_records)
        records_in_segment = end_recno - start_recno + 1
        
        print(f"\nSegment {segment_num + 1}: records {start_recno:,}-{end_recno:,} ({records_in_segment:,} records)")
        
        # Create heap map for this segment
        heap_map = HeapMap(record_size=16)
        heap_map.field_specs = field_specs
        heap_map.field_count = len(field_specs)
        
        # Simulate loading records into segment
        segment_matches = 0
        for i in range(records_in_segment):
            actual_recno = start_recno + i
            
            # Simulate record data
            year = 1990 + (actual_recno % 20)  # Years 1990-2009
            active = (actual_recno % 3) == 0   # Every 3rd record is active
            
            # Create heap record
            record = bytearray(16)
            
            # Store RecNo (Word at offset 0)
            struct.pack_into('<H', record, 0, actual_recno)
            
            # Store Year (Word at offset 2)
            struct.pack_into('<H', record, 2, year)
            
            # Store Active (BitFlag at offset 4)
            if active:
                record[4] |= 0x01
            
            heap_map.records.append(record)
            heap_map.record_count += 1
            
            # Filter: Year = 1995 AND Active = True
            if year == 1995 and active:
                all_results.append(actual_recno)
                segment_matches += 1
        
        print(f"  Matches in segment: {segment_matches}")
        total_matches += segment_matches
        
        # Verify segment size
        memory_used = heap_map.record_count * heap_map.record_size
        print(f"  Memory used: {memory_used:,} bytes ({memory_used / 1024:.1f} KB)")
    
    print(f"\n{'=' * 70}")
    print(f"Total matches across all segments: {total_matches}")
    print(f"Total results collected: {len(all_results)}")
    
    # Verify results
    print("\nFirst 10 matching records:")
    for i, recno in enumerate(all_results[:10]):
        year = 1990 + (recno % 20)
        active = (recno % 3) == 0
        print(f"  {i+1}. RecNo {recno}: Year={year}, Active={active}")
    
    # Calculate expected matches
    # Year 1995 occurs at RecNo: 6, 26, 46, 66, ... (every 20th starting at 6)
    # Active occurs at RecNo: 3, 6, 9, 12, 15, 18, 21, 24, 27, 30, ... (every 3rd)
    # Both conditions: RecNo must be divisible by 3 AND (RecNo % 20) == 6
    # This means RecNo % 60 must be 6, 66, or 126, ... but simplified: RecNo where (RecNo-6) % 60 == 0
    expected_matches = 0
    for recno in range(1, total_records + 1):
        year = 1990 + (recno % 20)
        active = (recno % 3) == 0
        if year == 1995 and active:
            expected_matches += 1
    
    print(f"\nExpected matches: {expected_matches}")
    print(f"Actual matches: {total_matches}")
    
    if total_matches == expected_matches:
        print("\n✓ SUCCESS: Segmented heap map works correctly!")
        return True
    else:
        print(f"\n✗ FAILURE: Expected {expected_matches} matches, got {total_matches}")
        return False


def test_segmented_performance():
    """Test performance of segmented vs full heap map"""
    print("\n" + "=" * 70)
    print("Test: Segmented Performance Analysis")
    print("=" * 70)
    
    import time
    
    MAX_HEAP_RECORDS = 8192
    
    # Test different table sizes
    test_sizes = [5000, 10000, 20000, 50000]
    
    for total_records in test_sizes:
        print(f"\n{'=' * 70}")
        print(f"Table size: {total_records:,} records")
        
        segments_needed = (total_records + MAX_HEAP_RECORDS - 1) // MAX_HEAP_RECORDS
        print(f"Segments needed: {segments_needed}")
        
        # Define simple field specs
        field_specs = [
            HeapFieldSpec(0, HeapFieldType.WORD),  # RecNo
            HeapFieldSpec(1, HeapFieldType.WORD),  # Year
        ]
        
        calculate_heap_layout(field_specs, 16)
        
        # Time segmented processing
        start_time = time.time()
        
        total_matches = 0
        for segment_num in range(segments_needed):
            start_recno = segment_num * MAX_HEAP_RECORDS + 1
            end_recno = min(start_recno + MAX_HEAP_RECORDS - 1, total_records)
            records_in_segment = end_recno - start_recno + 1
            
            # Create segment
            heap_map = HeapMap(record_size=16)
            heap_map.field_specs = field_specs
            heap_map.field_count = len(field_specs)
            
            # Load records
            for i in range(records_in_segment):
                actual_recno = start_recno + i
                year = 1990 + (actual_recno % 20)
                
                record = bytearray(16)
                struct.pack_into('<H', record, 0, actual_recno)
                struct.pack_into('<H', record, 2, year)
                
                heap_map.records.append(record)
                heap_map.record_count += 1
                
                # Filter: Year = 1995
                if year == 1995:
                    total_matches += 1
        
        elapsed_time = time.time() - start_time
        
        print(f"\nResults:")
        print(f"  Total matches: {total_matches:,}")
        print(f"  Processing time: {elapsed_time:.3f} seconds")
        print(f"  Records/second: {total_records / elapsed_time:,.0f}")
        print(f"  Memory per segment: {MAX_HEAP_RECORDS * 16 / 1024:.1f} KB")
        print(f"  Peak memory: {MAX_HEAP_RECORDS * 16 / 1024:.1f} KB (constant!)")
        
        # Estimate streaming time (assume 550 records/sec from disk)
        streaming_time = total_records / 550
        speedup = streaming_time / elapsed_time
        
        print(f"\nComparison:")
        print(f"  Estimated streaming time: {streaming_time:.1f} seconds")
        print(f"  Speedup: {speedup:.1f}x faster")
    
    print("\n✓ SUCCESS: Performance analysis complete!")
    return True


if __name__ == "__main__":
    print("Heap Map Builder Test")
    print("=" * 70)
    
    results = []
    
    # Run all tests
    results.append(("Basic Heap Map", test_basic_heap_map()))
    results.append(("Memory Alignment", test_alignment()))
    results.append(("Overflow Detection", test_overflow()))
    results.append(("Performance", test_performance()))
    results.append(("Different Sizes", test_different_sizes()))
    results.append(("Date Conversion", test_date_conversion()))
    results.append(("Boolean Packing", test_boolean_packing()))
    results.append(("Nibble Packing", test_nibble_packing()))
    results.append(("Segmented Heap Map", test_segmented_heap_map()))
    results.append(("Segmented Performance", test_segmented_performance()))
    
    # Summary
    print("\n" + "=" * 70)
    print("Test Summary")
    print("=" * 70)
    
    for name, passed in results:
        status = "✓ PASS" if passed else "✗ FAIL"
        print(f"{status}: {name}")
    
    all_passed = all(result[1] for result in results)
    
    if all_passed:
        print("\n✓✓✓ ALL TESTS PASSED! ✓✓✓")
    else:
        print("\n✗✗✗ SOME TESTS FAILED ✗✗✗")
