"""
Tests for NDX index file reading.

These tests use sample NDX files created by the Pascal implementation
to validate that our Python implementation reads them correctly.
"""

import unittest
import os
from ndx_module import (
    ndx_read_header, ndx_dump_first_entries,
    ndx_find_exact, ndx_find_prefix, 
    ndx_find_number_exact, ndx_find_number_range,
    ndx_find_date_exact, ndx_find_date_range,
    NDXHeader
)


class TestNDXReading(unittest.TestCase):
    """Test NDX file reading functionality."""
    
    def setUp(self):
        """Set up test fixtures."""
        self.samples_dir = "samples"
        # Track created NDX files for cleanup
        self.created_files = []
    
    def tearDown(self):
        """Clean up created test files (unless KEEP_TEST_FILES is set)."""
        # Check if we should keep test files for debugging
        if os.environ.get('KEEP_TEST_FILES'):
            print("\n📁 Keeping test files for inspection (KEEP_TEST_FILES is set)")
            return
        
        # Only delete files we created (not sample files)
        for filename in self.created_files:
            if os.path.exists(filename):
                try:
                    os.remove(filename)
                    print(f"🗑️  Cleaned up: {filename}")
                except Exception as e:
                    print(f"⚠️  Could not remove {filename}: {e}")
        
    def test_devname3_header(self):
        """Test reading DEVNAME3.NDX header."""
        filename = os.path.join(self.samples_dir, "DEVNAME3.NDX")
        
        header = ndx_read_header(filename)
        
        self.assertIsNotNone(header, "Should read header successfully")
        self.assertGreater(header.root_block, 0, "Root block should be positive")
        self.assertGreater(header.eof_block, 0, "EOF block should be positive")
        self.assertGreater(header.key_len, 0, "Key length should be positive")
        self.assertGreater(header.keys_max, 0, "Keys max should be positive")
        self.assertGreater(header.group_len, 0, "Group length should be positive")
        
        # Print header info for manual verification
        print(f"\nDEVNAME3.NDX Header:")
        print(f"  Expression: {header.expr}")
        print(f"  Key length: {header.key_len}")
        print(f"  Keys max: {header.keys_max}")
        print(f"  Group length: {header.group_len}")
        print(f"  Root block: {header.root_block}")
        print(f"  EOF block: {header.eof_block}")
    
    def test_devname3_first_entries(self):
        """Test dumping first 10 entries from DEVNAME3.NDX."""
        filename = os.path.join(self.samples_dir, "DEVNAME3.NDX")
        
        entries = ndx_dump_first_entries(filename, 10)
        
        self.assertGreater(len(entries), 0, "Should have entries")
        self.assertLessEqual(len(entries), 10, "Should have at most 10 entries")
        
        # Expected output from Pascal (samples/idxout.txt)
        expected = [
            (990, ""),
            (131, "'PG' Productions"),
            (2060, "-MWD- Software"),
            (2278, "1 Step Software, Inc."),
            (2355, "11th Dimension Entertainment"),
            (4446, "11th Dimension Entertainment"),
            (3279, "21st Century Entertainment Ltd"),
            (5641, "221B Software Development"),
            (5945, "221B Software Development"),
            (5096, "3000AD, Inc.")
        ]
        
        # Verify against Pascal output
        self.assertEqual(len(entries), len(expected), "Should have 10 entries")
        for i, ((recno, key), (exp_recno, exp_key)) in enumerate(zip(entries, expected), 1):
            self.assertEqual(recno, exp_recno, f"Entry {i} record number mismatch")
            self.assertEqual(key, exp_key, f"Entry {i} key mismatch")
        
        # Print entries for manual verification
        print(f"\nDEVNAME3.NDX First 10 entries (validated against Pascal):")
        for i, (recno, key) in enumerate(entries, 1):
            print(f"  {i} {recno} {key}")
        
        print("✅ All entries match Pascal output!")
    
    def test_text3_header(self):
        """Test reading TEXT3.NDX header (smaller file)."""
        filename = os.path.join(self.samples_dir, "TEXT3.NDX")
        
        header = ndx_read_header(filename)
        
        self.assertIsNotNone(header, "Should read header successfully")
        
        print(f"\nTEXT3.NDX Header:")
        print(f"  Expression: {header.expr}")
        print(f"  Key length: {header.key_len}")
    
    def test_year3_header(self):
        """Test reading YEAR3.NDX header (numeric index)."""
        filename = os.path.join(self.samples_dir, "YEAR3.NDX")
        
        header = ndx_read_header(filename)
        
        self.assertIsNotNone(header, "Should read header successfully")
        
        print(f"\nYEAR3.NDX Header:")
        print(f"  Expression: {header.expr}")
        print(f"  Key length: {header.key_len}")
    
    def test_dateadd3_header(self):
        """Test reading DATEADD3.NDX header (date index)."""
        filename = os.path.join(self.samples_dir, "DATEADD3.NDX")
        
        header = ndx_read_header(filename)
        
        self.assertIsNotNone(header, "Should read header successfully")
        
        print(f"\nDATEADD3.NDX Header:")
        print(f"  Expression: {header.expr}")
        print(f"  Key length: {header.key_len}")
    
    def test_all_ndx_files(self):
        """Test reading headers from all NDX files."""
        ndx_files = [
            "DEVNAME3.NDX",
            "DEVNAMEU.NDX",
            "PUBNAME3.NDX",
            "TEXT3.NDX",
            "TITLE3.NDX",
            "YEAR3.NDX",
            "DATEADD3.NDX"
        ]
        
        print("\nAll NDX Files:")
        for ndx_file in ndx_files:
            filename = os.path.join(self.samples_dir, ndx_file)
            if os.path.exists(filename):
                header = ndx_read_header(filename)
                self.assertIsNotNone(header, f"Should read {ndx_file} header")
                print(f"  {ndx_file}: expr='{header.expr}', keylen={header.key_len}")
    
    def test_exact_match_quicksilver(self):
        """Test exact match search for 'Quicksilver Software, Inc.'"""
        filename = os.path.join(self.samples_dir, "DEVNAME3.NDX")
        
        results = ndx_find_exact(filename, "Quicksilver Software, Inc.")
        
        # Expected from Pascal output (samples/idxout.txt line 14):
        # Exact recnos: [143, 586, 814, 2940, 7290] count= 5
        expected = [143, 586, 814, 2940, 7290]
        
        self.assertEqual(len(results), len(expected), f"Should find {len(expected)} matches")
        self.assertEqual(results, expected, "Record numbers should match Pascal output")
        
        print(f"\nExact match search: Quicksilver Software, Inc.")
        print(f"  Exact recnos: {results[:10]} count= {len(results)}")
        print("  ✅ Matches Pascal output!")
    
    def test_prefix_match_cosmi(self):
        """Test prefix match search for 'Cosmi'"""
        filename = os.path.join(self.samples_dir, "DEVNAME3.NDX")
        
        results = ndx_find_prefix(filename, "Cosmi")
        
        # Expected from Pascal output (samples/idxout.txt line 16):
        # Prefix recnos: [117, 517, 1692, 2102, 2513, 2782, 5284, 5848, 6462, 7105] count= 12
        # (array only displays first 10, but total count is 12)
        expected_first_10 = [117, 517, 1692, 2102, 2513, 2782, 5284, 5848, 6462, 7105]
        expected_count = 12
        
        self.assertEqual(len(results), expected_count, f"Should find {expected_count} matches")
        self.assertEqual(results[:10], expected_first_10, "First 10 record numbers should match Pascal output")
        
        print(f"\nPrefix match search: Cosmi")
        print(f"  Prefix recnos: {results[:10]} count= {len(results)}")
        print("  ✅ Matches Pascal output!")
    
    def test_prefix_match_king(self):
        """Test prefix match search for 'King' in TITLE3.NDX"""
        filename = os.path.join(self.samples_dir, "TITLE3.NDX")
        
        results = ndx_find_prefix(filename, "King")
        
        # Expected from Pascal output (samples/idxout.txt line 18):
        # Prefix recnos: [6283, 5175, 2743, 2100, 6943, 5308, 6097, 5376, 1387, 3181] count= 33
        expected_first_10 = [6283, 5175, 2743, 2100, 6943, 5308, 6097, 5376, 1387, 3181]
        expected_count = 33
        
        self.assertEqual(len(results), expected_count, f"Should find {expected_count} matches")
        self.assertEqual(results[:10], expected_first_10, "First 10 record numbers should match Pascal output")
        
        print(f"\nPrefix match search: King (TITLE3.NDX)")
        print(f"  Prefix recnos: {results[:10]} count= {len(results)}")
        print("  ✅ Matches Pascal output!")
    
    def test_prefix_match_sie_upper(self):
        """Test prefix match search for 'SIE' in DEVNAMEU.NDX (upper case index)"""
        filename = os.path.join(self.samples_dir, "DEVNAMEU.NDX")
        
        results = ndx_find_prefix(filename, "SIE")
        
        # Expected from Pascal output (samples/idxout.txt line 20):
        # Prefix recnos: [831, 2248, 2919, 3178, 4198, 125, 173, 187, 214, 220] count= 87
        # This tests when first entries are inside a leaf that falls outside the initial search area
        expected_first_10 = [831, 2248, 2919, 3178, 4198, 125, 173, 187, 214, 220]
        expected_count = 87
        
        self.assertEqual(len(results), expected_count, f"Should find {expected_count} matches")
        self.assertEqual(results[:10], expected_first_10, "First 10 record numbers should match Pascal output")
        
        print(f"\nPrefix match search: SIE (DEVNAMEU.NDX - upper case)")
        print(f"  Prefix recnos: {results[:10]} count= {len(results)}")
        print("  ✅ Matches Pascal output!")
    
    def test_number_exact_1981(self):
        """Test exact number search for 1981 in YEAR3.NDX"""
        filename = os.path.join(self.samples_dir, "YEAR3.NDX")
        
        results = ndx_find_number_exact(filename, 1981)
        
        # Expected from Pascal output (samples/idxout.txt line 22):
        # Exact recnos: [645, 914, 1727, 1876, 1878, 2028, 2256, 2296, 2545, 2760] count= 25
        expected_first_10 = [645, 914, 1727, 1876, 1878, 2028, 2256, 2296, 2545, 2760]
        expected_count = 25
        
        self.assertEqual(len(results), expected_count, f"Should find {expected_count} matches")
        self.assertEqual(results[:10], expected_first_10, "First 10 record numbers should match Pascal output")
        
        print(f"\nExact number search: 1981 (YEAR3.NDX)")
        print(f"  Exact recnos: {results[:10]} count= {len(results)}")
        print("  ✅ Matches Pascal output!")
    
    def test_number_range_1982_1984(self):
        """Test numeric range search for 1982-1984 in YEAR3.NDX"""
        filename = os.path.join(self.samples_dir, "YEAR3.NDX")
        
        # First verify individual year counts
        count_1982 = len(ndx_find_number_exact(filename, 1982))
        count_1983 = len(ndx_find_number_exact(filename, 1983))
        count_1984 = len(ndx_find_number_exact(filename, 1984))
        
        self.assertEqual(count_1982, 124, "1982 should have 124 entries")
        self.assertEqual(count_1983, 165, "1983 should have 165 entries")
        self.assertEqual(count_1984, 160, "1984 should have 160 entries")
        
        # Now test range
        results = ndx_find_number_range(filename, 1982, 1984)
        
        # Expected from Pascal output (samples/idxout.txt line 36):
        # Range recnos: [36, 119, 124, 219, 231, 284, 332, 393, 456, 584] count= 200
        # Line 38: Count= 449 (total)
        expected_first_10 = [36, 119, 124, 219, 231, 284, 332, 393, 456, 584]
        expected_count = 449  # 124 + 165 + 160
        
        self.assertEqual(len(results), expected_count, f"Should find {expected_count} matches (124+165+160)")
        self.assertEqual(results[:10], expected_first_10, "First 10 record numbers should match Pascal output")
        
        print(f"\nNumeric range search: 1982-1984 (YEAR3.NDX)")
        print(f"  Individual counts: 1982={count_1982}, 1983={count_1983}, 1984={count_1984}")
        print(f"  Range recnos: {results[:10]} count= {len(results)}")
        print(f"  ✅ Matches Pascal output! (124+165+160={expected_count})")
    
    def test_date_exact_2022_08_25(self):
        """Test exact date search for 2022-08-25 in DATEADD3.NDX"""
        filename = os.path.join(self.samples_dir, "DATEADD3.NDX")
        
        results = ndx_find_date_exact(filename, "2022-08-25")
        
        # Expected from Pascal output (samples/idxout.txt line 40):
        # Exact recnos: [32, 95, 129, 134, 140, 145, 171, 191, 250, 265] count= 20
        # Line 42: Count= 292
        expected_first_10 = [32, 95, 129, 134, 140, 145, 171, 191, 250, 265]
        expected_count = 292
        
        self.assertEqual(len(results), expected_count, f"Should find {expected_count} matches")
        self.assertEqual(results[:10], expected_first_10, "First 10 record numbers should match Pascal output")
        
        print(f"\nExact date search: 2022-08-25 (DATEADD3.NDX)")
        print(f"  Exact recnos: {results[:10]} count= {len(results)}")
        print("  ✅ Matches Pascal output!")
    
    def test_date_range_2022_08(self):
        """Test date range search for 2022-08-01 to 2022-08-30 in DATEADD3.NDX"""
        filename = os.path.join(self.samples_dir, "DATEADD3.NDX")
        
        results = ndx_find_date_range(filename, "2022-08-01", "2022-08-30")
        
        # Expected from Pascal output (samples/idxout.txt line 44):
        # Range recnos: [6431, 990, 2735, 32, 95, 129, 134, 140, 145, 171, 191, 250, 265, 267, 328, 344, 351, 395, 399, 407]
        # Line 46: Count= 295
        expected_first_20 = [6431, 990, 2735, 32, 95, 129, 134, 140, 145, 171, 191, 250, 265, 267, 328, 344, 351, 395, 399, 407]
        expected_count = 295
        
        self.assertEqual(len(results), expected_count, f"Should find {expected_count} matches")
        self.assertEqual(results[:20], expected_first_20, "First 20 record numbers should match Pascal output")
        
        print(f"\nDate range search: 2022-08-01 to 2022-08-30 (DATEADD3.NDX)")
        print(f"  Range recnos: {results[:20]}")
        print(f"  Count= {len(results)}")
        print("  ✅ Matches Pascal output!")
    
    def test_create_index_devname(self):
        """Test creating an NDX index for DEVNAME field"""
        from ndx_module import ndx_create_index
        
        dbf_filename = os.path.join(self.samples_dir, "GAMES3.DBF")
        ndx_filename = os.path.join(self.samples_dir, "DEVNAMEP.NDX")
        
        # Create the index
        success = ndx_create_index(dbf_filename, "devname", ndx_filename)
        self.assertTrue(success, "Index creation should succeed")
        
        # Track for cleanup
        self.created_files.append(ndx_filename)
        
        # Test search on created index
        results = ndx_find_exact(ndx_filename, "Quicksilver Software, Inc.")
        
        # Expected from Pascal output (same as DEVNAME3.NDX)
        expected = [143, 586, 814, 2940, 7290]
        
        self.assertEqual(results, expected, "Search results should match expected")
        
        print(f"\nCreated index DEVNAMEP.NDX")
        print(f"  Search for 'Quicksilver Software, Inc.': {results}")
        print("  ✅ Index creation and search successful!")
    
    def test_create_index_year_exact(self):
        """Test creating YEARP.NDX and exact number search"""
        from ndx_module import ndx_create_index
        
        dbf_filename = os.path.join(self.samples_dir, "GAMES3.DBF")
        ndx_filename = os.path.join(self.samples_dir, "YEARP.NDX")
        
        # Create the index
        success = ndx_create_index(dbf_filename, "year", ndx_filename)
        self.assertTrue(success, "Index creation should succeed")
        
        # Track for cleanup
        self.created_files.append(ndx_filename)
        
        # Test exact search - compare with YEAR3.NDX
        results_new = ndx_find_number_exact(ndx_filename, 1981)
        results_orig = ndx_find_number_exact(os.path.join(self.samples_dir, "YEAR3.NDX"), 1981)
        
        self.assertEqual(results_new, results_orig, "YEARP.NDX should match YEAR3.NDX for exact search")
        self.assertEqual(len(results_new), 25, "Should find 25 matches for 1981")
        
        print(f"\nCreated index YEARP.NDX")
        print(f"  Exact search 1981: {results_new[:10]} count={len(results_new)}")
        print("  ✅ Matches YEAR3.NDX!")
    
    def test_create_index_year_range(self):
        """Test creating YEARP.NDX and range number search"""
        from ndx_module import ndx_create_index
        
        dbf_filename = os.path.join(self.samples_dir, "GAMES3.DBF")
        ndx_filename = os.path.join(self.samples_dir, "YEARP.NDX")
        
        # Create the index (or use existing from previous test)
        ndx_create_index(dbf_filename, "year", ndx_filename)
        
        # Track for cleanup (avoid duplicates)
        if ndx_filename not in self.created_files:
            self.created_files.append(ndx_filename)
        
        # Test range search - compare with YEAR3.NDX
        results_new = ndx_find_number_range(ndx_filename, 1982, 1984)
        results_orig = ndx_find_number_range(os.path.join(self.samples_dir, "YEAR3.NDX"), 1982, 1984)
        
        self.assertEqual(results_new, results_orig, "YEARP.NDX should match YEAR3.NDX for range search")
        self.assertEqual(len(results_new), 449, "Should find 449 matches for 1982-1984")
        
        print(f"\nYEARP.NDX range search")
        print(f"  Range 1982-1984: {results_new[:10]} count={len(results_new)}")
        print("  ✅ Matches YEAR3.NDX!")
    
    def test_create_index_dateadd_exact(self):
        """Test creating DATEADDP.NDX and exact date search"""
        from ndx_module import ndx_create_index
        
        dbf_filename = os.path.join(self.samples_dir, "GAMES3.DBF")
        ndx_filename = os.path.join(self.samples_dir, "DATEADDP.NDX")
        
        # Create the index
        success = ndx_create_index(dbf_filename, "dateadd", ndx_filename)
        self.assertTrue(success, "Index creation should succeed")
        
        # Track for cleanup
        self.created_files.append(ndx_filename)
        
        # Test exact search - compare with DATEADD3.NDX
        results_new = ndx_find_date_exact(ndx_filename, "2022-08-25")
        results_orig = ndx_find_date_exact(os.path.join(self.samples_dir, "DATEADD3.NDX"), "2022-08-25")
        
        self.assertEqual(results_new, results_orig, "DATEADDP.NDX should match DATEADD3.NDX for exact search")
        self.assertEqual(len(results_new), 292, "Should find 292 matches for 2022-08-25")
        
        print(f"\nCreated index DATEADDP.NDX")
        print(f"  Exact search 2022-08-25: {results_new[:10]} count={len(results_new)}")
        print("  ✅ Matches DATEADD3.NDX!")
    
    def test_create_index_dateadd_range(self):
        """Test creating DATEADDP.NDX and range date search"""
        from ndx_module import ndx_create_index
        
        dbf_filename = os.path.join(self.samples_dir, "GAMES3.DBF")
        ndx_filename = os.path.join(self.samples_dir, "DATEADDP.NDX")
        
        # Create the index (or use existing from previous test)
        ndx_create_index(dbf_filename, "dateadd", ndx_filename)
        
        # Track for cleanup (avoid duplicates)
        if ndx_filename not in self.created_files:
            self.created_files.append(ndx_filename)
        
        # Test range search - compare with DATEADD3.NDX
        results_new = ndx_find_date_range(ndx_filename, "2022-08-01", "2022-08-30")
        results_orig = ndx_find_date_range(os.path.join(self.samples_dir, "DATEADD3.NDX"), "2022-08-01", "2022-08-30")
        
        self.assertEqual(results_new, results_orig, "DATEADDP.NDX should match DATEADD3.NDX for range search")
        self.assertEqual(len(results_new), 295, "Should find 295 matches for 2022-08-01 to 2022-08-30")
        
        print(f"\nDATEADDP.NDX range search")
        print(f"  Range 2022-08-01 to 2022-08-30: {results_new[:20]}")
        print(f"  Count={len(results_new)}")
        print("  ✅ Matches DATEADD3.NDX!")


if __name__ == "__main__":
    unittest.main(verbosity=2)
