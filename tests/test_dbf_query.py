"""
Tests for DBF query optimization module.

Tests heap maps and multi-field filtering with NDX indexes.
"""

import unittest
import os
import sys

# Add parent directory to path
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from dbf_query import DBFQueryBuilder, DBFHeapMap


class TestDBFHeapMap(unittest.TestCase):
    """Test cases for heap map functionality."""
    
    def setUp(self):
        """Set up test environment."""
        self.samples_dir = "samples"
        self.dbf_file = os.path.join(self.samples_dir, "GAMES3.DBF")
    
    def test_heap_map_year(self):
        """Test building heap map for year field."""
        heap_map = DBFHeapMap(self.dbf_file, "year")
        
        # Should have indexed records
        self.assertGreater(len(heap_map.recno_to_value), 0, "Should index records")
        self.assertGreater(len(heap_map.value_to_recnos), 0, "Should have value mappings")
        
        # Test exact match for 1984
        recnos_1984 = heap_map.find_exact(1984)
        self.assertGreater(len(recnos_1984), 0, "Should find records for 1984")
        
        print(f"\nHeap map for 'year':")
        print(f"  Total records indexed: {len(heap_map.recno_to_value)}")
        print(f"  Unique values: {len(heap_map.value_to_recnos)}")
        print(f"  Records with year=1984: {len(recnos_1984)}")
    
    def test_heap_map_range(self):
        """Test range queries on heap map."""
        heap_map = DBFHeapMap(self.dbf_file, "year")
        
        # Find games from 1982-1984
        recnos = heap_map.find_range(1982, 1984)
        
        self.assertGreater(len(recnos), 0, "Should find records in range")
        
        # Verify all values are in range
        for recno in recnos[:10]:  # Check first 10
            value = heap_map.recno_to_value.get(recno)
            self.assertIsNotNone(value, f"Recno {recno} should have value")
            self.assertGreaterEqual(value, 1982, f"Value {value} should be >= 1982")
            self.assertLessEqual(value, 1984, f"Value {value} should be <= 1984")
        
        print(f"\nRange query year 1982-1984:")
        print(f"  Found {len(recnos)} records")
        print(f"  First 10 recnos: {recnos[:10]}")
    
    def test_heap_map_filter(self):
        """Test filtering existing recnos."""
        heap_map = DBFHeapMap(self.dbf_file, "maxplay")
        
        # Start with some recnos
        input_recnos = list(range(1, 101))  # First 100 records
        
        # Filter to only 4-player games
        filtered = heap_map.filter_recnos(input_recnos, 4)
        
        self.assertLessEqual(len(filtered), len(input_recnos), "Filtered should be subset")
        
        # Verify all filtered records have maxplay=4
        for recno in filtered:
            self.assertEqual(heap_map.recno_to_value.get(recno), 4, 
                           f"Recno {recno} should have maxplay=4")
        
        print(f"\nFilter maxplay=4 on first 100 records:")
        print(f"  Input: {len(input_recnos)} records")
        print(f"  Output: {len(filtered)} records")


