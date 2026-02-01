# Heap Map Filtering Strategies: AND vs OR Operations

## Overview

When filtering records in a memory-packed heap map, the strategy differs significantly between AND and OR operations. This document explains both approaches and when to use each.

---

## Memory-Packed Heap Map Structure

```pascal
type
  THeapRecord = record
    RecNo: LongInt;        { 4 bytes - supports >64K records }
    Year: Word;            { 2 bytes }
    DateAdded: LongInt;    { 4 bytes - Julian Day Number }
    BoolFlags: Byte;       { 1 byte - bit-packed booleans }
    Flags: Byte;           { 1 byte - numeric flags }
    Reserved: array[0..3] of Byte;  { 4 bytes - padding to 16 bytes }
  end;
  { Total: 16 bytes - perfectly aligned for 8086 }
```

**Key Feature:** Fields can be accessed directly without unpacking the entire record.

---

## Strategy 1: AND Operations (Direct Compare)

### When to Use
- All filter conditions must be true (AND logic)
- Example: `Year=2005 AND Active=True AND Featured=True`

### Implementation

```pascal
procedure FilterWithAND(var HeapMap: THeapMap; 
                       var Filters: TFilterArray;
                       var Results: TResultSet);
var
  i: Word;
begin
  for i := 0 to HeapMap.RecordCount - 1 do
  begin
    { Direct memory access - no unpacking! }
    
    { Check year range }
    if (HeapMap.Records[i].Year < Filters.MinYear) or 
       (HeapMap.Records[i].Year > Filters.MaxYear) then
      Continue;  { Short-circuit: doesn't match, skip to next }
    
    { Check boolean flags }
    if (HeapMap.Records[i].BoolFlags and Filters.BoolMask) <> Filters.BoolValue then
      Continue;  { Short-circuit: doesn't match, skip to next }
    
    { Check numeric flags }
    if (HeapMap.Records[i].Flags and Filters.FlagMask) <> Filters.FlagValue then
      Continue;  { Short-circuit: doesn't match, skip to next }
    
    { All conditions passed - add to results }
    AddResult(Results, HeapMap.Records[i].RecNo);
  end;
end;
```

### Performance Characteristics

| Metric | Value |
|--------|-------|
| Passes through heap map | **1** |
| Memory overhead | **0 bytes** (no temp storage) |
| Short-circuit evaluation | ✅ Yes (stops at first failed condition) |
| Cache-friendly | ✅ Yes (sequential access) |
| Speed | **Fastest** |

### Example Query

```
Query: Year >= 2005 AND Year <= 2010 AND Active = True AND Featured = True

Pseudo-code:
  for each record in heap_map:
    if record.Year < 2005: continue
    if record.Year > 2010: continue
    if not (record.BoolFlags & ACTIVE): continue
    if not (record.Flags & FEATURED): continue
    add record.RecNo to results
```

**Result:** Single pass, minimal CPU cycles per record.

---

## Strategy 2: OR Operations (Bitmap Approach)

### When to Use
- Any filter condition can be true (OR logic)
- Example: `Year=2005 OR Year=2010 OR Year=2015`

### Why Direct Compare Doesn't Work

❌ **Problem with direct compare for OR:**
```pascal
{ This DOESN'T work for OR! }
for i := 0 to HeapMap.RecordCount - 1 do
begin
  if (HeapMap.Records[i].Year = 2005) or 
     (HeapMap.Records[i].Year = 2010) then
    AddResult(Results, HeapMap.Records[i].RecNo);
end;
```

**Issue:** You can't track which condition matched, and complex OR expressions become unwieldy.

### Correct Implementation: Bitmap Approach

