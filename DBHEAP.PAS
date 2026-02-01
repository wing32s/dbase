{ DBHEAP.PAS - Memory-packed heap map builder for fast filtering }

unit DBHEAP;

interface

uses DBF;

const
  MaxHeapRecords = 4000;  { Maximum records in heap map (4000*16=64000 < 65535 limit) }
  MaxHeapFields = 16;     { Maximum fields per heap record }

type
  { Heap-allocated row ID array for results }
  PRowIdArray = ^TRowIdArray;
  TRowIdArray = array[0..0] of LongInt;  { Open array for pointer math }

  { Field type in heap map }
  THeapFieldType = (hftNone, hftWord, hftLongInt, hftBitFlags, hftNibble, hftByte);

  { Specification for one field in heap map }
  THeapFieldSpec = record
    DBFFieldIdx: Integer;      { Source field index in DBF (0 = RecNo) }
    HeapFieldType: THeapFieldType; { How to store in heap }
    HeapOffset: Byte;          { Offset in heap record (auto-calculated) }
    ConvertToJDN: Boolean;     { Auto-convert date string (YYYYMMDD) to JDN }
    BitMask: Byte;             { For hftBitFlags: which bit(s) to use ($01, $02, $04, etc.) }
    NibbleShift: Byte;         { For hftNibble: 0 (low nibble) or 4 (high nibble) }
  end;
  
  { Array of field specifications }
  THeapFieldSpecArray = array[1..MaxHeapFields] of THeapFieldSpec;
  
  { Pointer types for memory access }
  PByteArray = ^TByteArray;
  TByteArray = array[0..8191] of Byte;
  
  { Generic heap record - variable size based on TargetRecordSize }
  THeapRecord = record
    Data: array[0..31] of Byte;  { Max 32 bytes per record }
  end;
  
  { Heap map structure }
  THeapMap = record
    RecordCount: Word;          { Actual records stored }
    AllocatedRecords: Word;     { Records allocated (for FreeMem) }
    RecordSize: Byte;           { 16, 24, or 32 bytes }
    FieldCount: Byte;           { Number of fields }
    FieldSpecs: THeapFieldSpecArray;
    Records: ^THeapRecord;      { Pointer to dynamically allocated records }
  end;
  
  { Segmented heap map structures }
  THeapSegment = record
    StartRecNo: LongInt;        { First record in segment (1-based) }
    EndRecNo: LongInt;          { Last record in segment }
    ActualCount: Word;          { Actual records loaded (may be < MaxHeapRecords for last segment) }
    HeapMap: THeapMap;          { The 8K heap map }
  end;
  
  TSegmentedResults = record
    RecNos: PRowIdArray;        { Caller-allocated result buffer }
    MaxCount: Word;             { Allocated capacity }
    Count: Word;                { Actual matches }
  end;
  
  { Filter function type for segmented processing }
  THeapFilterFunc = function(var HeapMap: THeapMap; RecordIdx: Word): Boolean;

{ Calculate field offsets and validate total size }
function CalculateHeapLayout(var FieldSpecs: THeapFieldSpecArray; 
  FieldCount: Integer; TargetRecordSize: Byte): Boolean;

{ Build heap map from DBF based on field specifications }
function BuildHeapMap(var Dbf: PDBFFile; var FieldSpecs: THeapFieldSpecArray;
  FieldCount: Integer; TargetRecordSize: Byte; var HeapMap: THeapMap): Boolean;

{ Allocate memory for heap records }
function AllocateHeapRecords(var HeapMap: THeapMap; NumRecords: Word): Boolean;

{ Free memory allocated for heap records }
function FreeHeapRecords(var HeapMap: THeapMap): Boolean;

{ Extract numeric fields from filter cursor for heap map }
function ExtractNumericFieldsFromFilters(var Cursor: Pointer; 
  var FieldSpecs: THeapFieldSpecArray; var FieldCount: Integer): Boolean;

{ Helper: Read Word from heap record }
function HeapGetWord(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): Word;

{ Helper: Read LongInt from heap record }
function HeapGetLongInt(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): LongInt;

{ Helper: Read bit flag from heap record }
function HeapGetBitFlag(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): Boolean;

{ Helper: Read nibble from heap record }
function HeapGetNibble(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): Byte;

{ Helper: Read byte from heap record }
function HeapGetByte(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): Byte;

{ Segmented heap map functions }

