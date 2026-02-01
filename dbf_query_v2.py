"""
DBF Query Optimization Module v2

Advanced query system with:
1. Filter groups (up to 8 filters per group with OR/AND logic)
2. Multiple groups (up to 4) combined with AND
3. Unified heap map for all non-string columns
4. Queue-based lazy evaluation for string filters

Architecture:
    - Apply NDX string filters first (most selective)
    - Build single unified heap map for all numeric/date columns
    - Queue string filters for lazy evaluation
    - Combine filter groups with AND logic

Example:
    (title LIKE 'King%' OR title LIKE 'Queen%') 
    AND (year = 1984 OR year = 1985)
    AND (maxplay >= 2)
"""

from typing import List, Dict, Set, Optional, Callable, Iterator, Tuple
from enum import Enum
from dbf_module import (
    dbf_file_open, dbf_file_close, dbf_file_read_row, 
    dbf_file_seek_to_row, DBFFile
)
from ndx_module import ndx_find_prefix, ndx_find_exact, ndx_find_number_exact, ndx_find_number_range


class FilterOp(Enum):
    """Filter operation types."""
    EQUAL = "="
    NOT_EQUAL = "!="
    LESS_THAN = "<"
    LESS_EQUAL = "<="
    GREATER_THAN = ">"
    GREATER_EQUAL = ">="
    BETWEEN = "BETWEEN"
    IN = "IN"
    LIKE = "LIKE"  # Prefix match
    BIT_SET = "BIT_SET"  # Check if bit is set
    BIT_CLEAR = "BIT_CLEAR"  # Check if bit is clear
    BIT_MASK_ALL = "BIT_MASK_ALL"  # Check if all bits in mask are set
    BIT_MASK_ANY = "BIT_MASK_ANY"  # Check if any bits in mask are set


class GroupOp(Enum):
    """Logical operators for combining filters within a group."""
    AND = "AND"
    OR = "OR"