```pascal
type
  TRecordBitmap = array[0..8191] of Byte;  { 8KB = 64K bits = 64K records }

procedure SetBit(var Bitmap: TRecordBitmap; RecNo: LongInt);
var
  ByteIdx, BitIdx: Word;
begin
  ByteIdx := RecNo div 8;
  BitIdx := RecNo mod 8;
  Bitmap[ByteIdx] := Bitmap[ByteIdx] or (1 shl BitIdx);
end;

function GetBit(var Bitmap: TRecordBitmap; RecNo: LongInt): Boolean;
var
  ByteIdx, BitIdx: Word;
begin
  ByteIdx := RecNo div 8;
  BitIdx := RecNo mod 8;
  Result := (Bitmap[ByteIdx] and (1 shl BitIdx)) <> 0;
end;

procedure FilterWithOR(var HeapMap: THeapMap;
                      var Filters: TFilterArray;
                      var Results: TResultSet);
var
  i, j: Word;
  Bitmap1, Bitmap2, ResultBitmap: TRecordBitmap;
  RecNo: LongInt;
begin
  { Initialize bitmaps }
  FillChar(Bitmap1, SizeOf(Bitmap1), 0);
  FillChar(Bitmap2, SizeOf(Bitmap2), 0);
  FillChar(ResultBitmap, SizeOf(ResultBitmap), 0);
  
  { Pass 1: Find records matching first condition (Year=2005) }
  for i := 0 to HeapMap.RecordCount - 1 do
  begin
    if HeapMap.Records[i].Year = 2005 then
      SetBit(Bitmap1, HeapMap.Records[i].RecNo);
  end;
  
  { Pass 2: Find records matching second condition (Year=2010) }
  for i := 0 to HeapMap.RecordCount - 1 do
  begin
    if HeapMap.Records[i].Year = 2010 then
      SetBit(Bitmap2, HeapMap.Records[i].RecNo);
  end;
  
  { OR the bitmaps together (fast bitwise operation) }
  for i := 0 to High(ResultBitmap) do
    ResultBitmap[i] := Bitmap1[i] or Bitmap2[i];
  
  { Extract RecNos from result bitmap }
  for RecNo := 1 to MaxRecNo do
  begin
    if GetBit(ResultBitmap, RecNo) then
      AddResult(Results, RecNo);
  end;
end;
```

### Performance Characteristics

| Metric | Value |
|--------|-------|
| Passes through heap map | **N** (one per OR condition) |
| Memory overhead | **8KB per bitmap** |
| Short-circuit evaluation | ❌ No (must check all conditions) |
| Cache-friendly | ✅ Yes (sequential access) |
| Speed | **~N× slower than AND** |

### Example Query

```
Query: Year = 2005 OR Year = 2010 OR Year = 2015

Pseudo-code:
  bitmap1 = empty
  bitmap2 = empty
  bitmap3 = empty
  
  // Pass 1
  for each record in heap_map:
    if record.Year == 2005:
      set_bit(bitmap1, record.RecNo)
  
  // Pass 2
  for each record in heap_map:
    if record.Year == 2010:
      set_bit(bitmap2, record.RecNo)
  
  // Pass 3
  for each record in heap_map:
    if record.Year == 2015:
      set_bit(bitmap3, record.RecNo)
  
  // OR the bitmaps
  result_bitmap = bitmap1 OR bitmap2 OR bitmap3
  
  // Extract results
  for each bit in result_bitmap:
    if bit is set:
      add RecNo to results
```

**Result:** Multiple passes, but still much faster than disk I/O.

---

## Strategy 3: Complex Expressions (AND + OR)

### Example Query
```
(Year=2005 AND Active=True) OR (Year=2010 AND Featured=True)
```

### Implementation Strategy

```pascal
procedure FilterComplex(var HeapMap: THeapMap; var Results: TResultSet);
var
  Bitmap1, Bitmap2, ResultBitmap: TRecordBitmap;
  i: Word;
begin
  FillChar(Bitmap1, SizeOf(Bitmap1), 0);
  FillChar(Bitmap2, SizeOf(Bitmap2), 0);
  
  { Condition 1: Year=2005 AND Active=True }
  for i := 0 to HeapMap.RecordCount - 1 do
  begin
    if (HeapMap.Records[i].Year = 2005) and
       ((HeapMap.Records[i].BoolFlags and BOOL_IS_ACTIVE) = BOOL_IS_ACTIVE) then
      SetBit(Bitmap1, HeapMap.Records[i].RecNo);
  end;
  
  { Condition 2: Year=2010 AND Featured=True }
  for i := 0 to HeapMap.RecordCount - 1 do
  begin
    if (HeapMap.Records[i].Year = 2010) and
       ((HeapMap.Records[i].Flags and FLAG_FEATURED) = FLAG_FEATURED) then
      SetBit(Bitmap2, HeapMap.Records[i].RecNo);
  end;
  
  { OR the bitmaps }
  for i := 0 to High(ResultBitmap) do
    ResultBitmap[i] := Bitmap1[i] or Bitmap2[i];
  
  { Extract results }
  ExtractBitmapResults(ResultBitmap, Results);
end;
```

