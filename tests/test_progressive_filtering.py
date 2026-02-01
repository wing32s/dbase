"""
Test Progressive Multi-Group Filtering Algorithm

This test validates the bitmap-based progressive filtering strategy
described in FILTERING_STRATEGIES.md Strategy 4.

Key concepts:
1. Groups are ANDed together (Group1 AND Group2 AND Group3...)
2. Within each group, filters use OR or AND based on group mode
3. Each group narrows the candidate set for subsequent groups
4. Index searches and numeric filters both produce bitmaps
5. Early exit if candidate set becomes empty
"""

import random
from typing import List, Set, Callable
from enum import Enum


class FilterKind(Enum):
    """Types of filters"""
    EXACT_STR = 1
    EXACT_NUM = 2
    RANGE_NUM = 3
    STARTS_WITH = 4
    FIELD_RANGE = 5  # NEW: Test if field value is within a range


class MatchMode(Enum):
    """How filters combine within a group"""
    ANY = 1  # OR - any filter can match
    ALL = 2  # AND - all filters must match


class FilterSpec:
    """A single filter specification"""
    def __init__(self, kind: FilterKind, field: str, value=None, min_val=None, max_val=None):
        self.kind = kind
        self.field = field
        self.value = value
        self.min_val = min_val
        self.max_val = max_val


class MatchGroup:
    """A group of filters with a match mode"""
    def __init__(self, mode: MatchMode):
        self.mode = mode
        self.filters: List[FilterSpec] = []
    
    def add_filter(self, filter_spec: FilterSpec):
        self.filters.append(filter_spec)


class Record:
    """A database record"""
    def __init__(self, rec_no: int, **fields):
        self.rec_no = rec_no
        self.fields = fields
    
    def get_field(self, field_name: str):
        return self.fields.get(field_name, "")


class Bitmap:
    """8KB bitmap for 64K records (1 bit per record)"""
    def __init__(self, size: int = 65536):
        self.size = size
        # Use a set for simplicity in Python (in Pascal this would be 8KB byte array)
        self.bits: Set[int] = set()
    
    def set_bit(self, rec_no: int):
        """Set a bit (mark record as matching)"""
        if 0 <= rec_no < self.size:
            self.bits.add(rec_no)
    
    def clear_bit(self, rec_no: int):
        """Clear a bit (mark record as not matching)"""
        self.bits.discard(rec_no)
    
    def get_bit(self, rec_no: int) -> bool:
        """Test if a bit is set"""
        return rec_no in self.bits
    
    def set_all(self):
        """Set all bits (all records are candidates)"""
        self.bits = set(range(self.size))
    
    def clear_all(self):
        """Clear all bits (no matches)"""
        self.bits.clear()
    
    def is_empty(self) -> bool:
        """Check if bitmap has no matches"""
        return len(self.bits) == 0
    
    def count(self) -> int:
        """Count number of set bits"""
        return len(self.bits)
    
    def or_with(self, other: 'Bitmap'):
        """OR this bitmap with another (add matches)"""
        self.bits |= other.bits
    
    def and_with(self, other: 'Bitmap'):
        """AND this bitmap with another (keep only common matches)"""
        self.bits &= other.bits
    
    def copy(self) -> 'Bitmap':
        """Create a copy of this bitmap"""
        new_bitmap = Bitmap(self.size)
        new_bitmap.bits = self.bits.copy()
        return new_bitmap