class UnifiedHeapMap:
    """Single heap map containing all non-string columns."""
    
    def __init__(self, dbf_filename: str, field_names: List[str]):
        """
        Build unified heap map for multiple fields.
        
        Args:
            dbf_filename: Path to DBF file
            field_names: List of field names to index
        """
        self.dbf_filename = dbf_filename
        self.field_names = field_names
        self.field_indices: Dict[str, int] = {}
        self.field_types: Dict[str, str] = {}
        
        # Single map: recno -> {field_name: value}
        self.recno_to_values: Dict[int, Dict[str, any]] = {}
        
        # Reverse maps: field_name -> {value: [recnos]}
        self.value_to_recnos: Dict[str, Dict[any, List[int]]] = {}
        
        self._build_map()
    
    def _build_map(self):
        """Build the unified heap map."""
        dbf = dbf_file_open(self.dbf_filename)
        try:
            # Get field indices and types
            for field_name in self.field_names:
                field_idx = self._find_field_index(dbf, field_name)
                if field_idx is None:
                    raise ValueError(f"Field '{field_name}' not found in DBF")
                self.field_indices[field_name] = field_idx
                self.field_types[field_name] = dbf.header.fields[field_idx].field_type
                self.value_to_recnos[field_name] = {}
            
            # Scan all records once
            for recno in range(1, dbf.header.record_count + 1):
                dbf_file_seek_to_row(dbf, recno - 1)
                row = dbf_file_read_row(dbf)
                
                if not row:
                    continue
                
                record_values = {}
                
                # Extract all indexed fields
                for field_name, field_idx in self.field_indices.items():
                    # row[0] is delete flag, fields start at row[1]
                    if len(row) > field_idx + 1:
                        value = row[field_idx + 1].strip()
                        
                        # Convert to appropriate type
                        field_type = self.field_types[field_name]
                        if field_type == 'N':  # Numeric
                            try:
                                value = int(value) if value and '.' not in value else float(value) if value else None
                            except ValueError:
                                value = None
                        elif field_type == 'D':  # Date - convert to integer for efficient comparison
                            if len(value) == 8 and value.isdigit():
                                value = int(value)  # YYYYMMDD as integer (e.g., 20220825)
                            else:
                                value = None
                        elif field_type == 'L':  # Logical - convert to boolean
                            value = value.upper() in ('T', 'Y', '1') if value else None
                        
                        if value is not None:
                            record_values[field_name] = value
                            
                            # Update reverse index
                            if value not in self.value_to_recnos[field_name]:
                                self.value_to_recnos[field_name][value] = []
                            self.value_to_recnos[field_name][value].append(recno)
                
                if record_values:
                    self.recno_to_values[recno] = record_values
        finally:
            dbf_file_close(dbf)
    
    def _find_field_index(self, dbf: DBFFile, field_name: str) -> Optional[int]:
        """Find the index of a field by name (case-insensitive)."""
        field_name_upper = field_name.upper()
        for i, field in enumerate(dbf.header.fields):
            if field.name.upper() == field_name_upper:
                return i
        return None
    
    def evaluate_filter(self, recnos: List[int], field_name: str, op: FilterOp, value: any, value2: any = None) -> List[int]:
        """
        Evaluate a filter on a list of recnos.
        
        Args:
            recnos: Input record numbers
            field_name: Field to filter on
            op: Filter operation
            value: Filter value
            value2: Second value (for BETWEEN)
            
        Returns:
            Filtered list of record numbers
        """
        result = []
        
        for recno in recnos:
            record_values = self.recno_to_values.get(recno)
            if not record_values:
                continue
            
            field_value = record_values.get(field_name)
            if field_value is None:
                continue
            
            # Evaluate operation
            match = False
            if op == FilterOp.EQUAL:
                match = field_value == value
            elif op == FilterOp.NOT_EQUAL:
                match = field_value != value
            elif op == FilterOp.LESS_THAN:
                match = field_value < value
            elif op == FilterOp.LESS_EQUAL:
                match = field_value <= value
            elif op == FilterOp.GREATER_THAN:
                match = field_value > value
            elif op == FilterOp.GREATER_EQUAL:
                match = field_value >= value
            elif op == FilterOp.BETWEEN:
                match = value <= field_value <= value2
            elif op == FilterOp.IN:
                match = field_value in value  # value should be a list
            elif op == FilterOp.BIT_SET:
                # Check if specific bit is set (value is bit position, 0-based)
                if isinstance(field_value, int):
                    match = (field_value & (1 << value)) != 0
            elif op == FilterOp.BIT_CLEAR:
                # Check if specific bit is clear
                if isinstance(field_value, int):
                    match = (field_value & (1 << value)) == 0
            elif op == FilterOp.BIT_MASK_ALL:
                # Check if all bits in mask are set (value is bitmask)
                if isinstance(field_value, int):
                    match = (field_value & value) == value
            elif op == FilterOp.BIT_MASK_ANY:
                # Check if any bits in mask are set
                if isinstance(field_value, int):
                    match = (field_value & value) != 0
            
            if match:
                result.append(recno)
        
        return result


class Filter:
    """Single filter condition."""
    
    def __init__(self, field_name: str, op: FilterOp, value: any, value2: any = None, ndx_file: str = None):
        """
        Create a filter.
        
        Args:
            field_name: Field to filter on
            op: Filter operation
            value: Filter value
            value2: Second value (for BETWEEN)
            ndx_file: NDX index file (for string filters)
        """
        self.field_name = field_name
        self.op = op
        self.value = value
        self.value2 = value2
        self.ndx_file = ndx_file
        self.is_string_filter = ndx_file is not None


