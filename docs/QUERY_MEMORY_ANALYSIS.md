# Query System Memory Analysis for Pascal Port

## Target Platform: 8088/8086 with 640KB RAM

### Memory Constraints

**Available Memory:**
- Total RAM: 640 KB
- DOS + TSRs: ~100 KB
- Program code: ~50-100 KB
- **Available for data: ~440-490 KB**

### Python Implementation Memory Usage

#### UnifiedHeapMap Structure

```python
heap_map = {
    recno: {
        'year': 1984,        # 4 bytes (int)
        'maxplay': 4,        # 4 bytes (int)
        'dateadd': 2459822,  # 4 bytes (int) - Julian Day Number
        'is_active': True,   # 1 byte (bool)
        'flags': 42          # 4 bytes (int)
    }
}
```

**Per Record:**
- Python dict overhead: ~240 bytes per record (!)
- 5 fields × 4 bytes average: 20 bytes
- Field name strings: ~50 bytes
- **Total: ~310 bytes per record**

**For 10,000 records:**
- 10,000 × 310 bytes = **3.1 MB**
- Plus reverse indices: **+1.5 MB**
- **Total: ~4.6 MB** ❌ Too large for DOS!

### Pascal Port Memory Requirements

#### Optimized Pascal Structures

```pascal
type
  TFieldValue = record
    case FieldType: Char of
      'N': (NumValue: LongInt);      { 4 bytes }
      'D': (DateValue: LongInt);     { 4 bytes - Julian Day Number }
      'L': (LogValue: Boolean);      { 1 byte }
  end;

  TRecordValues = record
    RecNo: Word;                      { 2 bytes }
    FieldCount: Byte;                 { 1 byte }
    Values: array[0..7] of TFieldValue; { 8 × 5 = 40 bytes max }
  end;
  { Total: 2 + 1 + 40 = 43 bytes per record }

  THeapMap = record
    RecordCount: Word;                { 2 bytes }
    FieldNames: array[0..7] of String[10]; { 8 × 11 = 88 bytes }
    Records: array[0..MaxRecords-1] of TRecordValues;
  end;
```

**Per Record (Pascal):**
- Record number: 2 bytes
- Field count: 1 byte
- 5 fields × 5 bytes average: 25 bytes
- **Total: ~28 bytes per record** ✅

**For 10,000 records:**
- 10,000 × 28 bytes = **280 KB**
- Field metadata: 88 bytes
- **Total: ~280 KB** ✅ Fits in DOS!

#### Date Storage: Julian Day Number (JDN)

**Why JDN instead of YYYYMMDD:**

| Feature | YYYYMMDD | JDN | Winner |
|---------|----------|-----|--------|
| Storage size | 4 bytes | 4 bytes | Tie |
| Date arithmetic | ❌ Complex | ✅ Simple | **JDN** |
| Range queries | ❌ Complex | ✅ Trivial | **JDN** |
| Invalid dates | ❌ Possible | ✅ Impossible | **JDN** |
| Comparison speed | ✅ Fast | ✅ Fast | Tie |
| Display format | ✅ Direct | ❌ Convert | YYYYMMDD |

**JDN Advantages:**
```pascal
{ Date arithmetic - trivial with JDN }
DaysApart := JDN2 - JDN1;           { Simple subtraction }
NextWeek := JDN + 7;                 { Simple addition }

{ Range query - "added in last 30 days" }
CurrentJDN := DateToJDN(2026, 1, 21);  { = 2460697 }
MinJDN := CurrentJDN - 30;              { = 2460667 }
if (RecordJDN >= MinJDN) and (RecordJDN <= CurrentJDN) then
  { Match! }

{ YYYYMMDD approach - complex! }
CurrentDate := 20260121;
{ How to subtract 30 days? Parse, calendar math, leap years, reformat... }
```

**JDN Range:**
- LongInt range: -2,147,483,648 to 2,147,483,647
- Date range: ~5,879,611 BC to ~5,879,611 AD
- Practical range: 1900-2099 uses JDN 2,415,021 to 2,488,433
- **More than sufficient for any database application**

**Conversion Functions:**
```pascal
function DateToJDN(Year, Month, Day: Integer): LongInt;
{ Standard Julian Day Number algorithm }

function JDNToDate(JDN: LongInt; var Year, Month, Day: Integer);
{ Reverse conversion for display }

function DBFDateToJDN(DateStr: string): LongInt;
{ Convert dBASE date string "19840315" to JDN = 2445780 }
```

**Memory Impact:**
- Same 4 bytes as YYYYMMDD format
- No additional storage overhead
- Simpler filtering logic = faster queries