**Key Insight:** Use AND logic within each pass, then OR the bitmaps together.

---

## Performance Comparison

### Test Case: 10,000 records, 2 conditions

| Strategy | Passes | Memory | Time (8088 @ 4.77 MHz) | vs. Disk I/O |
|----------|--------|--------|------------------------|--------------|
| AND (direct) | 1 | 0 KB | ~0.05 seconds | **100x faster** |
| OR (bitmap) | 2 | 8 KB | ~0.10 seconds | **50x faster** |
| Disk streaming | N/A | 1 KB | ~5 seconds | **1x (baseline)** |

### Memory Requirements

| Component | Size | Notes |
|-----------|------|-------|
| Heap map (10K × 16 bytes) | 160 KB | Main data structure |
| Bitmap (64K records) | 8 KB | 1 bit per record |
| Bitmap (multiple conditions) | 8 KB × N | One per OR condition |
| **Total (3 OR conditions)** | **184 KB** | Fits in 440 KB DOS memory |

---

## Optimization: Hybrid Approach

### Strategy: Use NDX Index First

For queries with both string and numeric filters:

```pascal
procedure HybridFilter(const DBFFile: string; 
                      StringFilter: string;
                      NumericFilters: TFilterArray);
var
  Candidates: array of LongInt;
  HeapMap: THeapMap;
begin
  { Phase 1: Use NDX to reduce candidate set }
  Candidates := NDXPrefixSearch(NDXFile, StringFilter);
  { Example: 1M records → 5K candidates }
  
  { Phase 2: Load only candidates into heap map }
  LoadPartialHeapMap(HeapMap, DBFFile, Candidates);
  { Only 5K × 16 bytes = 80 KB }
  
  { Phase 3: Apply numeric filters with AND or OR }
  if NumericFilters.UseOR then
    FilterWithOR(HeapMap, NumericFilters, Results)
  else
    FilterWithAND(HeapMap, NumericFilters, Results);
end;
```

**Benefits:**
- ✅ NDX reduces candidate set dramatically
- ✅ Smaller heap map = faster filtering
- ✅ Works with millions of records

---

## Decision Matrix

### When to Use Each Strategy

| Scenario | Strategy | Reason |
|----------|----------|--------|
| All conditions must match | **AND (direct)** | Fastest, no overhead |
| Any condition can match | **OR (bitmap)** | Must track matches |
| Complex (AND + OR) | **Bitmap** | Combine AND passes with OR |
| String filter available | **NDX first** | Reduce candidate set |
| Very large table (>100K) | **NDX + Bitmap** | Minimize heap map size |
| Simple range query | **AND (direct)** | Single pass optimal |

### Quick Reference

```
Query Type                          Strategy
─────────────────────────────────────────────────────────
Year >= 2000 AND Year <= 2010      → AND (direct)
Active = True AND Featured = True  → AND (direct)
Year = 2005 OR Year = 2010         → OR (bitmap)
Name LIKE "SMITH%" AND Year = 2005 → NDX + AND
(A AND B) OR (C AND D)             → Bitmap (2 passes)
```

---

## Implementation Guidelines

### 1. AND Operations

```pascal
✅ DO:
  - Use direct memory comparison
  - Short-circuit on first failed condition
  - Place most selective filters first
  - Use bitwise operations for flags

❌ DON'T:
  - Unpack entire record
  - Create temporary structures
  - Use multiple passes
```

### 2. OR Operations

```pascal
✅ DO:
  - Use bitmap approach
  - Allocate bitmaps on stack if possible
  - Reuse bitmaps across queries
  - Use bitwise OR for combining

❌ DON'T:
  - Try to use direct comparison
  - Build result arrays during passes
  - Allocate bitmaps on heap (fragmentation)
```

### 3. Memory Management

```pascal
{ Stack allocation (preferred) }
var
  Bitmap: TRecordBitmap;  { 8KB on stack }
begin
  FillChar(Bitmap, SizeOf(Bitmap), 0);
  { Use bitmap }
end;  { Automatically freed }

{ Heap allocation (avoid if possible) }
var
  Bitmap: ^TRecordBitmap;
begin
  New(Bitmap);
  { Use bitmap }
  Dispose(Bitmap);  { Must manually free }
end;
```

---

## Code Examples

### Example 1: Simple AND Query

