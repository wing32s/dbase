# Memory-Efficient NDX Index Building

## Current Memory Usage (Pascal)

For GAMES3.DBF (~7700 records):
- **Entries array**: 84 bytes × 7700 = ~647 KB
- **NodeInfos arrays**: Additional ~50-100 KB
- **Total heap needed**: ~350 KB

## Problem
The current implementation loads ALL entries into memory at once, which doesn't scale for large databases.

## Solution: External Sort with Chunking

### Algorithm Overview

```
1. CHUNK PHASE
   - Read DBF in chunks of N records (e.g., 1000)
   - Sort each chunk in memory
   - Write sorted chunk to temp file
   
2. MERGE PHASE
   - K-way merge of sorted temp files
   - Write merged output to final temp file
   
3. BUILD PHASE
   - Read merged data sequentially
   - Build B-tree leaf nodes on-the-fly
   - Build internal nodes bottom-up
```

### Memory Requirements

With chunk size = 1000:
- **Chunk buffer**: 84 bytes × 1000 = 84 KB
- **Merge buffers**: 84 bytes × K (number of chunks) × buffer_size
- **Node building**: 84 bytes × KeysMax (~12) = ~1 KB

**Total**: ~100 KB (vs 647 KB)

### Pascal Implementation Outline

```pascal
const
  ChunkSize = 1000;  { Adjust based on available memory }
  MergeBufferSize = 100;  { Records per merge buffer }

type
  TTempFileInfo = record
    FileName: string;
    Handle: File;
    Buffer: array[0..MergeBufferSize-1] of TNDXEntry;
    BufferPos: Integer;
    BufferLen: Integer;
    EOF: Boolean;
  end;

procedure BuildNDXMemoryEfficient(var Dbf: PDBFFile; FieldName: string);
var
  ChunkFiles: array of TTempFileInfo;
  ChunkCount: Integer;
  ChunkBuffer: array[0..ChunkSize-1] of TNDXEntry;
  ChunkLen: Integer;
  RowIndex, RowCount: LongInt;
  MergedFile: string;
begin
  { Phase 1: Create sorted chunks }
  ChunkCount := 0;
  RowCount := GetActualDBFRowCount(...);
  DBFFileSeekToFirstRow(Dbf);
  
  while RowIndex < RowCount do
  begin
    { Read chunk }
    ChunkLen := 0;
    while (ChunkLen < ChunkSize) and (RowIndex < RowCount) do
    begin
      DBFFileReadRow(Dbf, RowBuf);
      if RowBuf[0] <> Ord('*') then
      begin
        { Extract key and add to chunk }
        ChunkBuffer[ChunkLen].Key := ExtractKey(...);
        ChunkBuffer[ChunkLen].Recno := RowIndex + 1;
        Inc(ChunkLen);
      end;
      Inc(RowIndex);
    end;
    
    { Sort chunk in memory }
    QuickSortNDX(ChunkBuffer, 0, ChunkLen - 1, KeyLen);
    
    { Write chunk to temp file }
    WriteChunkToFile(ChunkBuffer, ChunkLen, ChunkCount);
    Inc(ChunkCount);
  end;
  
  { Phase 2: K-way merge }
  MergedFile := MergeChunks(ChunkFiles, ChunkCount);
  
  { Phase 3: Build B-tree from merged file }
  BuildBTreeFromSortedFile(MergedFile, NdxFileName);
  
  { Cleanup temp files }
  DeleteTempFiles(ChunkFiles, ChunkCount);
end;

function MergeChunks(var ChunkFiles: array of TTempFileInfo; 
                     ChunkCount: Integer): string;
var
  OutFile: File;
  MinEntry: TNDXEntry;
  MinIndex: Integer;
  I: Integer;
begin
  { Open all chunk files }
  for I := 0 to ChunkCount - 1 do
    OpenChunkFile(ChunkFiles[I]);
  
  { K-way merge }
  while not AllChunksEOF(ChunkFiles, ChunkCount) do
  begin
    { Find minimum entry across all chunks }
    MinIndex := FindMinEntry(ChunkFiles, ChunkCount, MinEntry);
    
    { Write to output }
    WriteEntry(OutFile, MinEntry);
    
    { Advance the chunk that had minimum }
    AdvanceChunk(ChunkFiles[MinIndex]);
  end;
  
  Result := 'merged.tmp';
end;

procedure BuildBTreeFromSortedFile(SortedFile, NdxFile: string);
var
  InFile: File;
  Entry: TNDXEntry;
  LeafBuffer: array[0..KeysMax-1] of TNDXEntry;
  LeafLen: Integer;
  LeafNodes: array of TNDXNodeInfo;
  Block: LongInt;
begin
  { Read sorted entries and build leaf nodes }
  Block := 1;
  LeafLen := 0;
  
  while not EOF(InFile) do
  begin
    ReadEntry(InFile, Entry);
    LeafBuffer[LeafLen] := Entry;
    Inc(LeafLen);
    
    if LeafLen = KeysMax then
    begin
      { Write full leaf node }
      WriteNDXNode(NdxFile, Block, LeafBuffer, LeafLen, ...);
      { Record node info for building parents }
      AddNodeInfo(LeafNodes, Block, LeafBuffer[LeafLen-1].Key);
      Inc(Block);
      LeafLen := 0;
    end;
  end;
  
  { Write partial leaf if any }
  if LeafLen > 0 then
  begin
    WriteNDXNode(NdxFile, Block, LeafBuffer, LeafLen, ...);
    AddNodeInfo(LeafNodes, Block, LeafBuffer[LeafLen-1].Key);
    Inc(Block);
  end;
  
  { Build internal nodes bottom-up }
  BuildInternalNodes(NdxFile, LeafNodes, Block);
end;
```

### Benefits

1. **Memory**: ~100 KB vs ~650 KB (6.5x reduction)
2. **Scalability**: Works with databases of any size
3. **Disk I/O**: More disk reads, but still efficient
4. **Simplicity**: Can reduce heap requirement to ~128 KB

### Trade-offs

- **More disk I/O**: Creates temporary files
- **Slightly slower**: Multiple passes over data
- **Complexity**: More code to maintain

### Recommendation

For your use case:
- If databases are typically < 10,000 records: **Keep current approach**
- If databases can be > 50,000 records: **Use external sort**
- Middle ground: **Hybrid approach** - use in-memory for small DBFs, external sort for large ones

### Quick Win: Reduce Memory Without External Sort

```pascal
{ Instead of allocating for RowCount, allocate for actual non-deleted count }
procedure BuildNDXSmarter(var Dbf: PDBFFile; FieldName: string);
var
  NonDeletedCount: LongInt;
begin
  { First pass: count non-deleted records }
  NonDeletedCount := CountNonDeletedRecords(Dbf);
  
  { Allocate only what's needed }
  GetMem(Entries, SizeOf(TNDXEntry) * NonDeletedCount);
  
  { Second pass: fill entries }
  ...
end;
```

This simple change can save 10-20% memory if you have deleted records.