{ Load one segment of records into heap map }
function LoadHeapSegment(var Dbf: PDBFFile; 
                         var FieldSpecs: THeapFieldSpecArray;
                         FieldCount: Integer; 
                         TargetRecordSize: Byte;
                         StartRecNo: LongInt;
                         var Segment: THeapSegment): Boolean;

{ Filter one segment and collect results }
function FilterSegment(var Segment: THeapSegment;
                       var Results: TSegmentedResults): Boolean;

{ Global filter function for TP 5.5 compatibility }
var
  CurrentFilterFuncVar: THeapFilterFunc;
  FilterFuncIsSet: Boolean;

{ Set global filter function (call this before QuerySegmented) }
function SetCurrentFilterFunc(Filter: THeapFilterFunc): Boolean;

{ Filter function that uses global function var }
function CurrentFilterFunc(var HeapMap: THeapMap; RecordIdx: Word): Boolean;


{ Process entire table in segments }
function QuerySegmented(var Dbf: PDBFFile;
                        var FieldSpecs: THeapFieldSpecArray;
                        FieldCount: Integer;
                        TargetRecordSize: Byte;
                        var Results: TSegmentedResults): Boolean;

{ Process in segments starting at StartRecNo (0-based); returns NextRecNo for paging }
function QuerySegmentedPaged(var Dbf: PDBFFile;
                             var FieldSpecs: THeapFieldSpecArray;
                             FieldCount: Integer;
                             TargetRecordSize: Byte;
                             StartRecNo: LongInt;
                             PageSize: Word;
                             var Results: TSegmentedResults;
                             var NextRecNo: LongInt): Boolean;

implementation

uses DBFUTIL;

{ Set global filter function (call this before QuerySegmented) }
function SetCurrentFilterFunc(Filter: THeapFilterFunc): Boolean;
begin
  CurrentFilterFuncVar := Filter;
  FilterFuncIsSet := True;
  SetCurrentFilterFunc := True;
end;

{ Filter function that uses global function var }
function CurrentFilterFunc(var HeapMap: THeapMap; RecordIdx: Word): Boolean;
begin
  if FilterFuncIsSet then
    CurrentFilterFunc := CurrentFilterFuncVar(HeapMap, RecordIdx)
  else
    CurrentFilterFunc := False;
end;


{ ============================================================================ }
{ Layout Calculation                                                           }
{ ============================================================================ }

function CalculateHeapLayout(var FieldSpecs: THeapFieldSpecArray; 
  FieldCount: Integer; TargetRecordSize: Byte): Boolean;
var
  I: Integer;
  CurrentOffset: Byte;
  FieldSize: Byte;
  LastBitFlagsOffset: Integer;
  LastNibbleOffset: Integer;