```pascal
{ Query: Year >= 2000 AND Year <= 2010 AND Active = True }
procedure QueryExample1(var HeapMap: THeapMap; var Results: TResultSet);
var
  i: Word;
begin
  for i := 0 to HeapMap.RecordCount - 1 do
  begin
    { Check year range }
    if (HeapMap.Records[i].Year < 2000) or 
       (HeapMap.Records[i].Year > 2010) then
      Continue;
    
    { Check active flag }
    if (HeapMap.Records[i].BoolFlags and BOOL_IS_ACTIVE) = 0 then
      Continue;
    
    { Match! }
    AddResult(Results, HeapMap.Records[i].RecNo);
  end;
end;
```

### Example 2: Simple OR Query

```pascal
{ Query: Year = 2005 OR Year = 2010 }
procedure QueryExample2(var HeapMap: THeapMap; var Results: TResultSet);
var
  i: Word;
  Bitmap1, Bitmap2, ResultBitmap: TRecordBitmap;
begin
  { Initialize }
  FillChar(Bitmap1, SizeOf(Bitmap1), 0);
  FillChar(Bitmap2, SizeOf(Bitmap2), 0);
  
  { Pass 1: Year = 2005 }
  for i := 0 to HeapMap.RecordCount - 1 do
    if HeapMap.Records[i].Year = 2005 then
      SetBit(Bitmap1, HeapMap.Records[i].RecNo);
  
  { Pass 2: Year = 2010 }
  for i := 0 to HeapMap.RecordCount - 1 do
    if HeapMap.Records[i].Year = 2010 then
      SetBit(Bitmap2, HeapMap.Records[i].RecNo);
  
  { OR bitmaps }
  for i := 0 to High(ResultBitmap) do
    ResultBitmap[i] := Bitmap1[i] or Bitmap2[i];
  
  { Extract results }
  ExtractBitmapResults(ResultBitmap, Results);
end;
```

### Example 3: Complex Query

```pascal
{ Query: (Year=2005 AND Active=True) OR (Year=2010 AND Featured=True) }
procedure QueryExample3(var HeapMap: THeapMap; var Results: TResultSet);
var
  i: Word;
  Bitmap1, Bitmap2, ResultBitmap: TRecordBitmap;
begin
  FillChar(Bitmap1, SizeOf(Bitmap1), 0);
  FillChar(Bitmap2, SizeOf(Bitmap2), 0);
  
  { Condition 1: Year=2005 AND Active=True }
  for i := 0 to HeapMap.RecordCount - 1 do
  begin
    if (HeapMap.Records[i].Year = 2005) and
       ((HeapMap.Records[i].BoolFlags and BOOL_IS_ACTIVE) <> 0) then
      SetBit(Bitmap1, HeapMap.Records[i].RecNo);
  end;
  
  { Condition 2: Year=2010 AND Featured=True }
  for i := 0 to HeapMap.RecordCount - 1 do
  begin
    if (HeapMap.Records[i].Year = 2010) and
       ((HeapMap.Records[i].Flags and FLAG_FEATURED) <> 0) then
      SetBit(Bitmap2, HeapMap.Records[i].RecNo);
  end;
  
  { OR the results }
  for i := 0 to High(ResultBitmap) do
    ResultBitmap[i] := Bitmap1[i] or Bitmap2[i];
  
  ExtractBitmapResults(ResultBitmap, Results);
end;
```

---

## Testing and Validation

### Python Simulation

A Python simulation is available at `tests/test_memory_packing.py` that demonstrates:
- Memory-packed 16-byte records
- Direct memory comparison (AND)
- Bitmap approach (OR)
- Performance comparison

Run with:
```bash
python tests/test_memory_packing.py
```

### Expected Results

```
AND Query (1 pass):
  10,000 records in ~0.05 seconds

OR Query (2 passes):
  10,000 records in ~0.10 seconds

Memory Usage:
  Heap map: 160 KB (10K × 16 bytes)
  Bitmaps:  16 KB (2 × 8 KB)
  Total:    176 KB (fits in 440 KB DOS memory)
```

---

## Summary

### Key Takeaways

1. **AND operations** use direct memory comparison (1 pass, fastest)
2. **OR operations** require bitmap approach (N passes, still fast)
3. **Bitmaps** are memory-efficient (1 bit per record = 8KB for 64K records)
4. **Hybrid approach** (NDX + heap map) handles large tables
5. **All strategies** are much faster than disk I/O (50-100x speedup)

### Performance Hierarchy

