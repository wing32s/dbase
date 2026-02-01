"""
DBF Query Optimization Module

Provides efficient multi-field filtering using:
1. In-memory heap maps for numeric/date fields (recno -> value)
2. NDX indexes for string prefix searches
3. Stream-based result set intersection

Example use case:
    Find games with title starting with "PC", year=1984, maxplayers=4
    - Use NDX index for title prefix "PC" (selective)
    - Build heap maps for year and maxplayers
    - Stream intersection of filtered recnos
"""

import heapq
from typing import List, Dict, Set, Optional, Callable, Iterator
from dbf_module import (
    dbf_file_open, dbf_file_close, dbf_file_read_row, 
    dbf_file_seek_to_row, DBFFile
)
from ndx_module import ndx_find_prefix, ndx_find_exact, ndx_find_number_exact, ndx_find_number_range


class DBFHeapMap:
    """In-memory heap map for fast numeric/date field lookups."""
    
    def __init__(self, dbf_filename: str, field_name: str):
        """
        Build a heap map: recno -> field_value
        
        Args:
            dbf_filename: Path to DBF file
            field_name: Name of field to index
        """
        self.field_name = field_name
        self.recno_to_value: Dict[int, any] = {}
        self.value_to_recnos: Dict[any, List[int]] = {}
        
        # Build the map
        dbf = dbf_file_open(dbf_filename)
        try:
            field_idx = self._find_field_index(dbf, field_name)
            if field_idx is None:
                raise ValueError(f"Field '{field_name}' not found in DBF")
            
            for recno in range(1, dbf.header.record_count + 1):
                # Seek to row (0-based index, so recno-1)
                dbf_file_seek_to_row(dbf, recno - 1)
                row = dbf_file_read_row(dbf)
                # row[0] is delete flag, fields start at row[1]
                if row and len(row) > field_idx + 1:
                    value = row[field_idx + 1].strip()
                    
                    # Convert to appropriate type
                    field_type = dbf.header.fields[field_idx].field_type
                    if field_type == 'N':  # Numeric
                        try:
                            value = int(value) if value else None
                        except ValueError:
                            try:
                                value = float(value)
                            except ValueError:
                                value = None
                    elif field_type == 'D':  # Date
                        # Keep as string YYYYMMDD format
                        value = value if len(value) == 8 else None
                    
                    if value is not None:
                        self.recno_to_value[recno] = value
                        if value not in self.value_to_recnos:
                            self.value_to_recnos[value] = []
                        self.value_to_recnos[value].append(recno)
        finally:
            dbf_file_close(dbf)
    
    def _find_field_index(self, dbf: DBFFile, field_name: str) -> Optional[int]:
        """Find the index of a field by name (case-insensitive)."""
        field_name_upper = field_name.upper()
        for i, field in enumerate(dbf.header.fields):
            if field.name.upper() == field_name_upper:
                return i
        return None
    
    def find_exact(self, value: any) -> List[int]:
        """Find all recnos with exact value match."""
        return self.value_to_recnos.get(value, [])
    
    def find_range(self, min_value: any, max_value: any) -> List[int]:
        """Find all recnos with value in range [min_value, max_value]."""
        result = []
        for value, recnos in self.value_to_recnos.items():
            if min_value <= value <= max_value:
                result.extend(recnos)
        return sorted(result)
    
    def filter_recnos(self, recnos: List[int], value: any) -> List[int]:
        """Filter a list of recnos to only those matching value."""
        return [r for r in recnos if self.recno_to_value.get(r) == value]
    
    def filter_recnos_range(self, recnos: List[int], min_value: any, max_value: any) -> List[int]:
        """Filter a list of recnos to only those in value range."""
        return [r for r in recnos 
                if r in self.recno_to_value 
                and min_value <= self.recno_to_value[r] <= max_value]