def evaluate_filter(record: Record, filter_spec: FilterSpec) -> bool:
    """Evaluate a single filter against a record"""
    field_value = record.get_field(filter_spec.field)
    
    if filter_spec.kind == FilterKind.EXACT_STR:
        return str(field_value).upper() == str(filter_spec.value).upper()
    
    elif filter_spec.kind == FilterKind.EXACT_NUM:
        try:
            return int(field_value) == int(filter_spec.value)
        except (ValueError, TypeError):
            return False
    
    elif filter_spec.kind == FilterKind.RANGE_NUM:
        # Tests if VALUE falls between two FIELDS in the record
        # Example: Does 2005 fall between record's StartYear and EndYear?
        try:
            val = int(field_value)
            return filter_spec.min_val <= val <= filter_spec.max_val
        except (ValueError, TypeError):
            return False
    
    elif filter_spec.kind == FilterKind.FIELD_RANGE:
        # Tests if FIELD value falls within a specified RANGE
        # Example: Is record's Year between 2005 and 2010?
        try:
            val = int(field_value)
            return filter_spec.min_val <= val <= filter_spec.max_val
        except (ValueError, TypeError):
            return False
    
    elif filter_spec.kind == FilterKind.STARTS_WITH:
        return str(field_value).upper().startswith(str(filter_spec.value).upper())
    
    return False


def simulate_index_search(records: List[Record], prefix: str, field: str) -> List[int]:
    """Simulate an NDX index search for STARTS_WITH (returns list of RecNos)"""
    results = []
    prefix_upper = prefix.upper()
    for record in records:
        field_value = str(record.get_field(field)).upper()
        if field_value.startswith(prefix_upper):
            results.append(record.rec_no)
    return results


def simulate_index_range_search(records: List[Record], min_val: int, max_val: int, field: str) -> List[int]:
    """Simulate an NDX index range search for FIELD_RANGE (returns list of RecNos)"""
    results = []
    for record in records:
        try:
            field_value = int(record.get_field(field))
            if min_val <= field_value <= max_val:
                results.append(record.rec_no)
        except (ValueError, TypeError):
            pass
    return results


def process_index_searches(group: MatchGroup, matches: Bitmap, temp_bitmap: Bitmap,
                          records: List[Record], index_field: str, candidates: Bitmap = None):
    """Process all index searches in a group (STARTS_WITH and FIELD_RANGE with index)
    
    Args:
        candidates: If provided (for OR groups after first), only consider records in this bitmap
    """
    for filter_spec in group.filters:
        rec_nos = None
        
        if filter_spec.kind == FilterKind.STARTS_WITH:
            # Simulate NDX index search for prefix
            rec_nos = simulate_index_search(records, filter_spec.value, filter_spec.field)
        
        elif filter_spec.kind == FilterKind.FIELD_RANGE:
            # Simulate NDX index range search
            rec_nos = simulate_index_range_search(records, filter_spec.min_val, 
                                                 filter_spec.max_val, filter_spec.field)
        
        if rec_nos is not None:
            # Convert to bitmap
            temp_bitmap.clear_all()
            for rec_no in rec_nos:
                # If candidates provided, only include if in candidates
                if candidates is None or candidates.get_bit(rec_no):
                    temp_bitmap.set_bit(rec_no)
            
            # Apply to matches based on group mode
            if group.mode == MatchMode.ANY:
                # OR: Add these matches
                matches.or_with(temp_bitmap)
            else:
                # AND: Remove non-matches
                matches.and_with(temp_bitmap)


def process_numeric_filters(group: MatchGroup, matches: Bitmap, temp_bitmap: Bitmap,
                           records: List[Record], candidates: Bitmap = None):
    """Process all numeric filters in a group
    
    Args:
        candidates: If provided (for OR groups after first), scan these records instead of matches
    """
    # Determine which records to scan
    scan_set = candidates.bits if candidates is not None else matches.bits
    
    if group.mode == MatchMode.ANY:
        # OR mode: Process each filter incrementally
        for filter_spec in group.filters:
            # Skip index searches (already processed) and field ranges (processed as index)
            if filter_spec.kind not in (FilterKind.STARTS_WITH, FilterKind.FIELD_RANGE):
                # Scan only records in scan_set, build bitmap for this filter
                temp_bitmap.clear_all()
                for rec_no in list(scan_set):  # Only scan candidates
                    if rec_no < len(records):
                        record = records[rec_no]
                        if evaluate_filter(record, filter_spec):
                            temp_bitmap.set_bit(rec_no)
                
                # OR this filter's results into Matches
                matches.or_with(temp_bitmap)
    else:
        # AND mode: Build combo filter, scan Matches once
        # Only look at Matches rows, flip bit off if combo filter fails
        for rec_no in list(matches.bits):  # Iterate over copy
            if rec_no < len(records):
                record = records[rec_no]
                
                # Test ALL numeric filters at once
                passes_filter = True
                for filter_spec in group.filters:
                    # Skip index searches (already processed) and field ranges (processed as index)
                    if filter_spec.kind not in (FilterKind.STARTS_WITH, FilterKind.FIELD_RANGE):
                        if not evaluate_filter(record, filter_spec):
                            passes_filter = False
                            break  # Short-circuit
                
                # If fails combo filter, clear the bit
                if not passes_filter:
                    matches.clear_bit(rec_no)