```
Fastest  →  AND (direct compare)
            ↓
            OR (bitmap, 2 conditions)
            ↓
            OR (bitmap, N conditions)
            ↓
            Disk streaming (baseline)
Slowest
```

### Memory Hierarchy

```
Least    →  AND (0 KB overhead)
            ↓
            OR (8 KB per condition)
            ↓
            Heap map (16 bytes per record)
            ↓
            Python dict (310 bytes per record)
Most
```

---

## Strategy 4: Progressive Multi-Group Filtering

### Overview

When multiple filter groups are combined with AND logic (Group1 AND Group2 AND Group3...), we can optimize by using **progressive filtering** where each group narrows the candidate set for subsequent groups.

### Key Insight

Since groups are ANDed together, we can:
1. Convert all operations (index searches, numeric filters) to bitmaps
2. Process groups sequentially, using previous results to filter subsequent groups
3. Exit early if candidate set becomes empty

### Algorithm

```pascal
{ Initialize based on first group's mode }
if Groups[1].Mode = mmAny then
  Matches := EmptyBitmap  { OR mode: start empty, add matches }
else
  Matches := AllOnes      { AND mode: start full, remove non-matches }

For each Group (1 to N):
  if Group is first then
    { First group: process based on its mode }
    if Group.Mode = mmAny then
      { OR mode: scan ALL records for numeric filters }
      ProcessIndexSearches(Group, Matches, AllRecords)
      ProcessNumericFilters(Group, Matches, AllRecords)
    else
      { AND mode: filter down from all records }
      ProcessIndexSearches(Group, Matches, Matches)
      ProcessNumericFilters(Group, Matches, Matches)
  else
    { Subsequent groups: AND with previous results }
    if Group.Mode = mmAny then
      { OR mode: collect matches from candidates, then AND }
      PrevMatches := Matches
      Matches := EmptyBitmap
      ProcessIndexSearches(Group, Matches, PrevMatches)
      ProcessNumericFilters(Group, Matches, PrevMatches)
      Matches := Matches AND PrevMatches
    else
      { AND mode: filter existing matches }
      ProcessIndexSearches(Group, Matches, Matches)
      ProcessNumericFilters(Group, Matches, Matches)
  
  { Early exit if no matches remain }
  if IsEmpty(Matches) then
    Exit
```

**Key Points:**
1. **First group initialization**: OR starts empty, AND starts full
2. **First OR group**: Numeric filters must scan ALL records, not just index results
3. **Subsequent OR groups**: Scan only previous matches (candidates)
4. **Subsequent AND groups**: Filter existing matches directly

### Example: Multi-Group Query

```
Group 1 (mmAny - OR mode):
  Filters: LastName LIKE "SMITH%" OR LastName LIKE "JONES%" OR Year=2005 OR Year=2010

Group 2 (mmAll - AND mode):
  Filters: Active=True AND Featured=True

Group 3 (mmAny - OR mode):
  Filters: State="CA" OR State="NY"
```

**Execution:**

```
Initial: Matches = 10,000 records (all)

Group 1 Processing:
  Index: "SMITH%" → 500 records
  Index: "JONES%" → 300 records
  IndexBitmap = 500 OR 300 = 800 records
  
  Numeric: Year=2005 → scan 10,000 records → 2,000 matches
  Numeric: Year=2010 → scan 10,000 records → 1,800 matches
  NumericBitmap = 2,000 OR 1,800 = 3,500 records
  
  GroupBitmap1 = 800 OR 3,500 = 3,800 records (mmAny mode)
  Matches = 10,000 AND 3,800 = 3,800 records

Group 2 Processing (only 3,800 candidates now):
  Numeric: Active=True → scan 3,800 records → 2,000 matches
  Numeric: Featured=True → scan 3,800 records → 500 matches
  GroupBitmap2 = 2,000 AND 500 = 400 records (mmAll mode)
  Matches = 3,800 AND 400 = 400 records

Group 3 Processing (only 400 candidates now):
  Numeric: State="CA" → scan 400 records → 250 matches
  Numeric: State="NY" → scan 400 records → 100 matches
  GroupBitmap3 = 250 OR 100 = 350 records (mmAny mode)
  Matches = 400 AND 350 = 350 records

Final Result: 350 records
```

### Performance Benefits