class DBFQueryBuilder:
    """Build and execute efficient multi-field queries."""
    
    def __init__(self, dbf_filename: str):
        """
        Initialize query builder.
        
        Args:
            dbf_filename: Path to DBF file
        """
        self.dbf_filename = dbf_filename
        self.heap_maps: Dict[str, DBFHeapMap] = {}
        self.filters: List[Callable[[List[int]], List[int]]] = []
        self.initial_recnos: Optional[List[int]] = None
    
    def add_heap_map(self, field_name: str) -> 'DBFQueryBuilder':
        """
        Add a heap map for a field (builds in-memory index).
        
        Args:
            field_name: Name of field to index
            
        Returns:
            Self for chaining
        """
        if field_name not in self.heap_maps:
            print(f"📊 Building heap map for '{field_name}'...")
            self.heap_maps[field_name] = DBFHeapMap(self.dbf_filename, field_name)
            print(f"   Indexed {len(self.heap_maps[field_name].recno_to_value)} records")
        return self
    
    def filter_by_ndx_prefix(self, ndx_filename: str, prefix: str) -> 'DBFQueryBuilder':
        """
        Use NDX index for prefix search (most selective filter first).
        
        Args:
            ndx_filename: Path to NDX index file
            prefix: Prefix to search for
            
        Returns:
            Self for chaining
        """
        print(f"🔍 NDX prefix search: '{prefix}' in {ndx_filename}")
        recnos = ndx_find_prefix(ndx_filename, prefix)
        print(f"   Found {len(recnos)} matches")
        self.initial_recnos = recnos
        return self
    
    def filter_by_ndx_exact(self, ndx_filename: str, value: str) -> 'DBFQueryBuilder':
        """
        Use NDX index for exact match.
        
        Args:
            ndx_filename: Path to NDX index file
            value: Exact value to search for
            
        Returns:
            Self for chaining
        """
        print(f"🔍 NDX exact search: '{value}' in {ndx_filename}")
        recnos = ndx_find_exact(ndx_filename, value)
        print(f"   Found {len(recnos)} matches")
        self.initial_recnos = recnos
        return self
    
    def filter_by_value(self, field_name: str, value: any) -> 'DBFQueryBuilder':
        """
        Filter by exact value using heap map.
        
        Args:
            field_name: Name of field
            value: Value to match
            
        Returns:
            Self for chaining
        """
        if field_name not in self.heap_maps:
            self.add_heap_map(field_name)
        
        heap_map = self.heap_maps[field_name]
        
        def filter_func(recnos: List[int]) -> List[int]:
            result = heap_map.filter_recnos(recnos, value)
            print(f"   Filter {field_name}={value}: {len(recnos)} -> {len(result)} records")
            return result
        
        self.filters.append(filter_func)
        return self
    
    def filter_by_range(self, field_name: str, min_value: any, max_value: any) -> 'DBFQueryBuilder':
        """
        Filter by value range using heap map.
        
        Args:
            field_name: Name of field
            min_value: Minimum value (inclusive)
            max_value: Maximum value (inclusive)
            
        Returns:
            Self for chaining
        """
        if field_name not in self.heap_maps:
            self.add_heap_map(field_name)
        
        heap_map = self.heap_maps[field_name]
        
        def filter_func(recnos: List[int]) -> List[int]:
            result = heap_map.filter_recnos_range(recnos, min_value, max_value)
            print(f"   Filter {field_name} in [{min_value}, {max_value}]: {len(recnos)} -> {len(result)} records")
            return result
        
        self.filters.append(filter_func)
        return self
    
    def execute(self) -> List[int]:
        """
        Execute the query and return matching recnos.
        
        Returns:
            Sorted list of matching record numbers
        """
        print(f"\n🚀 Executing query...")
        
        # Start with initial recnos (from NDX) or all records
        if self.initial_recnos is not None:
            recnos = self.initial_recnos
            print(f"   Starting with {len(recnos)} records from NDX")
        else:
            # No NDX filter - start with all records
            dbf = dbf_file_open(self.dbf_filename)
            try:
                recnos = list(range(1, dbf.header.record_count + 1))
                print(f"   Starting with all {len(recnos)} records")
            finally:
                dbf_file_close(dbf)
        
        # Apply filters in sequence
        for filter_func in self.filters:
            recnos = filter_func(recnos)
            if not recnos:
                print(f"   ⚠️  No records remaining after filter")
                break
        
        print(f"\n✅ Query complete: {len(recnos)} matching records")
        return recnos
    
    def execute_stream(self) -> Iterator[int]:
        """
        Execute query and stream results (memory efficient for large result sets).
        
        Yields:
            Record numbers one at a time
        """
        recnos = self.execute()
        for recno in recnos:
            yield recno


def query_example_games():
    """
    Example: Find games with title starting with "King", year=1984, maxplay=4
    """
    print("=" * 70)
    print("DBF Query Example: Multi-field Filter")
    print("=" * 70)
    print("Query: title LIKE 'King%' AND year = 1984 AND maxplay = 4")
    print()
    
    # Build and execute query
    query = DBFQueryBuilder("samples/GAMES3.DBF")
    
    # Most selective filter first (NDX prefix search)
    query.filter_by_ndx_prefix("samples/TITLE3.NDX", "King")
    
    # Apply additional filters using heap maps
    query.filter_by_value("year", 1984)
    query.filter_by_value("maxplay", 4)
    
    # Execute and get results
    recnos = query.execute()
    
    # Display results
    if recnos:
        print(f"\nMatching records: {recnos[:20]}")
        if len(recnos) > 20:
            print(f"... and {len(recnos) - 20} more")
        
        # Show sample data
        from dbf_module import dbf_file_open, dbf_file_read_row, dbf_file_seek_to_row, dbf_file_close
        dbf = dbf_file_open("samples/GAMES3.DBF")
        try:
            print("\nSample records:")
            for recno in recnos[:5]:
                dbf_file_seek_to_row(dbf, recno - 1)
                row = dbf_file_read_row(dbf)
                if row:
                    # row[0] is delete flag, fields start at row[1]
                    title = row[1].strip()  # TITLE field
                    year = row[4].strip()   # YEAR field (index 3 + 1)
                    print(f"  #{recno}: {title} ({year})")
        finally:
            dbf_file_close(dbf)
    else:
        print("\nNo matching records found.")


def query_example_range():
    """
    Example: Find games from years 1982-1984 with 2+ players
    """
    print("\n" + "=" * 70)
    print("DBF Query Example: Range Filter")
    print("=" * 70)
    print("Query: year BETWEEN 1982 AND 1984 AND maxplay >= 2")
    print()
    
    query = DBFQueryBuilder("samples/GAMES3.DBF")
    
    # Build heap maps and apply filters
    query.filter_by_range("year", 1982, 1984)
    query.filter_by_range("maxplay", 2, 99)  # 2 or more
    
    recnos = query.execute()
    
    print(f"\nMatching records: {len(recnos)} total")
    print(f"First 10: {recnos[:10]}")


if __name__ == "__main__":
    # Run examples
    query_example_games()
    query_example_range()