#### Memory Alignment for Performance

**Why Alignment Matters on 8086:**
- 16-bit processor with optimal access on **even byte boundaries**
- Word (2-byte) access on odd addresses requires 2 memory cycles
- **Penalty: ~4 clock cycles** for misaligned access
- Arrays of aligned records enable efficient sequential scanning

**Recommended Record Sizes:**

Heap map records should be aligned to **16, 24, or 32 bytes** for optimal performance:

```pascal
{ 16-byte record (2-4 fields) }
type
  THeapRecord16 = record
    RecNo: Word;           { 2 bytes }
    Year: Word;            { 2 bytes }
    MaxPlay: Word;         { 2 bytes }
    DateAdd: LongInt;      { 4 bytes - JDN }
    IsActive: Boolean;     { 1 byte }
    Flags: Byte;           { 1 byte }
    Reserved: LongInt;     { 4 bytes - padding or future use }
  end;
  { Total: 16 bytes } ✅

{ 24-byte record (4-6 fields) }
type
  THeapRecord24 = record
    RecNo: Word;           { 2 bytes }
    Field1: LongInt;       { 4 bytes }
    Field2: LongInt;       { 4 bytes }
    Field3: LongInt;       { 4 bytes }
    Field4: Word;          { 2 bytes }
    Field5: Word;          { 2 bytes }
    Flags: Word;           { 2 bytes }
    Reserved: LongInt;     { 4 bytes - padding }
  end;
  { Total: 24 bytes } ✅

{ 32-byte record (6-8 fields) }
type
  THeapRecord32 = record
    RecNo: Word;           { 2 bytes }
    Field1: LongInt;       { 4 bytes }
    Field2: LongInt;       { 4 bytes }
    Field3: LongInt;       { 4 bytes }
    Field4: LongInt;       { 4 bytes }
    Field5: LongInt;       { 4 bytes }
    Field6: Word;          { 2 bytes }
    Field7: Word;          { 2 bytes }
    Flags: Word;           { 2 bytes }
    Reserved: Word;        { 2 bytes - padding }
  end;
  { Total: 32 bytes } ✅
```

**Capacity with Aligned Records:**

| Record Size | Records per 280KB | Records per 420KB | Notes |
|-------------|-------------------|-------------------|-------|
| 16 bytes | **17,500** | **26,250** | Best for simple schemas |
| 24 bytes | **11,666** | **17,500** | Good balance |
| 32 bytes | **8,750** | **13,125** | Maximum fields |

**Alignment Guidelines:**

1. ✅ **Choose 16, 24, or 32 byte records** based on field count
2. ✅ **Use explicit padding** to reach target size (Reserved fields)
3. ✅ **Pack boolean flags** into a single Word (up to 16 flags)
4. ✅ **Place largest fields first** (LongInt before Word before Byte)
5. ✅ **Use Word for small integers** (0-65535) to save space
6. ❌ **Avoid odd-sized records** (17, 23, 28 bytes cause misalignment)

**Example: Packing Boolean Flags**
```pascal
const
  FLAG_IS_ACTIVE   = $0001;
  FLAG_IS_DELETED  = $0002;
  FLAG_IS_MODIFIED = $0004;
  FLAG_HAS_NOTES   = $0008;
  { ... up to 16 flags in one Word }

{ Check flag }
if (Record.Flags and FLAG_IS_ACTIVE) <> 0 then ...

{ Set flag }
Record.Flags := Record.Flags or FLAG_IS_ACTIVE;

{ Clear flag }
Record.Flags := Record.Flags and (not FLAG_IS_DELETED);
```

### Memory Savings: Python vs Pascal

| Component | Python | Pascal | Savings |
|-----------|--------|--------|---------|
| Per record overhead | 310 bytes | 28 bytes | **91%** |
| 10K records | 3.1 MB | 280 KB | **91%** |
| Reverse indices | 1.5 MB | N/A | **100%** |

### Pascal Implementation Strategy

#### Option 1: Full In-Memory (Small Datasets)

**Suitable for:**
- Records: < 15,000
- Fields: < 8
- Memory: < 420 KB

```pascal
{ Load entire heap map into memory }
procedure BuildHeapMap(var HeapMap: THeapMap; const DBFFile: string);
var
  RecNo: Word;
  FieldIdx: Byte;
begin
  { Scan DBF once, load all non-string fields }
  for RecNo := 1 to RecordCount do
  begin
    ReadRecord(DBFFile, RecNo, Record);
    for FieldIdx := 0 to FieldCount - 1 do
      HeapMap.Records[RecNo].Values[FieldIdx] := ExtractValue(Record, FieldIdx);
  end;
end;
```