| Optimization | Benefit |
|--------------|---------|
| **Index → Bitmap** | Disk I/O converted to memory operation |
| **Progressive filtering** | Group 2 scans 3,800 not 10,000 records |
| **Early exit** | Skip remaining groups if Matches = 0 |
| **Bitmap operations** | OR/AND on 8KB arrays is extremely fast |
| **Consistent approach** | Same strategy for index and numeric filters |

### Performance Comparison

**Without Progressive Filtering:**
```
Group 1: Scan 10,000 records
Group 2: Scan 10,000 records
Group 3: Scan 10,000 records
Total:   30,000 record evaluations
```

**With Progressive Filtering:**
```
Group 1: Scan 10,000 records → 3,800 matches
Group 2: Scan 3,800 records → 400 matches
Group 3: Scan 400 records → 350 matches
Total:   14,200 record evaluations (53% reduction)
```

### Memory Requirements

| Component | Size | Notes |
|-----------|------|-------|
| Matches bitmap | 8 KB | Current candidate set (persistent) |
| TempBitmap | 8 KB | Reused for all index and numeric operations |
| **Total** | **16 KB** | During processing |
| **Final** | **8 KB** | Only Matches remains after completion |

### Implementation Notes

1. **Bitmap initialization:**
   - `AllOnes`: All bits set (all records are candidates)
   - `EmptyBitmap`: All bits clear (no matches yet)

2. **Index searches:**
   - NDX returns array of RecNos
   - Convert to bitmap by setting corresponding bits
   - AND with Matches to filter by current candidates

3. **Numeric filters:**
   - Only scan records where bit is set in Matches
   - Skip records already eliminated by previous groups

4. **Group mode handling:**
   - `mmAny` (OR): Any filter in group can match
   - `mmAll` (AND): All filters in group must match

5. **Between-group logic:**
   - Always AND (groups must all match)
   - This is what enables progressive filtering

### When to Use This Strategy

| Scenario | Use Progressive Filtering? |
|----------|---------------------------|
| Single group | ❌ No benefit, use direct approach |
| Multiple groups with AND | ✅ Yes, significant benefit |
| First group very selective | ✅ Yes, huge benefit (99% reduction) |
| Groups have index searches | ✅ Yes, converts disk to memory ops |
| Many groups (3+) | ✅ Yes, compounds the benefit |

### Code Structure

```pascal
type
  TRecordBitmap = array[0..8191] of Byte;  { 8KB = 64K bits }

procedure ProcessIndexSearches(
  var Group: TDBMatchGroup;
  var Matches: TRecordBitmap;
  var TempBitmap: TRecordBitmap);
var
  i: Integer;
  RecNos: array of LongInt;
begin
  { Each index search returns 8KB bitmap, immediately apply to Matches }
  for i := 1 to Group.FilterCount do
  begin
    if Group.Filters[i].Kind = fkStartsWith then
    begin
      { Index search returns RecNos }
      RecNos := NDXPrefixSearch(Group.Filters[i].ValueStr);
      
      { Convert to bitmap }
      FillChar(TempBitmap, SizeOf(TempBitmap), 0);
      ConvertRecNosToBitmap(RecNos, TempBitmap);
      
      { Apply immediately to Matches based on group mode }
      if Group.Mode = mmAny then
        { OR: Add these matches }
        ORBitmaps(Matches, TempBitmap)
      else
        { AND: Remove non-matches }
        ANDBitmaps(Matches, TempBitmap);
    end;
  end;
end;

procedure ProcessNumericFilters(
  var Group: TDBMatchGroup;
  var Matches: TRecordBitmap;
  var TempBitmap: TRecordBitmap;
  var HeapMap: THeapMap);
var
  i, j, RecNo: LongInt;
  PassesFilter: Boolean;
  Filter: TDBFilterSpec;
begin
  if Group.Mode = mmAny then
  begin
    { OR mode: Process each filter incrementally like index searches }
    for i := 1 to Group.FilterCount do
    begin
      Filter := Group.Filters[i];
      if Filter.Kind <> fkStartsWith then
      begin
        { Scan only records in Matches, build bitmap for this filter }
        FillChar(TempBitmap, SizeOf(TempBitmap), 0);
        for RecNo := 0 to HeapMap.RecordCount - 1 do
        begin
          if GetBit(Matches, RecNo) then
          begin
            if EvaluateFilter(HeapMap.Records[RecNo], Filter) then
              SetBit(TempBitmap, RecNo);
          end;
        end;
        
        { OR this filter's results into Matches }
        ORBitmaps(Matches, TempBitmap);
      end;
    end;
  end
  else
  begin
    { AND mode: Build combo filter, scan Matches once }
    { Only look at Matches rows, flip bit off if combo filter fails }
    for RecNo := 0 to HeapMap.RecordCount - 1 do
    begin
      if GetBit(Matches, RecNo) then
      begin
        { Test ALL numeric filters at once }
        PassesFilter := True;
        j := 1;
        while (j <= Group.FilterCount) and PassesFilter do
        begin
          Filter := Group.Filters[j];
          if Filter.Kind <> fkStartsWith then
          begin
            if not EvaluateFilter(HeapMap.Records[RecNo], Filter) then
              PassesFilter := False;
          end;
          Inc(j);
        end;
        
        { If fails combo filter, clear the bit }
        if not PassesFilter then
          ClearBit(Matches, RecNo);
      end;
    end;
  end;
end;

procedure ProcessMultiGroupFilter(
  var Cursor: TDBMatchCursor;
  var HeapMap: THeapMap;
  var Results: TResultSet);
var
  Matches: TRecordBitmap;
  TempBitmap: TRecordBitmap;
  i: Integer;
  HasMatches: Boolean;
begin
  { Initialize: all records are candidates }
  FillChar(Matches, SizeOf(Matches), $FF);
  
  { Process each group }
  HasMatches := True;
  i := 1;
  while (i <= Cursor.GroupCount) and HasMatches do
  begin
    { Process index searches - modifies Matches directly }
    ProcessIndexSearches(Cursor.Groups[i], Matches, TempBitmap);
    
    { Process numeric filters - modifies Matches directly }
    ProcessNumericFilters(Cursor.Groups[i], Matches, TempBitmap, HeapMap);
    
    { Check if any matches remain }
    HasMatches := not IsEmptyBitmap(Matches);
    Inc(i);
  end;
  
  { Extract final results }
  if HasMatches then
    ExtractBitmapResults(Matches, Results);
end;
```