class FilterGroup:
    """Group of filters combined with AND/OR logic (max 8 filters)."""
    
    MAX_FILTERS = 8
    
    def __init__(self, operator: GroupOp = GroupOp.AND):
        """
        Create a filter group.
        
        Args:
            operator: Logical operator (AND/OR) for combining filters
        """
        self.operator = operator
        self.filters: List[Filter] = []
    
    def add_filter(self, filter: Filter) -> 'FilterGroup':
        """
        Add a filter to the group.
        
        Args:
            filter: Filter to add
            
        Returns:
            Self for chaining
            
        Raises:
            ValueError: If group already has MAX_FILTERS filters
        """
        if len(self.filters) >= self.MAX_FILTERS:
            raise ValueError(f"Filter group can have at most {self.MAX_FILTERS} filters")
        self.filters.append(filter)
        return self
    
    def evaluate(self, recnos: List[int], heap_map: UnifiedHeapMap, dbf: DBFFile) -> List[int]:
        """
        Evaluate all filters in the group.
        
        Args:
            recnos: Input record numbers
            heap_map: Unified heap map for non-string filters
            dbf: Open DBF file for string filter evaluation
            
        Returns:
            Filtered list of record numbers
        """
        if not self.filters:
            return recnos
        
        if self.operator == GroupOp.AND:
            # AND: Apply filters sequentially
            result = recnos
            for filter in self.filters:
                result = self._evaluate_single_filter(result, filter, heap_map, dbf)
                if not result:
                    break
            return result
        else:
            # OR: Collect results from each filter and union
            all_results = set()
            recno_set = set(recnos)
            
            for filter in self.filters:
                filtered = self._evaluate_single_filter(recnos, filter, heap_map, dbf)
                all_results.update(filtered)
                
                # Short-circuit: If we've matched all input records, no need to continue
                if len(all_results) == len(recno_set):
                    break
            
            return sorted(list(all_results))
    
    def _evaluate_single_filter(self, recnos: List[int], filter: Filter, heap_map: UnifiedHeapMap, dbf: DBFFile) -> List[int]:
        """Evaluate a single filter."""
        if filter.is_string_filter:
            # String filter: use NDX or lazy evaluation
            if filter.ndx_file:
                if filter.op == FilterOp.LIKE:
                    ndx_results = ndx_find_prefix(filter.ndx_file, filter.value)
                elif filter.op == FilterOp.EQUAL:
                    ndx_results = ndx_find_exact(filter.ndx_file, filter.value)
                else:
                    raise ValueError(f"Unsupported NDX operation: {filter.op}")
                
                # Intersect with input recnos
                recno_set = set(recnos)
                return sorted([r for r in ndx_results if r in recno_set])
            else:
                # Lazy string evaluation (queue-based)
                return self._lazy_string_filter(recnos, filter, dbf)
        else:
            # Non-string filter: use heap map
            return heap_map.evaluate_filter(recnos, filter.field_name, filter.op, filter.value, filter.value2)
    
    def _lazy_string_filter(self, recnos: List[int], filter: Filter, dbf: DBFFile) -> List[int]:
        """
        Lazy evaluation of string filter (queue-based).
        Pull next record, compare, keep or skip.
        """
        result = []
        field_idx = None
        
        # Find field index
        for i, field in enumerate(dbf.header.fields):
            if field.name.upper() == filter.field_name.upper():
                field_idx = i
                break
        
        if field_idx is None:
            return []
        
        # Queue-based evaluation
        for recno in recnos:
            dbf_file_seek_to_row(dbf, recno - 1)
            row = dbf_file_read_row(dbf)
            
            if row and len(row) > field_idx + 1:
                field_value = row[field_idx + 1].strip()
                
                # Evaluate operation
                match = False
                if filter.op == FilterOp.EQUAL:
                    match = field_value == filter.value
                elif filter.op == FilterOp.LIKE:
                    match = field_value.startswith(filter.value)
                
                if match:
                    result.append(recno)
        
        return result


class DBFQuery:
    """Advanced query builder with filter groups."""
    
    MAX_GROUPS = 4
    
    def __init__(self, dbf_filename: str):
        """
        Initialize query.
        
        Args:
            dbf_filename: Path to DBF file
        """
        self.dbf_filename = dbf_filename
        self.groups: List[FilterGroup] = []
        self.heap_map: Optional[UnifiedHeapMap] = None
        self.non_string_fields: Set[str] = set()
    
    def add_group(self, group: FilterGroup) -> 'DBFQuery':
        """
        Add a filter group (max 4 groups).
        
        Args:
            group: Filter group to add
            
        Returns:
            Self for chaining
            
        Raises:
            ValueError: If already have MAX_GROUPS groups
        """
        if len(self.groups) >= self.MAX_GROUPS:
            raise ValueError(f"Query can have at most {self.MAX_GROUPS} filter groups")
        self.groups.append(group)
        
        # Track non-string fields for heap map
        for filter in group.filters:
            if not filter.is_string_filter:
                self.non_string_fields.add(filter.field_name)
        
        return self
    
    def execute(self) -> List[int]:
        """
        Execute the query.
        
        Returns:
            Sorted list of matching record numbers
        """
        if not self.groups:
            return []
        
        print(f"\n🚀 Executing query with {len(self.groups)} filter group(s)...")
        
        # Build unified heap map for all non-string fields
        if self.non_string_fields and not self.heap_map:
            print(f"📊 Building unified heap map for fields: {sorted(self.non_string_fields)}")
            self.heap_map = UnifiedHeapMap(self.dbf_filename, list(self.non_string_fields))
            print(f"   Indexed {len(self.heap_map.recno_to_values)} records")
        
        # Start with all records
        dbf = dbf_file_open(self.dbf_filename)
        try:
            recnos = list(range(1, dbf.header.record_count + 1))
            print(f"   Starting with {len(recnos)} records")
            
            # Apply each group with AND logic
            for i, group in enumerate(self.groups):
                print(f"\n   Group {i+1} ({group.operator.value}, {len(group.filters)} filters):")
                recnos = group.evaluate(recnos, self.heap_map, dbf)
                print(f"      → {len(recnos)} records remain")
                
                if not recnos:
                    print(f"      ⚠️  No records remaining")
                    break
            
            print(f"\n✅ Query complete: {len(recnos)} matching records")
            return recnos
        finally:
            dbf_file_close(dbf)