def process_multi_group_filter(groups: List[MatchGroup], records: List[Record],
                              index_field: str = "LastName") -> Bitmap:
    """
    Process multiple filter groups with progressive filtering
    
    Returns: Bitmap with final matching RecNos
    """
    # Initialize based on first group's mode
    matches = Bitmap(len(records))
    if len(groups) > 0:
        if groups[0].mode == MatchMode.ANY:
            # OR mode: Start with empty (we're adding matches)
            matches.clear_all()
        else:
            # AND mode: Start with all (we're removing non-matches)
            matches.set_all()
    else:
        matches.set_all()
    
    # Temporary bitmap for intermediate results
    temp_bitmap = Bitmap(len(records))
    
    # Process each group
    for i, group in enumerate(groups):
        print(f"\n--- Processing Group {i+1} (mode={group.mode.name}) ---")
        print(f"Candidates before: {matches.count()}")
        
        if i == 0:
            # First group: process normally based on its mode
            if group.mode == MatchMode.ANY:
                # OR mode: Need to scan ALL records for numeric filters
                # Create a full candidate set
                full_set = Bitmap(len(records))
                full_set.set_all()
                process_index_searches(group, matches, temp_bitmap, records, index_field)
                process_numeric_filters(group, matches, temp_bitmap, records, full_set)
            else:
                # AND mode: Start with all, filter down
                process_index_searches(group, matches, temp_bitmap, records, index_field)
                process_numeric_filters(group, matches, temp_bitmap, records)
        else:
            # Subsequent groups: always AND with previous results
            # But the within-group logic depends on the group mode
            if group.mode == MatchMode.ANY:
                # OR mode: Collect matches from this group, then AND with previous
                # We need to check which records from 'matches' satisfy ANY filter in this group
                prev_matches = matches.copy()
                matches.clear_all()
                
                # Process filters - they will OR together, but only check prev_matches candidates
                process_index_searches(group, matches, temp_bitmap, records, index_field, prev_matches)
                process_numeric_filters(group, matches, temp_bitmap, records, prev_matches)
                
                # AND with previous groups' results (should already be subset, but be explicit)
                matches.and_with(prev_matches)
            else:
                # AND mode: Filter existing matches (remove records that don't match ALL filters)
                process_index_searches(group, matches, temp_bitmap, records, index_field)
                process_numeric_filters(group, matches, temp_bitmap, records)
        
        print(f"After group processing: {matches.count()}")
        
        # Early exit if no matches remain
        if matches.is_empty():
            print("No matches remain - early exit")
            break
    
    return matches