### Key Implementation Details

**Index Searches:**
- Each index search produces 8KB bitmap
- Immediately applied to `Matches` (OR or AND based on group mode)
- No intermediate storage needed

**Numeric Filters - OR Mode:**
- Process each filter incrementally (like index searches)
- Scan only records still in `Matches`
- Build bitmap for this filter
- OR into `Matches`

**Numeric Filters - AND Mode:**
- Build "combo filter" with all numeric conditions
- Single scan through `Matches` records
- Test all filters at once (short-circuit on first failure)
- Clear bit if combo filter fails
- Much more efficient than multiple passes

**Memory Usage:**
- `Matches`: 8KB (persistent across groups)
- `TempBitmap`: 8KB (temporary, reused for both index and numeric filters)
- **Total: 16KB** during processing, **8KB** when complete

---

## Filter Types

The filtering system supports multiple filter types to handle different query patterns:

### 1. Exact String Match (`fkExactStr`)
- **Purpose:** Case-insensitive exact match on string fields
- **Example:** `LastName = "SMITH"`
- **Implementation:** Direct string comparison after trimming and uppercasing
- **Performance:** O(1) per record

### 2. Exact Numeric Match (`fkExactNum`)
- **Purpose:** Exact integer match on numeric fields
- **Example:** `Year = 2005`
- **Implementation:** Direct integer comparison
- **Performance:** O(1) per record
- **Index Support:** Can use `FindNumberExact()` for NDX optimization

### 3. Range Numeric (`fkRangeNum`)
- **Purpose:** Tests if a **constant value** falls between **two fields** in the record
- **Example:** `2005 BETWEEN StartYear AND EndYear`
- **Use Case:** Finding records whose date/value ranges contain a specific point
- **Implementation:** Reads two fields (min/max), tests if value is between them
- **Performance:** O(1) per record

### 4. Starts With (`fkStartsWith`)
- **Purpose:** Prefix match for strings
- **Example:** `LastName LIKE "SMITH%"`
- **Implementation:** Substring comparison
- **Performance:** O(1) per record
- **Index Support:** Can use `FindCharacterBegins()` for NDX optimization (highly recommended)