# Helper functions for building queries

def equal(field: str, value: any, ndx_file: str = None) -> Filter:
    """Create EQUAL filter."""
    return Filter(field, FilterOp.EQUAL, value, ndx_file=ndx_file)

def not_equal(field: str, value: any) -> Filter:
    """Create NOT_EQUAL filter."""
    return Filter(field, FilterOp.NOT_EQUAL, value)

def less_than(field: str, value: any) -> Filter:
    """Create LESS_THAN filter."""
    return Filter(field, FilterOp.LESS_THAN, value)

def less_equal(field: str, value: any) -> Filter:
    """Create LESS_EQUAL filter."""
    return Filter(field, FilterOp.LESS_EQUAL, value)

def greater_than(field: str, value: any) -> Filter:
    """Create GREATER_THAN filter."""
    return Filter(field, FilterOp.GREATER_THAN, value)

def greater_equal(field: str, value: any) -> Filter:
    """Create GREATER_EQUAL filter."""
    return Filter(field, FilterOp.GREATER_EQUAL, value)

def between(field: str, min_value: any, max_value: any) -> Filter:
    """Create BETWEEN filter."""
    return Filter(field, FilterOp.BETWEEN, min_value, max_value)

def in_list(field: str, values: List[any]) -> Filter:
    """Create IN filter."""
    return Filter(field, FilterOp.IN, values)

def like(field: str, prefix: str, ndx_file: str) -> Filter:
    """Create LIKE (prefix match) filter using NDX index."""
    return Filter(field, FilterOp.LIKE, prefix, ndx_file=ndx_file)

def date_equal(field: str, year: int, month: int, day: int) -> Filter:
    """
    Create date equality filter.
    
    Args:
        field: Date field name
        year: Year (e.g., 2022)
        month: Month (1-12)
        day: Day (1-31)
    
    Returns:
        Filter for exact date match
    
    Example:
        date_equal("dateadd", 2022, 8, 25)  # Matches 20220825
    """
    date_value = year * 10000 + month * 100 + day
    return Filter(field, FilterOp.EQUAL, date_value)

def date_between(field: str, start_year: int, start_month: int, start_day: int,
                 end_year: int, end_month: int, end_day: int) -> Filter:
    """
    Create date range filter.
    
    Args:
        field: Date field name
        start_year, start_month, start_day: Start date
        end_year, end_month, end_day: End date
    
    Returns:
        Filter for date range
    
    Example:
        date_between("dateadd", 2022, 1, 1, 2022, 12, 31)  # All of 2022
    """
    start_value = start_year * 10000 + start_month * 100 + start_day
    end_value = end_year * 10000 + end_month * 100 + end_day
    return Filter(field, FilterOp.BETWEEN, start_value, end_value)

def date_after(field: str, year: int, month: int, day: int) -> Filter:
    """
    Create date > filter.
    
    Example:
        date_after("dateadd", 2022, 6, 30)  # After June 30, 2022
    """
    date_value = year * 10000 + month * 100 + day
    return Filter(field, FilterOp.GREATER_THAN, date_value)

def date_before(field: str, year: int, month: int, day: int) -> Filter:
    """
    Create date < filter.
    
    Example:
        date_before("dateadd", 2023, 1, 1)  # Before Jan 1, 2023
    """
    date_value = year * 10000 + month * 100 + day
    return Filter(field, FilterOp.LESS_THAN, date_value)