def date_to_jdn(year: int, month: int, day: int) -> int:
    """Convert Gregorian date to Julian Day Number (same algorithm as Pascal)"""
    a = (14 - month) // 12
    y = year + 4800 - a
    m = month + (12 * a) - 3
    return day + ((153 * m + 2) // 5) + (365 * y) + (y // 4) - (y // 100) + (y // 400) - 32045


def create_test_data(count: int = 10000) -> List[Record]:
    """Create test dataset with dates as JDN"""
    last_names = ["SMITH", "JONES", "JOHNSON", "WILLIAMS", "BROWN", "DAVIS", "MILLER", "WILSON"]
    states = ["CA", "NY", "TX", "FL", "IL", "PA", "OH", "GA"]
    
    # Pre-calculate some JDN values for testing
    jdn_2000_01_01 = date_to_jdn(2000, 1, 1)  # 2451545
    jdn_2015_12_31 = date_to_jdn(2015, 12, 31)  # 2457388
    jdn_2005_01_01 = date_to_jdn(2005, 1, 1)  # 2453371
    jdn_2010_12_31 = date_to_jdn(2010, 12, 31)  # 2455562
    jdn_2008_06_15 = date_to_jdn(2008, 6, 15)  # 2454632
    
    records = []
    for i in range(count):
        active = random.choice([True, False])
        featured = random.choice([True, False])
        record = Record(
            rec_no=i,
            LastName=random.choice(last_names),
            Year=random.randint(2000, 2015),
            DateAdded=random.randint(jdn_2000_01_01, jdn_2015_12_31),  # Random date as JDN
            DateSpecific=jdn_2008_06_15 if random.random() < 0.1 else random.randint(jdn_2000_01_01, jdn_2015_12_31),  # 10% have specific date
            Active="True" if active else "False",  # Store as string for consistency
            Featured="True" if featured else "False",  # Store as string for consistency
            State=random.choice(states)
        )
        records.append(record)
    
    return records


def test_progressive_filtering():
    """Test the progressive filtering algorithm"""
    print("=" * 70)
    print("Progressive Multi-Group Filtering Test")
    print("=" * 70)
    
    # Create test data
    print("\nCreating 10,000 test records...")
    records = create_test_data(10000)
    
    # Define filter groups
    print("\nDefining filter groups:")
    print("Group 1 (OR): LastName LIKE 'SMITH%' OR LastName LIKE 'JONES%' OR Year BETWEEN 2005 AND 2010")
    print("Group 2 (AND): Active=True AND Featured=True")
    print("Group 3 (OR): State='CA' OR State='NY'")
    print("Group 4 (AND): DateAdded BETWEEN 2005-01-01 AND 2010-12-31 (JDN range)")
    print("Group 5 (OR): DateSpecific = 2008-06-15 (JDN exact)")
    
    # JDN values for date filtering
    jdn_2005_01_01 = date_to_jdn(2005, 1, 1)  # 2453371
    jdn_2010_12_31 = date_to_jdn(2010, 12, 31)  # 2455562
    jdn_2008_06_15 = date_to_jdn(2008, 6, 15)  # 2454632
    
    # Group 1: OR mode - using FIELD_RANGE for Year
    group1 = MatchGroup(MatchMode.ANY)
    group1.add_filter(FilterSpec(FilterKind.STARTS_WITH, "LastName", "SMITH"))
    group1.add_filter(FilterSpec(FilterKind.STARTS_WITH, "LastName", "JONES"))
    group1.add_filter(FilterSpec(FilterKind.FIELD_RANGE, "Year", min_val=2005, max_val=2010))
    
    # Group 2: AND mode
    group2 = MatchGroup(MatchMode.ALL)
    group2.add_filter(FilterSpec(FilterKind.EXACT_STR, "Active", "True"))
    group2.add_filter(FilterSpec(FilterKind.EXACT_STR, "Featured", "True"))
    
    # Group 3: OR mode
    group3 = MatchGroup(MatchMode.ANY)
    group3.add_filter(FilterSpec(FilterKind.EXACT_STR, "State", "CA"))
    group3.add_filter(FilterSpec(FilterKind.EXACT_STR, "State", "NY"))
    
    # Group 4: AND mode - Date range using JDN (simulates numeric heap map)
    group4 = MatchGroup(MatchMode.ALL)
    group4.add_filter(FilterSpec(FilterKind.FIELD_RANGE, "DateAdded", min_val=jdn_2005_01_01, max_val=jdn_2010_12_31))
    
    # Group 5: OR mode - Exact date match using JDN
    group5 = MatchGroup(MatchMode.ANY)
    group5.add_filter(FilterSpec(FilterKind.EXACT_NUM, "DateSpecific", jdn_2008_06_15))
    
    groups = [group1, group2, group3, group4, group5]
    
    # Run progressive filtering
    print("\n" + "=" * 70)
    print("Running Progressive Filtering Algorithm")
    print("=" * 70)
    
    result_bitmap = process_multi_group_filter(groups, records)
    
    # Display results
    print("\n" + "=" * 70)
    print("Final Results")
    print("=" * 70)
    print(f"Total matching records: {result_bitmap.count()}")
    print(f"\nFirst 10 matching RecNos: {sorted(list(result_bitmap.bits))[:10]}")
    
    # Verify results by brute force
    print("\n" + "=" * 70)
    print("Verification (Brute Force)")
    print("=" * 70)
    
    brute_force_matches = []
    debug_count = 0
    for record in records:
        # Group 1: OR - using FIELD_RANGE
        year = record.get_field("Year")
        group1_match = (
            record.get_field("LastName").upper().startswith("SMITH") or
            record.get_field("LastName").upper().startswith("JONES") or
            (2005 <= year <= 2010)  # FIELD_RANGE: Year BETWEEN 2005 AND 2010
        )
        
        # Group 2: AND
        group2_match = (
            record.get_field("Active").upper() == "TRUE" and
            record.get_field("Featured").upper() == "TRUE"
        )
        
        # Group 3: OR
        group3_match = (
            record.get_field("State") == "CA" or
            record.get_field("State") == "NY"
        )
        
        # Group 4: AND - Date range using JDN
        date_added = record.get_field("DateAdded")
        group4_match = (jdn_2005_01_01 <= date_added <= jdn_2010_12_31)
        
        # Group 5: OR - Exact date match using JDN
        date_specific = record.get_field("DateSpecific")
        group5_match = (date_specific == jdn_2008_06_15)
        
        # All groups must match (AND between groups)
        if group1_match and group2_match and group3_match and group4_match and group5_match:
            brute_force_matches.append(record.rec_no)
            if debug_count < 3:
                print(f"  Match {debug_count+1}: RecNo={record.rec_no}, LastName={record.get_field('LastName')}, "
                      f"Year={record.get_field('Year')}, DateAdded={date_added} (JDN), "
                      f"DateSpecific={date_specific} (JDN), Active={record.get_field('Active')}, "
                      f"Featured={record.get_field('Featured')}, State={record.get_field('State')}")
                debug_count += 1
    
    print(f"Brute force matches: {len(brute_force_matches)}")
    print(f"Algorithm matches: {result_bitmap.count()}")
    
    # Compare results
    algorithm_set = result_bitmap.bits
    brute_force_set = set(brute_force_matches)
    
    if algorithm_set == brute_force_set:
        print("\n✓ SUCCESS: Algorithm matches brute force results!")
    else:
        print("\n✗ FAILURE: Results don't match!")
        missing = brute_force_set - algorithm_set
        extra = algorithm_set - brute_force_set
        print(f"Missing {len(missing)} records: {sorted(list(missing))[:10]}")
        print(f"Extra {len(extra)} records: {sorted(list(extra))[:10]}")
        
        # Debug: Check a missing record
        if missing:
            rec_no = list(missing)[0]
            rec = records[rec_no]
            print(f"\nDebug missing record {rec_no}:")
            print(f"  LastName={rec.get_field('LastName')}, Year={rec.get_field('Year')}")
            print(f"  Active={rec.get_field('Active')}, Featured={rec.get_field('Featured')}")
            print(f"  State={rec.get_field('State')}")
    
    # Performance comparison
    print("\n" + "=" * 70)
    print("Performance Analysis")
    print("=" * 70)
    print("Without progressive filtering:")
    print(f"  Group 1: Scan 10,000 records")
    print(f"  Group 2: Scan 10,000 records")
    print(f"  Group 3: Scan 10,000 records")
    print(f"  Total:   30,000 record evaluations")
    print("\nWith progressive filtering (actual):")
    print(f"  Group 1: Scan 10,000 records")
    print(f"  Group 2: Scan ~{result_bitmap.count() * 3} records (estimated)")
    print(f"  Group 3: Scan ~{result_bitmap.count()} records (estimated)")
    print(f"  Significant reduction in evaluations!")


if __name__ == "__main__":
    test_progressive_filtering()