**Memory usage:**
- 15,000 records × 28 bytes = **420 KB** ✅

#### Option 2: Streaming (Large Datasets)

**Suitable for:**
- Records: > 15,000
- Memory: Limited

```pascal
{ Stream through records, no heap map }
procedure StreamingQuery(const DBFFile: string; var Filters: TFilterArray);
var
  RecNo: Word;
  Match: Boolean;
begin
  for RecNo := 1 to RecordCount do
  begin
    SeekToRecord(DBFFile, RecNo);
    ReadRecord(DBFFile, Record);
    
    Match := EvaluateFilters(Record, Filters);
    if Match then
      AddToResults(RecNo);
  end;
end;
```

**Memory usage:**
- Current record: ~256 bytes
- Filter array: ~100 bytes
- Results: ~20 KB (for 10K results)
- **Total: ~21 KB** ✅

#### Option 3: Hybrid (Best of Both)

**Strategy:**
1. Use NDX indexes for string filters (most selective)
2. Build heap map only for non-string fields
3. Stream through candidate records

```pascal
procedure HybridQuery(const DBFFile: string; var Query: TQuery);
var
  Candidates: array of Word;
  HeapMap: THeapMap;
begin
  { Phase 1: NDX filter (most selective) }
  if Query.HasNDXFilter then
    Candidates := NDXPrefixSearch(Query.NDXFile, Query.Prefix)
  else
    Candidates := AllRecords;
  
  { Phase 2: Build heap map for candidates only }
  if Query.HasNonStringFilters and (Length(Candidates) < 5000) then
  begin
    BuildPartialHeapMap(HeapMap, DBFFile, Candidates);
    Results := FilterWithHeapMap(HeapMap, Query);
  end
  else
  begin
    { Too many candidates, stream instead }
    Results := StreamingFilter(DBFFile, Candidates, Query);
  end;
end;
```

**Memory usage:**
- Candidates: 10,000 × 2 bytes = **20 KB**
- Partial heap map: 5,000 × 28 bytes = **140 KB**
- **Total: ~160 KB** ✅

### Filter Group Memory

```pascal
type
  TFilter = record
    FieldIndex: Byte;        { 1 byte }
    Operation: TFilterOp;    { 1 byte }
    Value: LongInt;          { 4 bytes }
    Value2: LongInt;         { 4 bytes - for BETWEEN }
    NDXFile: String[80];     { 81 bytes }
  end;
  { Total: 91 bytes per filter }

  TFilterGroup = record
    Operator: TGroupOp;      { 1 byte - AND/OR }
    FilterCount: Byte;       { 1 byte }
    Filters: array[0..7] of TFilter; { 8 × 91 = 728 bytes }
  end;
  { Total: 730 bytes per group }

  TQuery = record
    DBFFile: String[80];     { 81 bytes }
    GroupCount: Byte;        { 1 byte }
    Groups: array[0..3] of TFilterGroup; { 4 × 730 = 2,920 bytes }
  end;
  { Total: ~3 KB per query }
```

**Memory usage:**
- Query structure: **3 KB** ✅
- 4 groups × 8 filters = 32 filters max
- Very reasonable for DOS!

### Reverse Index Memory (Optional)

For fast value lookups, we could add reverse indices:

```pascal
type
  TValueIndex = record
    Value: LongInt;          { 4 bytes }
    RecNos: array of Word;   { Dynamic - could be large! }
  end;
```

**Problem:** Reverse indices can be large!
- Unique values: ~1,000
- Avg records per value: 10
- 1,000 × (4 + 10 × 2) = **24 KB per field**
- 5 fields = **120 KB** ⚠️

**Solution:** Skip reverse indices, use linear scan through heap map
- Scanning 10,000 records × 28 bytes = 280 KB is fast enough
- Modern DOS systems can scan ~1 MB/sec
- 280 KB scan = **0.28 seconds** ✅

### Memory Budget Breakdown

**Conservative (440 KB available):**

| Component | Memory | Percentage |
|-----------|--------|------------|
| Program code | 80 KB | 18% |
| Query structure | 3 KB | 1% |
| Heap map (10K records) | 280 KB | 64% |
| Result set (2K results) | 4 KB | 1% |
| Stack + buffers | 20 KB | 5% |
| **Reserve** | **53 KB** | **12%** |
| **Total** | **440 KB** | **100%** |

**Aggressive (490 KB available):**

| Component | Memory | Percentage |
|-----------|--------|------------|
| Program code | 80 KB | 16% |
| Query structure | 3 KB | 1% |
| Heap map (15K records) | 420 KB | 86% |
| Result set (2K results) | 4 KB | 1% |
| Stack + buffers | 20 KB | 4% |
| **Reserve** | **13 KB** | **3%** |
| **Total** | **490 KB** | **100%** |