begin
  CalculateHeapLayout := False;
  CurrentOffset := 0;
  LastBitFlagsOffset := -1;  { Track last BitFlags byte offset }
  LastNibbleOffset := -1;    { Track last Nibble byte offset }
  
  { Calculate offset for each field, maintaining alignment }
  for I := 1 to FieldCount do
  begin
    case FieldSpecs[I].HeapFieldType of
      hftWord:
      begin
        { Word: 2 bytes, must be 2-byte aligned }
        if (CurrentOffset mod 2) <> 0 then
          Inc(CurrentOffset);  { Align to 2-byte boundary }
        FieldSpecs[I].HeapOffset := CurrentOffset;
        FieldSize := 2;
        LastBitFlagsOffset := -1;  { Reset BitFlags tracking }
        LastNibbleOffset := -1;    { Reset Nibble tracking }
      end;
      hftLongInt:
      begin
        { LongInt: 4 bytes, must be 4-byte aligned }
        while (CurrentOffset mod 4) <> 0 do
          Inc(CurrentOffset);  { Align to 4-byte boundary }
        FieldSpecs[I].HeapOffset := CurrentOffset;
        FieldSize := 4;
        LastBitFlagsOffset := -1;  { Reset BitFlags tracking }
        LastNibbleOffset := -1;    { Reset Nibble tracking }
      end;
      hftBitFlags:
      begin
        { BitFlags: 1 byte, can share with previous BitFlags }
        if LastBitFlagsOffset >= 0 then
        begin
          { Reuse the same byte as previous BitFlags }
          FieldSpecs[I].HeapOffset := LastBitFlagsOffset;
          FieldSize := 0;  { Don't advance offset }
        end
        else
        begin
          { New BitFlags byte }
          FieldSpecs[I].HeapOffset := CurrentOffset;
          FieldSize := 1;
          LastBitFlagsOffset := CurrentOffset;
        end;
        LastNibbleOffset := -1;  { Reset Nibble tracking }
      end;
      hftNibble:
      begin
        { Nibble: 4 bits, can share byte with another nibble }
        if LastNibbleOffset >= 0 then
        begin
          { Reuse same byte, use high nibble }
          FieldSpecs[I].HeapOffset := LastNibbleOffset;
          FieldSpecs[I].NibbleShift := 4;  { High nibble }
          FieldSize := 0;  { Don't advance offset }
          LastNibbleOffset := -1;  { Byte is now full }
        end
        else
        begin
          { New nibble byte, use low nibble }
          FieldSpecs[I].HeapOffset := CurrentOffset;
          FieldSpecs[I].NibbleShift := 0;  { Low nibble }
          FieldSize := 1;
          LastNibbleOffset := CurrentOffset;
        end;
        LastBitFlagsOffset := -1;  { Reset BitFlags tracking }
      end;
      hftByte:
      begin
        { Byte: 1 byte, no alignment required }
        FieldSpecs[I].HeapOffset := CurrentOffset;
        FieldSize := 1;
        LastBitFlagsOffset := -1;  { Reset BitFlags tracking }
        LastNibbleOffset := -1;    { Reset Nibble tracking }
      end;
      else
      begin
        { Unknown type }
        Exit;
      end;
    end;
    
    Inc(CurrentOffset, FieldSize);
    
    { Check if we exceeded target size }
    if CurrentOffset > TargetRecordSize then
      Exit;
  end;
  
  { Pad to next multiple of 8 bytes }
  if (CurrentOffset mod 8) <> 0 then
    CurrentOffset := ((CurrentOffset div 8) + 1) * 8;
  
  { Check if padded size exceeds target }
  if CurrentOffset > TargetRecordSize then
    Exit;
  
  { Success: all fields fit within target size (with padding) }
  CalculateHeapLayout := True;
end;

{ ============================================================================ }
{ Heap Memory Management                                                        }
{ ============================================================================ }

function AllocateHeapRecords(var HeapMap: THeapMap; NumRecords: Word): Boolean;
var
  MemSize: LongInt;
  MemSizeWord: Word;
begin
  AllocateHeapRecords := False;

  { Free any existing allocation }
  if HeapMap.Records <> nil then
    if not FreeHeapRecords(HeapMap) then ;

  { Calculate memory needed }
  MemSize := LongInt(NumRecords) * LongInt(HeapMap.RecordSize);

  { TP 5.5 GetMem only accepts Word-sized allocations (max 65535 bytes) }
  { If we exceed this, the allocation would silently fail/corrupt memory }
  if MemSize > 65535 then
    Exit;

  MemSizeWord := Word(MemSize);

  { Allocate memory using GetMem }
  GetMem(HeapMap.Records, MemSizeWord);
  if HeapMap.Records = nil then
    Exit;

  { Track allocated size for FreeMem }
  HeapMap.AllocatedRecords := NumRecords;

  { Initialize memory to zero }
  FillChar(HeapMap.Records^, MemSizeWord, 0);

  AllocateHeapRecords := True;
end;

function FreeHeapRecords(var HeapMap: THeapMap): Boolean;
var
  MemSize: Word;
begin
  FreeHeapRecords := True;
  if HeapMap.Records <> nil then
  begin
    { AllocateHeapRecords guarantees MemSize <= 65535 }
    MemSize := HeapMap.AllocatedRecords * HeapMap.RecordSize;
    FreeMem(HeapMap.Records, MemSize);
    HeapMap.Records := nil;
    HeapMap.AllocatedRecords := 0;
  end;
end;

{ ============================================================================ }
{ Heap Map Builder                                                             }
{ ============================================================================ }

function BuildHeapMap(var Dbf: PDBFFile; var FieldSpecs: THeapFieldSpecArray;
  FieldCount: Integer; TargetRecordSize: Byte; var HeapMap: THeapMap): Boolean;
var
  I, J: Integer;
  RecNo: LongInt;
  RowPtr: Pointer;
  Header: TDBFHeader;
  FieldValue: string;
  NumValue: LongInt;
  WordValue: Word;
  PData: ^Byte;
  Success: Boolean;
  FieldSpec: THeapFieldSpec;
begin
  BuildHeapMap := False;
  { Get header for record size }
  if not DBFFileGetHeader(Dbf, Header) then
    Exit;

  { Allocate row buffer on heap }
  GetMem(RowPtr, Header.RecordSize);
  if RowPtr = nil then
    Exit;
  { Initialize heap map }
  FillChar(HeapMap, SizeOf(HeapMap), 0);
  HeapMap.RecordSize := TargetRecordSize;
  HeapMap.FieldCount := FieldCount;
  HeapMap.Records := nil;  { Initialize pointer to nil }
  
  { Copy field specs }
  for I := 1 to FieldCount do
    HeapMap.FieldSpecs[I] := FieldSpecs[I];
  
  { Calculate layout }
  if not CalculateHeapLayout(HeapMap.FieldSpecs, FieldCount, TargetRecordSize) then
  begin
    HeapMap.RecordCount := 0;
    FreeMem(RowPtr, Header.RecordSize);
    Exit;
  end;

  { Allocate memory for maximum records }
  if not AllocateHeapRecords(HeapMap, MaxHeapRecords) then
  begin
    HeapMap.RecordCount := 0;
    FreeMem(RowPtr, Header.RecordSize);
    Exit;
  end;
  
  { Load records from DBF }
  HeapMap.RecordCount := 0;
  RecNo := 0;
  
  Success := True;
  while Success and (RecNo < DBFFileGetActualRowCount(Dbf)) and
        (HeapMap.RecordCount < MaxHeapRecords) do
  begin
    if not DBFFileSeekToRow(Dbf, RecNo) then
      Success := False
    else if not DBFFileReadRow(Dbf, RowPtr, Header.RecordSize) then
      Success := False;
    if Success then
    begin
      { Process each field }
      for I := 1 to FieldCount do
      begin
        FieldSpec := HeapMap.FieldSpecs[I];
        PData := @PByteArray(HeapMap.Records)^[HeapMap.RecordCount * HeapMap.RecordSize + FieldSpec.HeapOffset];

        if FieldSpec.DBFFieldIdx = 0 then
        begin
          { Special case: RecNo field }
          case FieldSpec.HeapFieldType of
            hftWord:
            begin
              WordValue := RecNo;
              Move(WordValue, PData^, 2);
            end;
            hftLongInt:
            begin
              NumValue := RecNo;
              Move(NumValue, PData^, 4);
            end;
          end;
        end
        else
        begin
          { Regular field: read from buffer }
          FieldValue := DBFFieldGetStr(RowPtr, Header, FieldSpec.DBFFieldIdx);
          
          { Trim whitespace }
          while (Length(FieldValue) > 0) and (FieldValue[1] = ' ') do
            Delete(FieldValue, 1, 1);
          while (Length(FieldValue) > 0) and (FieldValue[Length(FieldValue)] = ' ') do
            Delete(FieldValue, Length(FieldValue), 1);
          
          { Convert date to JDN if requested }
          if FieldSpec.ConvertToJDN then
          begin
            NumValue := DBFDateStrToJDN(FieldValue);
          end
          else
          begin
            { Parse as integer }
            NumValue := 0;
            for J := 1 to Length(FieldValue) do
            begin
              if (FieldValue[J] >= '0') and (FieldValue[J] <= '9') then
                NumValue := NumValue * 10 + (Ord(FieldValue[J]) - Ord('0'))
              else if FieldValue[J] = '-' then
                { Negative number - not handled yet }
              else
                J := Length(FieldValue);  { Exit loop early }
            end;
          end;
          
          { Store based on type }
          case FieldSpec.HeapFieldType of
            hftWord:
            begin
              WordValue := NumValue;
              Move(WordValue, PData^, 2);
            end;
            hftLongInt:
            begin
              Move(NumValue, PData^, 4);
            end;
            hftBitFlags:
            begin
              { Convert to boolean and OR into byte }
              { dBASE logical: 'T', 't', 'Y', 'y' = True }
              if (Length(FieldValue) > 0) and 
                 ((FieldValue[1] = 'T') or (FieldValue[1] = 't') or 
                  (FieldValue[1] = 'Y') or (FieldValue[1] = 'y')) then
              begin
                PData^ := PData^ or FieldSpec.BitMask;
              end;
            end;
            hftNibble:
            begin
              { Pack as nibble (4 bits, value 0-15) }
              { Clamp to 0-15 range }
              if NumValue < 0 then
                NumValue := 0
              else if NumValue > 15 then
                NumValue := 15;
              
              if FieldSpec.NibbleShift = 0 then
              begin
                { Low nibble: clear bits 0-3, set value }
                PData^ := (PData^ and $F0) or (NumValue and $0F);
              end
              else
              begin
                { High nibble: clear bits 4-7, set value }
                PData^ := (PData^ and $0F) or ((NumValue and $0F) shl 4);
              end;
            end;
            hftByte:
            begin
              { Pack as byte (8 bits, value 0-255) }
              { Clamp to 0-255 range }
              if NumValue < 0 then
                NumValue := 0
              else if NumValue > 255 then
                NumValue := 255;
              PData^ := NumValue and $FF;
            end;
          end;
        end;
      end;
      
      Inc(HeapMap.RecordCount);
    end;

    Inc(RecNo);
  end;

  { Free heap-allocated row buffer }
  FreeMem(RowPtr, Header.RecordSize);
  BuildHeapMap := True;
end;

{ ============================================================================ }
{ Filter Analysis (Placeholder)                                                }
{ ============================================================================ }

function ExtractNumericFieldsFromFilters(var Cursor: Pointer; 
  var FieldSpecs: THeapFieldSpecArray; var FieldCount: Integer): Boolean;
begin
  { TODO: Analyze filter cursor to extract numeric fields }
  { For now, caller must manually specify fields }
  FieldCount := 0;
  ExtractNumericFieldsFromFilters := True;
end;

{ ============================================================================ }
{ Heap Map Accessors                                                           }
{ ============================================================================ }

function HeapGetWord(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): Word;
var
  PData: ^Word;
begin
  if (RecordIdx >= HeapMap.RecordCount) or (FieldIdx < 1) or (FieldIdx > HeapMap.FieldCount) then
  begin
    HeapGetWord := 0;
    Exit;
  end;
  
  if HeapMap.FieldSpecs[FieldIdx].HeapFieldType <> hftWord then
  begin
    HeapGetWord := 0;
    Exit;
  end;
  
  PData := @PByteArray(HeapMap.Records)^[RecordIdx * HeapMap.RecordSize + HeapMap.FieldSpecs[FieldIdx].HeapOffset];
  HeapGetWord := PData^;
end;

function HeapGetLongInt(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): LongInt;
var
  PData: ^LongInt;
begin
  if (RecordIdx >= HeapMap.RecordCount) or (FieldIdx < 1) or (FieldIdx > HeapMap.FieldCount) then
  begin
    HeapGetLongInt := 0;
    Exit;
  end;
  
  if HeapMap.FieldSpecs[FieldIdx].HeapFieldType <> hftLongInt then
  begin
    HeapGetLongInt := 0;
    Exit;
  end;
  
  PData := @PByteArray(HeapMap.Records)^[RecordIdx * HeapMap.RecordSize + HeapMap.FieldSpecs[FieldIdx].HeapOffset];
  HeapGetLongInt := PData^;
end;

function HeapGetBitFlag(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): Boolean;
var
  PData: ^Byte;
  ByteValue: Byte;
begin
  if (RecordIdx >= HeapMap.RecordCount) or (FieldIdx < 1) or (FieldIdx > HeapMap.FieldCount) then
  begin
    HeapGetBitFlag := False;
    Exit;
  end;
  
  if HeapMap.FieldSpecs[FieldIdx].HeapFieldType <> hftBitFlags then
  begin
    HeapGetBitFlag := False;
    Exit;
  end;
  
  PData := @PByteArray(HeapMap.Records)^[RecordIdx * HeapMap.RecordSize + HeapMap.FieldSpecs[FieldIdx].HeapOffset];
  ByteValue := PData^;
  HeapGetBitFlag := (ByteValue and HeapMap.FieldSpecs[FieldIdx].BitMask) <> 0;
end;

function HeapGetNibble(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): Byte;
var
  PData: ^Byte;
  ByteValue: Byte;
begin
  if (RecordIdx >= HeapMap.RecordCount) or (FieldIdx < 1) or (FieldIdx > HeapMap.FieldCount) then
  begin
    HeapGetNibble := 0;
    Exit;
  end;
  
  if HeapMap.FieldSpecs[FieldIdx].HeapFieldType <> hftNibble then
  begin
    HeapGetNibble := 0;
    Exit;
  end;
  
  PData := @PByteArray(HeapMap.Records)^[RecordIdx * HeapMap.RecordSize + HeapMap.FieldSpecs[FieldIdx].HeapOffset];
  ByteValue := PData^;
  
  if HeapMap.FieldSpecs[FieldIdx].NibbleShift = 0 then
    { Low nibble }
    HeapGetNibble := ByteValue and $0F
  else
    { High nibble }
    HeapGetNibble := (ByteValue shr 4) and $0F;
end;

function HeapGetByte(var HeapMap: THeapMap; RecordIdx: Word; FieldIdx: Integer): Byte;
var
  PData: ^Byte;
begin
  if (RecordIdx >= HeapMap.RecordCount) or (FieldIdx < 1) or (FieldIdx > HeapMap.FieldCount) then
  begin
    HeapGetByte := 0;
    Exit;
  end;
  
  if HeapMap.FieldSpecs[FieldIdx].HeapFieldType <> hftByte then
  begin
    HeapGetByte := 0;
    Exit;
  end;
  
  PData := @PByteArray(HeapMap.Records)^[RecordIdx * HeapMap.RecordSize + HeapMap.FieldSpecs[FieldIdx].HeapOffset];
  HeapGetByte := PData^;
end;

{ ============================================================================ }
{ Segmented Heap Map Functions                                                 }
{ ============================================================================ }

function LoadHeapSegment(var Dbf: PDBFFile;
                         var FieldSpecs: THeapFieldSpecArray;
                         FieldCount: Integer;
                         TargetRecordSize: Byte;
                         StartRecNo: LongInt;
                         var Segment: THeapSegment): Boolean;
var
  RecNo: LongInt;
  HeapIdx: Word;
  TotalRecords: LongInt;
  I, J: Integer;
  FieldValue: string;
  NumValue: LongInt;
  PData: ^Byte;
  PWord: ^Word;
  PLongInt: ^LongInt;
  RowPtr: Pointer;
  Header: TDBFHeader;
  Success: Boolean;
begin
  LoadHeapSegment := False;
  { Get header for record size }
  if not DBFFileGetHeader(Dbf, Header) then
    Exit;

  { Allocate row buffer on heap }
  GetMem(RowPtr, Header.RecordSize);
  if RowPtr = nil then
    Exit;
  TotalRecords := DBFFileGetActualRowCount(Dbf);
  Segment.StartRecNo := StartRecNo;
  Segment.ActualCount := 0;

  { Initialize heap map }
  FillChar(Segment.HeapMap, SizeOf(Segment.HeapMap), 0);
  Segment.HeapMap.RecordSize := TargetRecordSize;
  Segment.HeapMap.FieldCount := FieldCount;
  Move(FieldSpecs, Segment.HeapMap.FieldSpecs, SizeOf(THeapFieldSpecArray));

  { Calculate layout for field offsets }
  if not CalculateHeapLayout(Segment.HeapMap.FieldSpecs, FieldCount, TargetRecordSize) then
  begin
    Segment.ActualCount := 0;
    Segment.EndRecNo := StartRecNo - 1;
    Segment.HeapMap.RecordCount := 0;
    FreeMem(RowPtr, Header.RecordSize);
    Exit;
  end;

  { Allocate memory for heap records }
  if not AllocateHeapRecords(Segment.HeapMap, MaxHeapRecords) then
  begin
    Segment.ActualCount := 0;
    Segment.EndRecNo := StartRecNo - 1;
    Segment.HeapMap.RecordCount := 0;
    FreeMem(RowPtr, Header.RecordSize);
    Exit;
  end;

  { Load up to MaxHeapRecords records }
  HeapIdx := 0;
  RecNo := StartRecNo;

  Success := True;
  while Success and (HeapIdx < MaxHeapRecords) and (RecNo < TotalRecords) do
  begin
    if not DBFFileSeekToRow(Dbf, RecNo) then
      Success := False
    else if not DBFFileReadRow(Dbf, RowPtr, Header.RecordSize) then
      Success := False;

    { Load each field into heap record }
    if Success then
    begin
      for I := 1 to FieldCount do
      begin
        { Get pointer to destination in heap record - use segment's FieldSpecs }
        { which have HeapOffset set by CalculateHeapLayout }
        PData := @PByteArray(Segment.HeapMap.Records)
          ^[HeapIdx * Segment.HeapMap.RecordSize + Segment.HeapMap.FieldSpecs[I].HeapOffset];

        { Get field value from DBF }
        if Segment.HeapMap.FieldSpecs[I].DBFFieldIdx = 0 then
          { Special case: RecNo }
          NumValue := RecNo
        else
        begin
          FieldValue := DBFFieldGetStr(RowPtr, Header, Segment.HeapMap.FieldSpecs[I].DBFFieldIdx);

          { Convert to JDN if requested }
          if Segment.HeapMap.FieldSpecs[I].ConvertToJDN then
            NumValue := DBFDateStrToJDN(FieldValue)
          else
          begin
            { Manual integer parsing for Turbo Pascal 5.5 }
            NumValue := 0;
            
            { Manual trim leading spaces }
            while (Length(FieldValue) > 0) and (FieldValue[1] = ' ') do
              Delete(FieldValue, 1, 1);
            
            { Manual trim trailing spaces }
            while (Length(FieldValue) > 0) and (FieldValue[Length(FieldValue)] = ' ') do
              Delete(FieldValue, Length(FieldValue), 1);
              
            for J := 1 to Length(FieldValue) do
            begin
              if (FieldValue[J] >= '0') and (FieldValue[J] <= '9') then
                NumValue := NumValue * 10 + (Ord(FieldValue[J]) - Ord('0'))
              else
                J := Length(FieldValue);  { Exit loop early }
            end;
          end;
        end;
        
        { Store based on field type }
        case Segment.HeapMap.FieldSpecs[I].HeapFieldType of
          hftWord:
          begin
            PWord := Pointer(PData);
            PWord^ := Word(NumValue);
          end;

          hftLongInt:
          begin
            PLongInt := Pointer(PData);
            PLongInt^ := NumValue;
          end;

          hftBitFlags:
          begin
            { Set bit if value is non-zero }
            if NumValue <> 0 then
              PData^ := PData^ or Segment.HeapMap.FieldSpecs[I].BitMask;
          end;

          hftNibble:
          begin
            { Clamp to 0-15 range }
            if NumValue < 0 then
              NumValue := 0
            else if NumValue > 15 then
              NumValue := 15;

            if Segment.HeapMap.FieldSpecs[I].NibbleShift = 0 then
              { Low nibble }
              PData^ := (PData^ and $F0) or (NumValue and $0F)
            else
              { High nibble }
              PData^ := (PData^ and $0F) or ((NumValue and $0F) shl 4);
          end;

          hftByte:
          begin
            { Clamp to 0-255 range }
            if NumValue < 0 then
              NumValue := 0
            else if NumValue > 255 then
              NumValue := 255;
            PData^ := Byte(NumValue);
          end;
        end;
      end;
    end;
    
    if Success then
    begin
      Inc(HeapIdx);
      Inc(RecNo);
    end;
  end;
  
  Segment.ActualCount := HeapIdx;
  Segment.EndRecNo := StartRecNo + HeapIdx - 1;
  Segment.HeapMap.RecordCount := HeapIdx;

  { Free heap-allocated row buffer }
  FreeMem(RowPtr, Header.RecordSize);
  LoadHeapSegment := True;
end;

function FilterSegment(var Segment: THeapSegment;
                       var Results: TSegmentedResults): Boolean;
var
  I: Word;
  RecNo: LongInt;
begin
  if Results.RecNos = nil then
  begin
    FilterSegment := False;
    Exit;
  end;
  FilterSegment := True;
  for I := 0 to Segment.ActualCount - 1 do
  begin
    { Check if we have room for more results }
    if Results.Count >= Results.MaxCount then
      Exit;

    { Evaluate filter on this heap record using current filter function }
    if CurrentFilterFunc(Segment.HeapMap, I) then
    begin
      { Calculate actual DBF record number }
      RecNo := Segment.StartRecNo + I;
      Results.RecNos^[Results.Count] := RecNo + 1;
      Inc(Results.Count);
    end;
  end;
end;

function QuerySegmented(var Dbf: PDBFFile;
                        var FieldSpecs: THeapFieldSpecArray;
                        FieldCount: Integer;
                        TargetRecordSize: Byte;
                        var Results: TSegmentedResults): Boolean;
var
  TotalRecords: LongInt;
  CurrentRecNo: LongInt;
  Segment: THeapSegment;
  SegmentNum: Integer;
  Ok: Boolean;
begin
  QuerySegmented := False;
  if Dbf = nil then
    Exit;
  { Validate caller-allocated buffer }
  if Results.RecNos = nil then
  begin
    Results.Count := 0;
    Exit;
  end;
  if Results.MaxCount = 0 then
  begin
    Results.Count := 0;
    Exit;
  end;

  { Global filter function should already be set by SetGlobalFilterFunc }

  TotalRecords := DBFFileGetActualRowCount(Dbf);
  Results.Count := 0;
  CurrentRecNo := 0;
  SegmentNum := 0;

  WriteLn('Total records: ', TotalRecords);
  WriteLn('Processing in segments of ', MaxHeapRecords, '...');

  { Process one segment at a time }
  while CurrentRecNo < TotalRecords do
  begin
    Inc(SegmentNum);
    Write('Segment ', SegmentNum, ': records ', CurrentRecNo + 1, '-');

    { Load segment }
    Ok := LoadHeapSegment(Dbf, FieldSpecs, FieldCount, TargetRecordSize,
                          CurrentRecNo, Segment);
    if not Ok then
      Exit;

    WriteLn(Segment.EndRecNo + 1, ' (', Segment.ActualCount, ' records)');

    { Filter segment }
    Ok := FilterSegment(Segment, Results);
    if not Ok then
    begin
      Ok := FreeHeapRecords(Segment.HeapMap);
      Exit;
    end;

    WriteLn('  Matches so far: ', Results.Count);

    { Free segment memory before loading next }
    Ok := FreeHeapRecords(Segment.HeapMap);

    { Move to next segment }
    CurrentRecNo := Segment.EndRecNo + 1;

    { Stop if results array is full }
    if Results.Count >= Results.MaxCount then
    begin
      WriteLn('Results array full, stopping early');
      CurrentRecNo := TotalRecords + 1;  { Exit while loop }
    end;
  end;

  WriteLn('Total matches: ', Results.Count);
  QuerySegmented := True;
end;

function FilterSegmentPaged(var Segment: THeapSegment;
                            var Results: TSegmentedResults;
                            var NextRecNo: LongInt): Boolean;
var
  I: Word;
  RecNo: LongInt;
begin
  if Results.RecNos = nil then
  begin
    FilterSegmentPaged := False;
    Exit;
  end;
  FilterSegmentPaged := True;
  for I := 0 to Segment.ActualCount - 1 do
  begin
    if Results.Count >= Results.MaxCount then
    begin
      NextRecNo := Segment.StartRecNo + I;
      Exit;
    end;
    if CurrentFilterFunc(Segment.HeapMap, I) then
    begin
      RecNo := Segment.StartRecNo + I;
      Results.RecNos^[Results.Count] := RecNo + 1;
      Inc(Results.Count);
    end;
  end;
  NextRecNo := Segment.EndRecNo + 1;
end;

function QuerySegmentedPaged(var Dbf: PDBFFile;
                             var FieldSpecs: THeapFieldSpecArray;
                             FieldCount: Integer;
                             TargetRecordSize: Byte;
                             StartRecNo: LongInt;
                             PageSize: Word;
                             var Results: TSegmentedResults;
                             var NextRecNo: LongInt): Boolean;
var
  TotalRecords: LongInt;
  CurrentRecNo: LongInt;
  Segment: THeapSegment;
  Ok: Boolean;
  PageLimit: Word;
  OrigMax: Word;
begin
  QuerySegmentedPaged := False;
  NextRecNo := StartRecNo;
  if Dbf = nil then
    Exit;
  if Results.RecNos = nil then
  begin
    Results.Count := 0;
    Exit;
  end;
  if Results.MaxCount = 0 then
  begin
    Results.Count := 0;
    Exit;
  end;
  if StartRecNo < 0 then
    StartRecNo := 0;

  TotalRecords := DBFFileGetActualRowCount(Dbf);
  Results.Count := 0;
  CurrentRecNo := StartRecNo;
  PageLimit := Results.MaxCount;
  if (PageSize > 0) and (PageSize < PageLimit) then
    PageLimit := PageSize;
  OrigMax := Results.MaxCount;
  Results.MaxCount := PageLimit;

  while (CurrentRecNo < TotalRecords) and (Results.Count < Results.MaxCount) do
  begin
    Ok := LoadHeapSegment(Dbf, FieldSpecs, FieldCount, TargetRecordSize,
                          CurrentRecNo, Segment);
    if not Ok then
    begin
      Results.MaxCount := OrigMax;
      Exit;
    end;

    Ok := FilterSegmentPaged(Segment, Results, CurrentRecNo);
    if not Ok then
    begin
      Ok := FreeHeapRecords(Segment.HeapMap);
      Results.MaxCount := OrigMax;
      Exit;
    end;

    Ok := FreeHeapRecords(Segment.HeapMap);
  end;

  NextRecNo := CurrentRecNo;
  Results.MaxCount := OrigMax;
  QuerySegmentedPaged := True;
end;

end.