class TestDBFQueryBuilder(unittest.TestCase):
    """Test cases for query builder."""
    
    def setUp(self):
        """Set up test environment."""
        self.samples_dir = "samples"
        self.dbf_file = os.path.join(self.samples_dir, "GAMES3.DBF")
    
    def test_query_single_field(self):
        """Test query with single field filter."""
        query = DBFQueryBuilder(self.dbf_file)
        query.filter_by_value("year", 1984)
        
        recnos = query.execute()
        
        self.assertGreater(len(recnos), 0, "Should find records")
        
        # Verify results
        heap_map = query.heap_maps["year"]
        for recno in recnos[:10]:
            self.assertEqual(heap_map.recno_to_value.get(recno), 1984,
                           f"Recno {recno} should have year=1984")
        
        print(f"\nQuery: year=1984")
        print(f"  Results: {len(recnos)} records")
    
    def test_query_multiple_fields(self):
        """Test query with multiple field filters."""
        query = DBFQueryBuilder(self.dbf_file)
        query.filter_by_value("year", 1984)
        query.filter_by_value("maxplay", 4)
        
        recnos = query.execute()
        
        self.assertGreaterEqual(len(recnos), 0, "Query should execute")
        
        # Verify results
        year_map = query.heap_maps["year"]
        players_map = query.heap_maps["maxplay"]
        for recno in recnos[:10]:
            self.assertEqual(year_map.recno_to_value.get(recno), 1984)
            self.assertEqual(players_map.recno_to_value.get(recno), 4)
        
        print(f"\nQuery: year=1984 AND maxplay=4")
        print(f"  Results: {len(recnos)} records")
    
    def test_query_with_ndx_prefix(self):
        """Test query combining NDX prefix search with heap filters."""
        ndx_file = os.path.join(self.samples_dir, "TITLE3.NDX")
        
        if not os.path.exists(ndx_file):
            self.skipTest(f"NDX file not found: {ndx_file}")
        
        query = DBFQueryBuilder(self.dbf_file)
        query.filter_by_ndx_prefix(ndx_file, "King")
        query.filter_by_value("year", 1984)
        
        recnos = query.execute()
        
        self.assertGreaterEqual(len(recnos), 0, "Query should execute")
        
        print(f"\nQuery: title LIKE 'King%' AND year=1984")
        print(f"  Results: {len(recnos)} records")
        if recnos:
            print(f"  Sample recnos: {recnos[:10]}")
    
    def test_query_range(self):
        """Test query with range filter."""
        query = DBFQueryBuilder(self.dbf_file)
        query.filter_by_range("year", 1982, 1984)
        
        recnos = query.execute()
        
        self.assertGreater(len(recnos), 0, "Should find records in range")
        
        # Verify results are in range
        year_map = query.heap_maps["year"]
        for recno in recnos[:20]:
            year = year_map.recno_to_value.get(recno)
            self.assertGreaterEqual(year, 1982)
            self.assertLessEqual(year, 1984)
        
        print(f"\nQuery: year BETWEEN 1982 AND 1984")
        print(f"  Results: {len(recnos)} records")
    
    def test_query_stream(self):
        """Test streaming query results."""
        query = DBFQueryBuilder(self.dbf_file)
        query.filter_by_value("year", 1984)
        
        # Stream results
        count = 0
        first_10 = []
        for recno in query.execute_stream():
            count += 1
            if count <= 10:
                first_10.append(recno)
        
        self.assertGreater(count, 0, "Should stream records")
        
        print(f"\nStreaming query: year=1984")
        print(f"  Streamed {count} records")
        print(f"  First 10: {first_10}")


def demo_query_optimization():
    """Demonstrate query optimization benefits."""
    print("\n" + "=" * 70)
    print("Query Optimization Demo")
    print("=" * 70)
    
    dbf_file = "samples/GAMES3.DBF"
    
    # Example 1: NDX + heap filters (optimal)
    print("\n1. Optimized Query: NDX prefix + heap filters")
    print("   Query: title LIKE 'King%' AND year=1984 AND maxplay=4")
    
    if os.path.exists("samples/TITLE3.NDX"):
        query = DBFQueryBuilder(dbf_file)
        query.filter_by_ndx_prefix("samples/TITLE3.NDX", "King")  # Most selective first
        query.filter_by_value("year", 1984)
        query.filter_by_value("maxplay", 4)
        recnos = query.execute()
        print(f"   ✅ Found {len(recnos)} matching records")
    else:
        print("   ⚠️  TITLE3.NDX not found, skipping")
    
    # Example 2: Multiple heap filters
    print("\n2. Heap Map Query: Multiple numeric filters")
    print("   Query: year BETWEEN 1982 AND 1984 AND maxplay >= 2")
    
    query = DBFQueryBuilder(dbf_file)
    query.filter_by_range("year", 1982, 1984)
    query.filter_by_range("maxplay", 2, 99)
    recnos = query.execute()
    print(f"   ✅ Found {len(recnos)} matching records")
    
    # Example 3: Exact match on indexed field
    print("\n3. NDX Exact Match + Filter")
    print("   Query: devname = 'Sierra On-Line, Inc.' AND year >= 1985")
    
    if os.path.exists("samples/DEVNAME3.NDX"):
        query = DBFQueryBuilder(dbf_file)
        query.filter_by_ndx_exact("samples/DEVNAME3.NDX", "Sierra On-Line, Inc.")
        query.filter_by_range("year", 1985, 9999)
        recnos = query.execute()
        print(f"   ✅ Found {len(recnos)} matching records")
    else:
        print("   ⚠️  DEVNAME3.NDX not found, skipping")
    
    print("\n" + "=" * 70)


if __name__ == "__main__":
    # Run demo first
    demo_query_optimization()
    
    # Then run tests
    print("\n\nRunning unit tests...")
    unittest.main(verbosity=2)