def date_year(field: str, year: int) -> Filter:
    """
    Create filter for all dates in a specific year.
    
    Args:
        field: Date field name
        year: Year (e.g., 2022)
    
    Returns:
        Filter for entire year
    
    Example:
        date_year("dateadd", 2022)  # All dates in 2022
    """
    start_value = year * 10000 + 101  # Jan 1
    end_value = year * 10000 + 1231   # Dec 31
    return Filter(field, FilterOp.BETWEEN, start_value, end_value)

def logical_true(field: str) -> Filter:
    """
    Create filter for logical field = TRUE.
    
    Args:
        field: Logical field name
    
    Returns:
        Filter for TRUE values
    
    Example:
        logical_true("is_active")  # Where is_active = TRUE
    """
    return Filter(field, FilterOp.EQUAL, True)

def logical_false(field: str) -> Filter:
    """
    Create filter for logical field = FALSE.
    
    Args:
        field: Logical field name
    
    Returns:
        Filter for FALSE values
    
    Example:
        logical_false("is_deleted")  # Where is_deleted = FALSE
    """
    return Filter(field, FilterOp.EQUAL, False)

def bit_set(field: str, bit_position: int) -> Filter:
    """
    Create filter to check if a specific bit is set.
    
    Args:
        field: Numeric field name (containing bit flags)
        bit_position: Bit position to check (0-based, 0 = LSB)
    
    Returns:
        Filter for records where bit is set
    
    Example:
        bit_set("flags", 3)  # Check if bit 3 is set
        # For value 0b1010 (10), bit 3 is set, bit 2 is clear
    """
    return Filter(field, FilterOp.BIT_SET, bit_position)

def bit_clear(field: str, bit_position: int) -> Filter:
    """
    Create filter to check if a specific bit is clear.
    
    Args:
        field: Numeric field name (containing bit flags)
        bit_position: Bit position to check (0-based)
    
    Returns:
        Filter for records where bit is clear
    
    Example:
        bit_clear("flags", 2)  # Check if bit 2 is clear
    """
    return Filter(field, FilterOp.BIT_CLEAR, bit_position)

def bit_mask_all(field: str, mask: int) -> Filter:
    """
    Create filter to check if all bits in mask are set.
    
    Args:
        field: Numeric field name (containing bit flags)
        mask: Bitmask to check
    
    Returns:
        Filter for records where all mask bits are set
    
    Example:
        bit_mask_all("flags", 0b1010)  # Check if bits 1 and 3 are both set
        # Matches: 0b1010, 0b1011, 0b1110, 0b1111, etc.
    """
    return Filter(field, FilterOp.BIT_MASK_ALL, mask)

def bit_mask_any(field: str, mask: int) -> Filter:
    """
    Create filter to check if any bits in mask are set.
    
    Args:
        field: Numeric field name (containing bit flags)
        mask: Bitmask to check
    
    Returns:
        Filter for records where any mask bits are set
    
    Example:
        bit_mask_any("flags", 0b1010)  # Check if bit 1 OR bit 3 is set
        # Matches: 0b0010, 0b1000, 0b1010, 0b1011, etc.
    """
    return Filter(field, FilterOp.BIT_MASK_ANY, mask)


# Example usage

def example_complex_query():
    """
    Example: Complex query with multiple filter groups.
    
    Query: (title LIKE 'King%' OR title LIKE 'Queen%')
           AND (year = 1984 OR year = 1985)
           AND (maxplay >= 2)
    """
    print("=" * 70)
    print("Complex Query Example")
    print("=" * 70)
    print("Query: (title LIKE 'King%' OR title LIKE 'Queen%')")
    print("       AND (year = 1984 OR year = 1985)")
    print("       AND (maxplay >= 2)")
    
    query = DBFQuery("samples/GAMES3.DBF")
    
    # Group 1: Title filters (OR)
    group1 = FilterGroup(GroupOp.OR)
    group1.add_filter(like("title", "King", "samples/TITLE3.NDX"))
    group1.add_filter(like("title", "Queen", "samples/TITLE3.NDX"))
    query.add_group(group1)
    
    # Group 2: Year filters (OR)
    group2 = FilterGroup(GroupOp.OR)
    group2.add_filter(equal("year", 1984))
    group2.add_filter(equal("year", 1985))
    query.add_group(group2)
    
    # Group 3: Player count filter
    group3 = FilterGroup(GroupOp.AND)
    group3.add_filter(greater_equal("maxplay", 2))
    query.add_group(group3)
    
    # Execute
    recnos = query.execute()
    
    print(f"\nMatching records: {len(recnos)}")
    if recnos:
        print(f"First 10: {recnos[:10]}")