### Recommendations for Pascal Port

#### 1. Use Static Arrays (Not Dynamic)

```pascal
{ ✅ GOOD: Static array, known size }
const
  MaxRecords = 15000;
  MaxFields = 8;

type
  THeapMap = record
    Records: array[0..MaxRecords-1] of TRecordValues;
  end;

{ ❌ BAD: Dynamic array, heap fragmentation }
type
  THeapMap = record
    Records: array of TRecordValues;  { Avoid! }
  end;
```

#### 2. Skip Reverse Indices

```pascal
{ Use linear scan instead of reverse index }
function FindRecordsWithValue(var HeapMap: THeapMap; 
                              FieldIdx: Byte; 
                              Value: LongInt): TRecordArray;
var
  RecNo: Word;
begin
  SetLength(Result, 0);
  for RecNo := 0 to HeapMap.RecordCount - 1 do
    if HeapMap.Records[RecNo].Values[FieldIdx].NumValue = Value then
      AddToArray(Result, HeapMap.Records[RecNo].RecNo);
end;
```

**Performance:** 10,000 records × 5 comparisons = 50,000 ops = **0.05 seconds** on 8088

#### 3. Implement Streaming Fallback

```pascal
{ If heap map too large, fall back to streaming }
if RecordCount > MaxRecords then
  Result := StreamingQuery(DBFFile, Query)
else
  Result := HeapMapQuery(DBFFile, Query);
```

#### 4. Use Bit Packing for Flags

```pascal
type
  TFieldFlags = record
    IsNull: Boolean;         { 1 bit }
    FieldType: 0..3;         { 2 bits: 0=Num, 1=Date, 2=Logical }
    Reserved: 0..31;         { 5 bits }
  end;  { Total: 1 byte instead of 3 }
```

#### 5. Optimize String Storage

```pascal
{ ✅ GOOD: Fixed-length strings }
type
  TFieldName = String[10];   { 11 bytes }

{ ❌ BAD: Long strings }
type
  TFieldName = String;       { 256 bytes! }
```

### Performance Estimates (8088 @ 4.77 MHz)

**Heap Map Build:**
- Read 10,000 records: ~5 seconds (disk I/O)
- Parse + store: ~2 seconds (CPU)
- **Total: ~7 seconds** ✅

**Query Execution (with heap map):**
- Scan 10,000 records: ~0.05 seconds
- Filter evaluation: ~0.02 seconds
- **Total: ~0.07 seconds** ✅

**Query Execution (streaming, no heap map):**
- Read 10,000 records: ~5 seconds (disk I/O)
- Filter evaluation: ~0.5 seconds (CPU)
- **Total: ~5.5 seconds** ⚠️

**Conclusion:** Heap map is **78x faster** than streaming!

### Maximum Dataset Sizes

| Memory Available | Max Records | Max Fields | Heap Map Size |
|------------------|-------------|------------|---------------|
| 200 KB | 7,000 | 8 | 196 KB |
| 300 KB | 10,000 | 8 | 280 KB |
| 400 KB | 14,000 | 8 | 392 KB |
| 500 KB | 17,000 | 8 | 476 KB |

### Comparison: Python vs Pascal Implementation

| Feature | Python | Pascal | Notes |
|---------|--------|--------|-------|
| Memory per record | 310 bytes | 28 bytes | **91% savings** |
| Max records (440KB) | ~1,400 | ~15,000 | **10x more** |
| Reverse indices | Yes | No | Trade memory for speed |
| Dynamic allocation | Yes | No | Static arrays only |
| String overhead | High | Low | Fixed-length strings |
| Dict/hash overhead | ~240 bytes | 0 bytes | No hash tables |

### Final Recommendations

**For Pascal Port:**

1. ✅ **Use unified heap map** - 91% memory savings vs Python
2. ✅ **Static arrays** - Avoid heap fragmentation
3. ✅ **Skip reverse indices** - Linear scan is fast enough
4. ✅ **Implement streaming fallback** - For datasets > 15K records
5. ✅ **Use hybrid approach** - NDX first, then heap map
6. ✅ **Bit packing** - For flags and small enums
7. ✅ **Fixed-length strings** - 11 bytes vs 256 bytes

**Expected Performance:**
- Build heap map: 7 seconds (one-time cost)
- Query execution: 0.07 seconds (with heap map)
- Memory usage: 280 KB for 10K records
- Max dataset: 15,000 records in 440 KB RAM

**The query system is viable for Pascal/DOS!** 🎉