### 5. Field Range (`fkFieldRange`) - **NEW**
- **Purpose:** Tests if a **field value** falls within a **specified range**
- **Example:** `Year >= 2005 AND Year <= 2010`
- **Example:** `Salary BETWEEN 50000 AND 100000`
- **Use Case:** Finding records where a field is within a numeric range
- **Implementation:** Single comparison: `(FieldValue >= MinValue) AND (FieldValue <= MaxValue)`
- **Performance:** O(1) per record
- **Index Support:** Can use `FindNumberRange()` or `FindDateRange()` for NDX optimization

### Comparison: fkRangeNum vs fkFieldRange

These are **opposite** operations:

| Filter Type | What's Fixed | What's Variable | Example |
|-------------|--------------|-----------------|---------|
| `fkRangeNum` | Search value (2005) | Record fields (StartYear, EndYear) | "Find records where 2005 is between their start/end years" |
| `fkFieldRange` | Range bounds (2005-2010) | Record field (Year) | "Find records where Year is between 2005 and 2010" |

### Field Range Benefits

**Without `fkFieldRange`** (current workaround):
```pascal
{ Need separate filter for each value - inefficient! }
DBMatchCursorAddGroup(Cursor, mmAny);
DBMatchCursorAddExactNum(Cursor, 1, YearFieldIdx, 2005);
DBMatchCursorAddExactNum(Cursor, 1, YearFieldIdx, 2006);
DBMatchCursorAddExactNum(Cursor, 1, YearFieldIdx, 2007);
{ ... 6 filters for 6 years, limited to 8 filters per group }
```

**With `fkFieldRange`** (proposed):
```pascal
{ Single filter handles entire range }
DBMatchCursorAddFieldRange(Cursor, 1, YearFieldIdx, 2005, 2010);
{ Can use NDX index: FindNumberRange('YEAR.NDX', 2005, 2010, ...) }
```

**Advantages:**
1. **Single filter** instead of N filters (saves filter slots)
2. **NDX range search** support (much faster than sequential scan)
3. **Natural API** matches SQL `BETWEEN` semantics
4. **More efficient** bitmap operations (one pass vs N passes)
5. **Unlimited range** (not constrained by 8 filters per group)

### Implementation Notes

**Data Structure Changes:**
```pascal
type
  TDBFilterKind = (fkExactStr, fkExactNum, fkRangeNum, fkStartsWith, fkFieldRange);
  
  TDBFilterSpec = record
    Kind: TDBFilterKind;
    FieldIdx: Integer;
    FieldIdxMin: Integer;      { For fkRangeNum }
    FieldIdxMax: Integer;      { For fkRangeNum }
    ValueStr: string[255];
    ValueNum: LongInt;
    ValueNumMin: LongInt;      { For fkFieldRange - NEW }
    ValueNumMax: LongInt;      { For fkFieldRange - NEW }
    IndexFileName: string[255];
  end;
```

**API:**
```pascal
procedure DBMatchCursorAddFieldRange(var Cursor: TDBMatchCursor; 
  GroupIndex: Integer; FieldIdx: Integer; MinValue, MaxValue: LongInt);
```

**Index Search Integration:**
```pascal
{ In ProcessIndexSearchesForGroup }
if (Filter.Kind = fkFieldRange) and (Filter.IndexFileName <> '') then
begin
  Success := FindNumberRange(Filter.IndexFileName, 
    Filter.ValueNumMin, Filter.ValueNumMax, RowIds, DBFMaxRowIds, Count);
  { Convert to bitmap and apply to Matches }
end;
```

**Numeric Filter Evaluation:**
```pascal
fkFieldRange:
begin
  FieldValue := TrimString(Accessor.GetField(Accessor.Context, Buf, Filter.FieldIdx));
  NumValue := ParseInt(FieldValue);
  EvaluateFilterMatch := (NumValue >= Filter.ValueNumMin) and 
                         (NumValue <= Filter.ValueNumMax);
end;
```

---

## Conclusion

The choice between AND and OR filtering strategies is fundamental:

- **AND operations** benefit from direct memory comparison and short-circuit evaluation
- **OR operations** require tracking matches across conditions, making bitmaps the optimal solution
- **Multi-group filtering** uses progressive filtering to narrow candidates between groups
- **Bitmap approach** unifies index searches and numeric filters into a consistent strategy
- **All strategies** maintain the 50-100x performance advantage over disk I/O
- **Memory efficiency** remains excellent even with multiple bitmaps (8KB each)

The memory-packed heap map approach combined with progressive multi-group filtering is viable for DOS applications, providing dramatic performance improvements while staying within the 440KB memory constraint.
