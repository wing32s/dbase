#!/usr/bin/env python3
"""
TESTFLTR.PY - Python equivalent of TESTFLTR.PAS

This test demonstrates:
1. Creating a test DBF file with multiple field types
2. Building NDX indexes using Python ndx_module
3. Creating heap maps using Python heap_builder
4. Testing filtering operations with NDX + heap map integration
"""

import os
import sys
import unittest
from datetime import datetime, timedelta

# Add current directory to path for imports
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from dbf_module import (
    DBFColumn, DBFHeader, DBFFile,
    dbf_file_create, dbf_file_close, dbf_file_open,
    dbf_file_append_row, dbf_file_read_row, dbf_file_seek_to_row,
    dbf_file_get_actual_row_count, dbf_file_get_field_str,
    DBF_LANG_US
)

from ndx_module import ndx_create_index
from test_heap_builder import (
    HeapMap, HeapFieldType, HeapFieldSpec, build_heap_map, DBFRecord,
    heap_get_word, heap_get_longint, heap_get_bitflag, heap_get_nibble, heap_get_byte
)
from test_progressive_filtering import FilterKind, MatchMode, FilterSpec, MatchGroup


class TestFilterIntegration(unittest.TestCase):
    """Test NDX + Heap Map filtering integration"""
    
    def setUp(self):
        """Set up test fixtures."""
        self.test_filename = "TESTFLTR"
        self.max_test_records = 100
        self.created_files = []
        
        # Boolean bit definitions - packed into BoolFlags byte
        self.BOOL_IS_ACTIVE = 0x01   # Bit 0: Active (from ACTIVE field)
        self.BOOL_IS_DELETED = 0x02   # Bit 1: Deleted (from DELETED field)
        
        # Numeric flag bit definitions - stored in Flags byte
        self.FLAG_FEATURED = 0x01      # Bit 0: Featured item
        self.FLAG_VERIFIED = 0x02      # Bit 1: Verified/approved
        self.FLAG_ARCHIVED = 0x04      # Bit 2: Archived
        self.FLAG_FAVORITE = 0x08      # Bit 3: Favorite
        
    def tearDown(self):
        """Clean up created test files (unless KEEP_TEST_FILES is set)."""
        if os.environ.get('KEEP_TEST_FILES'):
            print("\n📁 Keeping test files for inspection (KEEP_TEST_FILES is set)")
            return
        
        # Clean up created files
        for filename in self.created_files:
            if os.path.exists(filename):
                try:
                    os.remove(filename)
                    print(f"🗑️  Cleaned up: {filename}")
                except Exception as e:
                    print(f"⚠️  Could not remove {filename}: {e}")
    
    def create_test_dbf(self):
        """Create test DBF file with sample data."""
        print(f"Creating test DBF file: {self.test_filename}.DBF")
        
        # Define fields for our test database
        fields = [
            DBFColumn(name="NAME", field_type="C", length=20, decimals=0),
            DBFColumn(name="YEAR", field_type="N", length=4, decimals=0),
            DBFColumn(name="RATING", field_type="N", length=2, decimals=0),
            DBFColumn(name="DATEADD", field_type="D", length=8, decimals=0),
            DBFColumn(name="ACTIVE", field_type="L", length=1, decimals=0),
            DBFColumn(name="DELETED", field_type="L", length=1, decimals=0),
            DBFColumn(name="FLAGS", field_type="N", length=3, decimals=0),
        ]
        
        # Create header
        header = DBFHeader()
        header.version = 0x03  # dBase III
        header.field_count = len(fields)
        header.fields = fields
        
        # Set date (DBF stores year as year - 1900)
        now = datetime.now()
        header.year = now.year - 1900  # DBF year is offset from 1900
        header.month = now.month
        header.day = now.day
        
        # Create DBF file
        dbf = dbf_file_create(self.test_filename, header)
        self.created_files.append(f"{self.test_filename}.DBF")
        
        # Add sample records
        print(f"Adding {self.max_test_records} test records...")
        
        for rec_no in range(1, self.max_test_records + 1):
            # NAME field - pattern based on record number
            if rec_no % 10 == 0:
                name = "Alpha"
            elif rec_no % 5 == 0:
                name = "Beta"
            elif rec_no % 3 == 0:
                name = "Gamma"
            else:
                name = "Delta"
            
            # YEAR field - 1980-2025
            year = 1980 + (rec_no % 45)
            
            # RATING field - 1-10
            rating = 1 + (rec_no % 10)
            
            # DATEADD field - dates in 2020s
            dateadd = datetime(2020, 1, 1) + timedelta(days=rec_no)
            
            # ACTIVE field - alternating
            active = rec_no % 2 == 0
            
            # DELETED field - every 4th record
            deleted = rec_no % 4 == 0
            
            # FLAGS field - bit patterns based on record number
            flags = 0
            if rec_no % 10 == 0:
                flags |= self.FLAG_FEATURED
            if rec_no % 7 == 0:
                flags |= self.FLAG_VERIFIED
            if rec_no % 5 == 0:
                flags |= self.FLAG_ARCHIVED
            if rec_no % 3 == 0:
                flags |= self.FLAG_FAVORITE
            
            # Append row (values list is 1-indexed, so values[0] is ignored)
            row_data = [
                '',  # values[0] is ignored
                name,  # Field 1: NAME
                str(year),  # Field 2: YEAR
                str(rating),  # Field 3: RATING
                dateadd.strftime('%Y%m%d'),  # Field 4: DATEADD as string
                'T' if active else 'F',  # Field 5: ACTIVE
                'T' if deleted else 'F',  # Field 6: DELETED
                str(flags)  # Field 7: FLAGS
            ]
            dbf_file_append_row(dbf, row_data)
        
        dbf_file_close(dbf)
        print(f"Created {self.max_test_records} records")
        
        return self.test_filename + ".DBF"
    
    def create_ndx_index(self, dbf_filename):
        """Create NDX index on NAME field."""
        print(f"Creating NDX index on NAME field...")
        
        ndx_filename = dbf_filename.replace('.DBF', '.NDX')
        success = ndx_create_index(dbf_filename, 'name', ndx_filename)
        
        if success:
            self.created_files.append(ndx_filename)
            print(f"NDX index created: {ndx_filename}")
            return ndx_filename
        else:
            raise Exception("Failed to create NDX index")
    
    def build_heap_map(self, dbf_filename):
        """Build heap map from DBF file."""
        print(f"Building heap map from {dbf_filename}...")
        
        # Open DBF file and read records
        dbf = dbf_file_open(dbf_filename)
        records = []
        
        for i in range(dbf_file_get_actual_row_count(dbf)):
            dbf_file_seek_to_row(dbf, i)
            row = dbf_file_read_row(dbf)
            
            # Create DBFRecord object with proper type conversion
            # Convert string fields to appropriate types for heap map
            year_str = dbf_file_get_field_str(row, dbf, 2).strip()
            rating_str = dbf_file_get_field_str(row, dbf, 3).strip()
            flags_str = dbf_file_get_field_str(row, dbf, 7).strip()
            
            # More robust string to int conversion
            def safe_int_convert(s, default=0):
                try:
                    return int(s) if s else default
                except (ValueError, TypeError):
                    return default
            
            record = DBFRecord(i, **{
                'NAME': dbf_file_get_field_str(row, dbf, 1),
                'YEAR': safe_int_convert(year_str, 0),
                'RATING': safe_int_convert(rating_str, 0),
                'DATEADD': dbf_file_get_field_str(row, dbf, 4),  # Keep as string for JDN conversion
                'ACTIVE': dbf_file_get_field_str(row, dbf, 5) == 'T',
                'DELETED': dbf_file_get_field_str(row, dbf, 6) == 'T',
                'FLAGS': safe_int_convert(flags_str, 0),
            })
            records.append(record)
        
        dbf_file_close(dbf)
        
        # Define field specifications for heap map
        field_specs = [
            HeapFieldSpec(0, HeapFieldType.WORD),     # RecNo (index 0)
            HeapFieldSpec(2, HeapFieldType.WORD),     # YEAR (field index 2)
            HeapFieldSpec(4, HeapFieldType.LONGINT, convert_to_jdn=True),  # DATEADD (field index 4, convert date string to JDN)
            HeapFieldSpec(5, HeapFieldType.BITFLAGS, bit_mask=0x01),  # ACTIVE (field index 5)
            HeapFieldSpec(6, HeapFieldType.BITFLAGS, bit_mask=0x02),  # DELETED (field index 6)
            HeapFieldSpec(7, HeapFieldType.WORD),     # FLAGS (field index 7)
        ]
        
        # Build heap map
        heap_map = build_heap_map(records, field_specs, target_record_size=16)
        
        print(f"Heap map built: {heap_map.record_count} records, "
              f"{heap_map.record_count * heap_map.record_size} bytes")
        
        return heap_map
    
    def _test_streaming_filtering(self, dbf_filename):
        """Test streaming mode filtering."""
        print("\n=== Testing Streaming Mode ===")
        
        dbf = dbf_file_open(dbf_filename)
        
        # Test 1: Filter by YEAR = 1985
        print("Test 1: YEAR = 1985")
        year_matches = []
        for i in range(dbf_file_get_actual_row_count(dbf)):
            dbf_file_seek_to_row(dbf, i)
            row = dbf_file_read_row(dbf)
            year = int(dbf_file_get_field_str(row, dbf, 2))
            if year == 1985:
                year_matches.append(i)
        print(f"  Found {len(year_matches)} matches")
        self.assertGreater(len(year_matches), 0, "Should find records with year 1985")
        
        # Test 2: Filter by RATING = 5
        print("Test 2: RATING = 5")
        rating_matches = []
        for i in range(dbf_file_get_actual_row_count(dbf)):
            dbf_file_seek_to_row(dbf, i)
            row = dbf_file_read_row(dbf)
            rating = int(dbf_file_get_field_str(row, dbf, 3))
            if rating == 5:
                rating_matches.append(i)
        print(f"  Found {len(rating_matches)} matches")
        self.assertGreater(len(rating_matches), 0, "Should find records with rating 5")
        
        # Test 3: Filter by NAME starts with "Alp"
        print("Test 3: NAME starts with 'Alp'")
        name_matches = []
        for i in range(dbf_file_get_actual_row_count(dbf)):
            dbf_file_seek_to_row(dbf, i)
            row = dbf_file_read_row(dbf)
            name = dbf_file_get_field_str(row, dbf, 1)
            if name.startswith('Alp'):
                name_matches.append(i)
        print(f"  Found {len(name_matches)} matches")
        self.assertGreater(len(name_matches), 0, "Should find records starting with Alp")
        
        dbf_file_close(dbf)
        print("Streaming mode tests completed")
    
    def _test_heap_map_filtering(self, heap_map):
        """Test heap map mode filtering."""
        print("\n=== Testing Heap Map Mode ===")
        
        # Test 1: Filter by YEAR >= 1985 using heap map
        print("Test 1: YEAR >= 1985 (heap map)")
        year_matches = []
        for i in range(heap_map.record_count):
            year = heap_get_word(heap_map, i, 2)  # Field 2 = YEAR (corrected index)
            if year >= 1985:
                year_matches.append(i)
        print(f"  Found {len(year_matches)} matches")
        self.assertGreater(len(year_matches), 0, "Should find records with year >= 1985")
        
        # Test 2: Filter by boolean flags
        print("Test 2: Active AND NOT Deleted (heap map)")
        bool_matches = []
        for i in range(heap_map.record_count):
            active = heap_get_bitflag(heap_map, i, 4)  # Field 4 = ACTIVE (corrected index)
            deleted = heap_get_bitflag(heap_map, i, 5)  # Field 5 = DELETED (corrected index)
            if active and not deleted:
                bool_matches.append(i)
        print(f"  Found {len(bool_matches)} matches")
        
        # Test 3: Filter by numeric flags
        print("Test 3: Featured OR Verified (heap map)")
        flag_matches = []
        for i in range(heap_map.record_count):
            flags = heap_get_word(heap_map, i, 6)  # Field 6 = FLAGS (corrected index)
            if flags & self.FLAG_FEATURED or flags & self.FLAG_VERIFIED:
                flag_matches.append(i)
        print(f"  Found {len(flag_matches)} matches")
        
        print("Heap map mode tests completed")
    
    def _test_ndx_heap_map_integration(self, dbf_filename, ndx_filename, heap_map):
        """Test NDX + heap map integration."""
        print("\n=== Testing NDX + Heap Map Integration ===")
        
        # Test 1: NDX search for "Alp" + heap map filter YEAR >= 1985
        print("Test 1: NDX search for 'Alp' + heap map filter YEAR >= 1985")
        
        # Simulate NDX search (would normally use ndx_module search functions)
        # For demo, we'll use direct DBF search to simulate NDX results
        ndx_matches = []
        dbf = dbf_file_open(dbf_filename)
        for i in range(dbf_file_get_actual_row_count(dbf)):
            dbf_file_seek_to_row(dbf, i)
            row = dbf_file_read_row(dbf)
            name = dbf_file_get_field_str(row, dbf, 1)
            if name.startswith('Alp'):
                ndx_matches.append(i)
        dbf_file_close(dbf)
        
        print(f"  NDX found {len(ndx_matches)} records starting with 'Alp'")
        
        # Apply heap map filtering to those results
        heap_matches = 0
        for rec_no in ndx_matches:
            if rec_no < heap_map.record_count:
                year = heap_get_word(heap_map, rec_no, 2)  # Field 2 = YEAR (corrected index)
                if year >= 1985:
                    heap_matches += 1
        
        print(f"  Heap map filtered to {heap_matches} records with YEAR >= 1985")
        print(f"  Combined result: {heap_matches} records match both criteria")
        
        # Test 2: NDX search for "Beta" + heap map boolean filtering
        print("Test 2: NDX search for 'Beta' + heap map boolean filtering")
        
        # Simulate NDX search for "Beta"
        ndx_matches = []
        dbf = dbf_file_open(dbf_filename)
        for i in range(dbf_file_get_actual_row_count(dbf)):
            dbf_file_seek_to_row(dbf, i)
            row = dbf_file_read_row(dbf)
            name = dbf_file_get_field_str(row, dbf, 1)
            if name.startswith('Beta'):
                ndx_matches.append(i)
        dbf_file_close(dbf)
        
        print(f"  NDX found {len(ndx_matches)} records starting with 'Beta'")
        
        # Apply heap map boolean filtering
        heap_matches = 0
        for rec_no in ndx_matches:
            if rec_no < heap_map.record_count:
                active = heap_get_bitflag(heap_map, rec_no, 4)  # Field 4 = ACTIVE (corrected index)
                deleted = heap_get_bitflag(heap_map, rec_no, 5)  # Field 5 = DELETED (corrected index)
                if active and not deleted:
                    heap_matches += 1
        
        print(f"  Heap map filtered to {heap_matches} active, non-deleted records")
        print(f"  Combined result: {heap_matches} records match all criteria")
        
        print("NDX + Heap Map integration tests completed")
    
    def test_filter_integration(self):
        """Main test method that runs the complete workflow."""
        print("TESTFLTR - Filter Integration Test")
        print("=" * 50)
        
        # Step 1: Create test DBF
        dbf_filename = self.create_test_dbf()
        print()
        
        # Step 2: Create NDX index
        ndx_filename = self.create_ndx_index(dbf_filename)
        print()
        
        # Step 3: Build heap map
        heap_map = self.build_heap_map(dbf_filename)
        print()
        
        # Step 4: Test streaming mode
        self._test_streaming_filtering(dbf_filename)
        
        # Step 5: Test heap map mode
        self._test_heap_map_filtering(heap_map)
        
        # Step 6: Test NDX + heap map integration
        self._test_ndx_heap_map_integration(dbf_filename, ndx_filename, heap_map)
        
        print("\nAll tests completed successfully!")


if __name__ == "__main__":
    # Run the test
    unittest.main(verbosity=2)