def example_simple_query():
    """
    Example: Simple query with single group.
    
    Query: year = 1984 AND maxplay = 4
    """
    print("\n" + "=" * 70)
    print("Simple Query Example")
    print("=" * 70)
    print("Query: year = 1984 AND maxplay = 4")
    
    query = DBFQuery("samples/GAMES3.DBF")
    
    # Single group with AND
    group = FilterGroup(GroupOp.AND)
    group.add_filter(equal("year", 1984))
    group.add_filter(equal("maxplay", 4))
    query.add_group(group)
    
    # Execute
    recnos = query.execute()
    
    print(f"\nMatching records: {len(recnos)}")
    if recnos:
        print(f"Records: {recnos[:20]}")


def example_date_query():
    """
    Example: Query with date filters.
    
    Query: dateadd BETWEEN 2018-01-01 AND 2018-12-31
           AND year >= 1985
    """
    print("\n" + "=" * 70)
    print("Date Query Example")
    print("=" * 70)
    print("Query: dateadd in 2018 AND year >= 1985")
    
    query = DBFQuery("samples/GAMES3.DBF")
    
    # Group 1: Date range (all of 2018)
    group1 = FilterGroup(GroupOp.AND)
    group1.add_filter(date_between("dateadd", 2018, 1, 1, 2018, 12, 31))
    query.add_group(group1)
    
    # Group 2: Year filter
    group2 = FilterGroup(GroupOp.AND)
    group2.add_filter(greater_equal("year", 1985))
    query.add_group(group2)
    
    # Execute
    recnos = query.execute()
    
    print(f"\nMatching records: {len(recnos)}")
    if recnos:
        print(f"First 10: {recnos[:10]}")


def example_bitflag_query():
    """
    Example: Query with bit flag operations.
    
    Demonstrates checking individual bits in numeric fields.
    Note: This is a conceptual example - GAMES3.DBF doesn't have bit flags.
    """
    print("\n" + "=" * 70)
    print("Bit Flag Query Example (Conceptual)")
    print("=" * 70)
    print("Query: Check if bit 3 is set in flags field")
    print("       AND bit 5 is clear")
    print()
    print("Bit operations:")
    print("  bit_set(field, 3)       - Check if bit 3 is set")
    print("  bit_clear(field, 5)     - Check if bit 5 is clear")
    print("  bit_mask_all(field, 0b1010) - Check if bits 1 and 3 are both set")
    print("  bit_mask_any(field, 0b1010) - Check if bit 1 OR bit 3 is set")
    print()
    print("Example bit values:")
    print("  0b00001000 (8)  - Bit 3 is set")
    print("  0b00101000 (40) - Bits 3 and 5 are set")
    print("  0b00001010 (10) - Bits 1 and 3 are set")
    
    # Conceptual query structure (would work with a flags field)
    # query = DBFQuery("data.DBF")
    # 
    # group = FilterGroup(GroupOp.AND)
    # group.add_filter(bit_set("flags", 3))      # Bit 3 must be set
    # group.add_filter(bit_clear("flags", 5))    # Bit 5 must be clear
    # query.add_group(group)
    # 
    # recnos = query.execute()


def example_logical_query():
    """
    Example: Query with logical field operations.
    
    Demonstrates filtering on boolean/logical fields.
    Note: This is a conceptual example - GAMES3.DBF doesn't have logical fields.
    """
    print("\n" + "=" * 70)
    print("Logical Field Query Example (Conceptual)")
    print("=" * 70)
    print("Query: is_active = TRUE AND is_deleted = FALSE")
    print()
    print("Logical operations:")
    print("  logical_true(field)  - Filter where field is TRUE")
    print("  logical_false(field) - Filter where field is FALSE")
    print()
    print("DBF logical field values:")
    print("  'T', 'Y', '1' → TRUE")
    print("  'F', 'N', '0' → FALSE")
    
    # Conceptual query structure (would work with logical fields)
    # query = DBFQuery("data.DBF")
    # 
    # group = FilterGroup(GroupOp.AND)
    # group.add_filter(logical_true("is_active"))
    # group.add_filter(logical_false("is_deleted"))
    # query.add_group(group)
    # 
    # recnos = query.execute()


if __name__ == "__main__":
    example_simple_query()
    example_complex_query()
    example_date_query()
    example_bitflag_query()
    example_logical_query()
