unit DBFILTER;

interface

uses DBFUTIL, DBF, DBFINDEX, DBFMEMO;

const
  
  { Fixed buffer size for streaming row ID results }
  RowIdBufferSize = 128;       { Match bitmap chunk size (128 records) }

  DBFilterDebug = False;
  
  { Bitmap chunk configuration for disk-based AND operations }
  BitmapChunkSize = 128;       { Records per bitmap chunk (power of 2) }
  BitmapChunkBytes = 16;       { Bytes per chunk (128 bits / 8) }
  BitmapChunkShift = 7;       { Log2(128) for fast division }
  
  { Single-pass processing configuration }
  MaxFiltersPerGroup = 32;     { Maximum filters to handle in one pass }
  RecordsPerPass = 25600;      { 200 chunks × 128 records = 25,600 records }
  ChunksPerPass = 200;         { Number of 128-record chunks per pass }

type
  { Array type for filter bitmap files - needed for older Pascal compatibility }
  TFilterBitmapArray = array[1..MaxFiltersPerGroup] of string;
  
  TDBFilterKind = (fkExactStr, fkExactNum, fkRangeNum, fkStartsWith, fkFieldRange);
  TDBMatchMode = (mmAny, mmAll);
  TDBFilterSpec = record
    Kind: TDBFilterKind;
    FieldIdx: Integer;
    FieldIdxMin: Integer;
    FieldIdxMax: Integer;
    ValueStr: string[80];        { Filter value (up to 127 chars) }
    ValueNum: LongInt;
    ValueNumMin: LongInt;
    ValueNumMax: LongInt;  { For fkFieldRange - minimum value }
    IndexFileName: string[12];     { 8.3 name in same directory }
  end;
  TDBFilterSpecArray = array[1..8] of TDBFilterSpec;
  TDBMatchGroup = record
    Mode: TDBMatchMode;
    FilterCount: Integer;
    Filters: TDBFilterSpecArray;
  end;
  TDBMatchGroupArray = array[1..4] of TDBMatchGroup;
  TDBMatchCursor = record
    ScanPos: LongInt;
    TotalRows: LongInt;
    GroupCount: Integer;
    Groups: TDBMatchGroupArray;
  end;

procedure DBMatchCursorReset(var Cursor: TDBMatchCursor);
procedure DBMatchCursorAddGroup(var Cursor: TDBMatchCursor; Mode: TDBMatchMode);
procedure DBMatchCursorInitDefault(var Cursor: TDBMatchCursor);
procedure DBMatchCursorAddExact(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Value: string);
procedure DBMatchCursorAddExactNum(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Value: LongInt);
procedure DBMatchCursorAddRangeNum(var Cursor: TDBMatchCursor; GroupIndex: Integer; 
  FieldIdxMin: Integer; FieldIdxMax: Integer; Value: LongInt);
procedure DBMatchCursorAddStartsWith(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Prefix: string);
procedure DBMatchCursorAddFieldRange(var Cursor: TDBMatchCursor; GroupIndex: Integer; 
FieldIdx: Integer; MinValue, MaxValue: LongInt);
procedure DBMatchCursorSetFilterIndex(var Cursor: TDBMatchCursor; GroupIndex: Integer; 
FilterIndex: Integer; IndexFileName: string);
procedure DBFetchNextMatchesCore(var Dbf: PDBFFile;
  var Cursor: TDBMatchCursor; var RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer);
procedure DBFetchNextMatches(var Dbf: PDBFFile; var Cursor: TDBMatchCursor;
  var RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer);

{ DBF accessor functions - forward declarations }
function DBFGetRow(Context: Pointer; RowIndex: LongInt; var Buf: Pointer): Boolean;
function DBFGetField(Context: Pointer; var Buf: Pointer; FieldIdx: Integer): string;
function DBFGetTotalRows(Context: Pointer): LongInt;

{ Disk-based bitmap operations for large AND operations }
function CreateBitmapFile(var F: File; FileName: string): Boolean;
procedure SetBitInBitmapFile(var F: File; RecordID: LongInt);
procedure ClearBitInBitmapFile(var F: File; RecordID: LongInt);
function GetBitInBitmapFile(var F: File; RecordID: LongInt): Boolean;
procedure CloseBitmapFile(var F: File);
function IntersectBitmapWithRowIds(SourceBitmapFile: string; var RowIds: PRowIdArray; 
  Count: Integer; DestBitmapFile: string): Boolean;
function ORBitmapFiles(BitmapFile1, BitmapFile2, DestBitmapFile: string): Boolean;
function ANDBitmapFiles(BitmapFile1, BitmapFile2, DestBitmapFile: string): Boolean;
procedure SetMultipleBitsInBitmapFile(var F: File; var RowIds: PRowIdArray; Count: Integer);
function BitmapFileToRowIds(BitmapFile: string; var RowIds: PRowIdArray; 
  var Count: Integer; MaxCount: Integer): Boolean;

{ Single-pass processing functions }
function ProcessNonIndexedFiltersSinglePass(var Dbf: PDBFFile; 
  var Group: TDBMatchGroup; StartRecord, EndRecord: LongInt): Boolean;
function CombineFilterBitmapFiles(var FilterBitmaps: TFilterBitmapArray; 
  FilterCount: Integer; Mode: TDBMatchMode; DestBitmapFile: string): Boolean;

{ TDBFilterSpec packing/unpacking helpers }
procedure PackFilterValue(var Filter: TDBFilterSpec; Value: string);
procedure PackFilterIndexFile(var Filter: TDBFilterSpec; FileName: string);
function UnpackFilterValue(var Filter: TDBFilterSpec): string;
function UnpackFilterIndexFile(var Filter: TDBFilterSpec): string;

{ Release global buffer used by DBFetchNextMatches }
procedure DBFilterReleaseGlobals;

implementation

var
  { Global buffer to avoid heap allocation in DBFetchNextMatchesCore }
  { This prevents heap fragmentation that can corrupt HeapMap.Records }
  GlobalRowBuf: Pointer;
  GlobalHeader: TDBFHeader;
  GlobalRecordSize: Integer;
  GlobalHeaderLoaded: Boolean;

procedure DBMatchCursorReset(var Cursor: TDBMatchCursor);
begin
  FillChar(Cursor, SizeOf(Cursor), 0);
  Cursor.GroupCount := 0;
  Cursor.ScanPos := 0;
  Cursor.TotalRows := -1;
end;

procedure DBMatchCursorAddGroup(var Cursor: TDBMatchCursor; Mode: TDBMatchMode);
begin
  if Cursor.GroupCount >= 4 then
    Exit;
  Inc(Cursor.GroupCount);
  Cursor.Groups[Cursor.GroupCount].Mode := Mode;
  Cursor.Groups[Cursor.GroupCount].FilterCount := 0;
end;

procedure DBMatchCursorInitDefault(var Cursor: TDBMatchCursor);
begin
  DBMatchCursorReset(Cursor);
  DBMatchCursorAddGroup(Cursor, mmAll);
end;

procedure DBMatchCursorAddExact(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Value: string);
var
  Idx: Integer;
begin
  if (GroupIndex < 1) or (GroupIndex > Cursor.GroupCount) then
    Exit;
  if Cursor.Groups[GroupIndex].FilterCount >= 8 then
    Exit;
  Inc(Cursor.Groups[GroupIndex].FilterCount);
  Idx := Cursor.Groups[GroupIndex].FilterCount;
  Cursor.Groups[GroupIndex].Filters[Idx].Kind := fkExactStr;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdx := FieldIdx;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMin := 0;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMax := 0;
  PackFilterValue(Cursor.Groups[GroupIndex].Filters[Idx], Value);
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNum := 0;
end;

procedure DBMatchCursorAddExactNum(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Value: LongInt);
var
  Idx: Integer;
begin
  if (GroupIndex < 1) or (GroupIndex > Cursor.GroupCount) then
    Exit;
  if Cursor.Groups[GroupIndex].FilterCount >= 8 then
    Exit;
  Inc(Cursor.Groups[GroupIndex].FilterCount);
  Idx := Cursor.Groups[GroupIndex].FilterCount;
  Cursor.Groups[GroupIndex].Filters[Idx].Kind := fkExactNum;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdx := FieldIdx;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMin := 0;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMax := 0;
  PackFilterValue(Cursor.Groups[GroupIndex].Filters[Idx], '');
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNum := Value;
end;

procedure DBMatchCursorAddRangeNum(var Cursor: TDBMatchCursor; GroupIndex: Integer; 
  FieldIdxMin: Integer; FieldIdxMax: Integer; Value: LongInt);
var
  Idx: Integer;
begin
  if (GroupIndex < 1) or (GroupIndex > Cursor.GroupCount) then
    Exit;
  if Cursor.Groups[GroupIndex].FilterCount >= 8 then
    Exit;
  Inc(Cursor.Groups[GroupIndex].FilterCount);
  Idx := Cursor.Groups[GroupIndex].FilterCount;
  Cursor.Groups[GroupIndex].Filters[Idx].Kind := fkRangeNum;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMin := FieldIdxMin;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMax := FieldIdxMax;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdx := 0;
  PackFilterValue(Cursor.Groups[GroupIndex].Filters[Idx], '');
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNum := Value;
end;

procedure DBMatchCursorAddStartsWith(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Prefix: string);
var
  Idx: Integer;
begin
  if (GroupIndex < 1) or (GroupIndex > Cursor.GroupCount) then
    Exit;
  if Cursor.Groups[GroupIndex].FilterCount >= 8 then
    Exit;
  Inc(Cursor.Groups[GroupIndex].FilterCount);
  Idx := Cursor.Groups[GroupIndex].FilterCount;
  Cursor.Groups[GroupIndex].Filters[Idx].Kind := fkStartsWith;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdx := FieldIdx;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMin := 0;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMax := 0;
  PackFilterValue(Cursor.Groups[GroupIndex].Filters[Idx], Prefix);
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNum := 0;
  PackFilterIndexFile(Cursor.Groups[GroupIndex].Filters[Idx], '');
end;

procedure DBMatchCursorAddFieldRange(var Cursor: TDBMatchCursor; 
  GroupIndex: Integer; FieldIdx: Integer; MinValue, MaxValue: LongInt);
var
  Idx: Integer;
begin
  if (GroupIndex < 1) or (GroupIndex > Cursor.GroupCount) then
    Exit;
  if Cursor.Groups[GroupIndex].FilterCount >= 8 then
    Exit;
  Inc(Cursor.Groups[GroupIndex].FilterCount);
  Idx := Cursor.Groups[GroupIndex].FilterCount;
  Cursor.Groups[GroupIndex].Filters[Idx].Kind := fkFieldRange;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdx := FieldIdx;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMin := FieldIdx;
  Cursor.Groups[GroupIndex].Filters[Idx].FieldIdxMax := FieldIdx;
  PackFilterValue(Cursor.Groups[GroupIndex].Filters[Idx], '');
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNum := 0;
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNumMin := MinValue;
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNumMax := MaxValue;
  PackFilterIndexFile(Cursor.Groups[GroupIndex].Filters[Idx], '');
end;

procedure DBMatchCursorSetFilterIndex(var Cursor: TDBMatchCursor; 
  GroupIndex: Integer; FilterIndex: Integer; IndexFileName: string);
begin
  if (GroupIndex < 1) or (GroupIndex > Cursor.GroupCount) then
    Exit;
  if (FilterIndex < 1) or (FilterIndex > Cursor.Groups[GroupIndex].FilterCount) then
    Exit;
  PackFilterIndexFile(Cursor.Groups[GroupIndex].Filters[FilterIndex], IndexFileName);
end;

procedure DBFetchNextMatchesCore(var Dbf: PDBFFile;
  var Cursor: TDBMatchCursor; var RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer);
var
  I, J: Integer;
  Group: TDBMatchGroup;
  Filter: TDBFilterSpec;
  FieldValue, MinStr, MaxStr: string;
  MinVal, MaxVal: LongInt;
  FilterMatch, GroupMatch, OverallMatch: Boolean;
begin
  { Use global buffer instead of heap allocation to avoid corruption }

  Count := 0;
  if MaxCount <= 0 then
    Exit;

  if Cursor.TotalRows < 0 then
    Cursor.TotalRows := DBFGetTotalRows(Dbf);
  if Cursor.ScanPos < 0 then
    Cursor.ScanPos := 0;
  if Cursor.ScanPos >= Cursor.TotalRows then
    Exit;

  if Cursor.GroupCount = 0 then
  begin
    { No filters - return all rows starting from scan position }
    while (Cursor.ScanPos < Cursor.TotalRows) and (Count < MaxCount) do
    begin
      RowIds^[Count] := Cursor.ScanPos;
      Inc(Count);
      Inc(Cursor.ScanPos);
    end;
    Exit;
  end;

  while (Cursor.ScanPos < Cursor.TotalRows) and (Count < MaxCount) do
  begin
    if not DBFGetRow(Dbf, Cursor.ScanPos, GlobalRowBuf) then
      Exit;
    OverallMatch := True;
    for I := 1 to Cursor.GroupCount do
    begin
      Group := Cursor.Groups[I];
      if Group.Mode = mmAll then
        GroupMatch := True
      else
        GroupMatch := False;
      if Group.FilterCount = 0 then
        GroupMatch := True;
      for J := 1 to Group.FilterCount do
      begin
        Filter := Group.Filters[J];
        FilterMatch := False;
        case Filter.Kind of
          fkExactStr:
          begin
            FieldValue := TrimString(DBFGetField(Dbf, GlobalRowBuf, Filter.FieldIdx));
            FilterMatch := FieldValue = UnpackFilterValue(Filter);
          end;
          fkExactNum:
          begin
            FieldValue := TrimString(DBFGetField(Dbf, GlobalRowBuf, Filter.FieldIdx));
            FilterMatch := ParseInt(FieldValue) = Filter.ValueNum;
          end;
          fkRangeNum:
          begin
            MinStr := TrimString(DBFGetField(Dbf, GlobalRowBuf, Filter.FieldIdxMin));
            MaxStr := TrimString(DBFGetField(Dbf, GlobalRowBuf, Filter.FieldIdxMax));
            MinVal := ParseInt(MinStr);
            MaxVal := ParseInt(MaxStr);
            if (MinVal = 0) and (MaxVal = 0) then
              FilterMatch := False
            else
            begin
              if MinVal = 0 then
                MinVal := MaxVal;
              if MaxVal = 0 then
                MaxVal := MinVal;
              FilterMatch := (Filter.ValueNum >= MinVal) and (Filter.ValueNum <= MaxVal);
            end;
          end;
          fkFieldRange:
          begin
            FieldValue := TrimString(DBFGetField(Dbf, GlobalRowBuf, Filter.FieldIdx));
            FilterMatch := (ParseInt(FieldValue) >= Filter.ValueNumMin) and (ParseInt(FieldValue) <= Filter.ValueNumMax);
          end;
          fkStartsWith:
          begin
            FieldValue := TrimString(DBFGetField(Dbf, GlobalRowBuf, Filter.FieldIdx));
            FilterMatch := Copy(FieldValue, 1, Length(UnpackFilterValue(Filter))) = UnpackFilterValue(Filter);
          end;
        end;

        if Group.Mode = mmAll then
          GroupMatch := GroupMatch and FilterMatch
        else
          GroupMatch := GroupMatch or FilterMatch;

        if (Group.Mode = mmAll) and (not GroupMatch) then
          J := Group.FilterCount;  { Exit inner loop early }
        if (Group.Mode = mmAny) and GroupMatch then
          J := Group.FilterCount;  { Exit inner loop early }
      end;
      if not GroupMatch then
      begin
        OverallMatch := False;
        I := Cursor.GroupCount;  { Exit outer loop early }
      end;
    end;
    if OverallMatch then
    begin
      RowIds^[Count] := Cursor.ScanPos;
      Inc(Count);
    end;
    Inc(Cursor.ScanPos);
  end;
end;

{ ============================================================================ }
{ Progressive Multi-Group Filtering Implementation                             }
{ ============================================================================ }

function EvaluateFilterMatch(var Dbf: PDBFFile; var Buf: Pointer; 
  var Filter: TDBFilterSpec): Boolean;
var
  FieldValue, MinStr, MaxStr: string;
  MinVal, MaxVal: LongInt;
  function UpperStr(S: string): string;
  var
    K: Integer;
  begin
    for K := 1 to Length(S) do
      S[K] := UpCase(S[K]);
    UpperStr := S;
  end;
begin
  EvaluateFilterMatch := False;
  case Filter.Kind of
    fkExactStr:
    begin
      FieldValue := UpperStr(TrimString(DBFGetField(Dbf, Buf, Filter.FieldIdx)));
      EvaluateFilterMatch := FieldValue = UpperStr(UnpackFilterValue(Filter));
    end;
    fkExactNum:
    begin
      FieldValue := TrimString(DBFGetField(Dbf, Buf, Filter.FieldIdx));
      EvaluateFilterMatch := ParseInt(FieldValue) = Filter.ValueNum;
    end;
    fkRangeNum:
    begin
      MinStr := TrimString(DBFGetField(Dbf, Buf, Filter.FieldIdxMin));
      MaxStr := TrimString(DBFGetField(Dbf, Buf, Filter.FieldIdxMax));
      MinVal := ParseInt(MinStr);
      MaxVal := ParseInt(MaxStr);
      if (MinVal = 0) and (MaxVal = 0) then
        EvaluateFilterMatch := False
      else
      begin
        if MinVal = 0 then
          MinVal := MaxVal;
        if MaxVal = 0 then
          MaxVal := MinVal;
        EvaluateFilterMatch := (Filter.ValueNum >= MinVal) and (Filter.ValueNum <= MaxVal);
      end;
    end;
    fkStartsWith:
    begin
      FieldValue := UpperStr(TrimString(DBFGetField(Dbf, Buf, Filter.FieldIdx)));
      EvaluateFilterMatch := Copy(FieldValue, 1, Length(UnpackFilterValue(Filter))) = UpperStr(UnpackFilterValue(Filter));
    end;
    fkFieldRange:
    begin
      FieldValue := TrimString(DBFGetField(Dbf, Buf, Filter.FieldIdx));
      MinVal := ParseInt(FieldValue);
      EvaluateFilterMatch := (MinVal >= Filter.ValueNumMin) and (MinVal <= Filter.ValueNumMax);
    end;
  end;
end;


function ORBitmapFiles(BitmapFile1, BitmapFile2, DestBitmapFile: string): Boolean;
var
  F1, F2, DestF: File;
  Buffer1, Buffer2, DestBuffer: array[1..BitmapChunkBytes] of Byte;
  BytesRead1, BytesRead2, BytesWritten: Integer;
  MoreData: Boolean;
  IOR: Integer;
begin
  if not CreateBitmapFile(DestF, DestBitmapFile) then
  begin
    ORBitmapFiles := False;
    Exit;
  end;
  
  {$I-}
  Assign(F1, BitmapFile1);
  Assign(F2, BitmapFile2);
  Reset(F1, 1);
  Reset(F2, 1);
  if IOResult <> 0 then
  begin
    CloseBitmapFile(DestF);
    ORBitmapFiles := False;
    Exit;
  end;
  {$I+}
  
  MoreData := True;
  while MoreData do
  begin
    FillChar(Buffer1, SizeOf(Buffer1), 0);
    FillChar(Buffer2, SizeOf(Buffer2), 0);
    FillChar(DestBuffer, SizeOf(DestBuffer), 0);
    
    BlockRead(F1, Buffer1, BitmapChunkBytes, BytesRead1);
    BlockRead(F2, Buffer2, BitmapChunkBytes, BytesRead2);
    
    { OR the buffers byte by byte }
    for BytesWritten := 1 to BitmapChunkBytes do
      DestBuffer[BytesWritten] := Buffer1[BytesWritten] or Buffer2[BytesWritten];
    
    if (BytesRead1 > 0) or (BytesRead2 > 0) then
      BlockWrite(DestF, DestBuffer, BitmapChunkBytes)
    else
      MoreData := False;
  end;
  
  CloseBitmapFile(F1);
  CloseBitmapFile(F2);
  CloseBitmapFile(DestF);
  ORBitmapFiles := True;
end;

function ANDBitmapFiles(BitmapFile1, BitmapFile2, DestBitmapFile: string): Boolean;
var
  F1, F2, DestF: File;
  Buffer1, Buffer2, DestBuffer: array[1..BitmapChunkBytes] of Byte;
  BytesRead1, BytesRead2, BytesWritten: Integer;
  MoreData: Boolean;
  IOR: Integer;
begin
  if not CreateBitmapFile(DestF, DestBitmapFile) then 
  begin
    ANDBitmapFiles := False;
    Exit;
  end;
  
  {$I-}
  Assign(F1, BitmapFile1);
  Assign(F2, BitmapFile2);
  Reset(F1, 1);
  Reset(F2, 1);
  IOR := IOResult;
  if IOR <> 0 then
  begin
    if DBFilterDebug then
      WriteLn('ANDBitmapFiles open failed IO=', IOR,
        ' src1=', BitmapFile1, ' src2=', BitmapFile2,
        ' dest=', DestBitmapFile);
    CloseBitmapFile(DestF);
    ANDBitmapFiles := False;
    Exit;
  end;
  {$I+}
  
  MoreData := True;
  while MoreData do
  begin
    FillChar(Buffer1, SizeOf(Buffer1), 0);
    FillChar(Buffer2, SizeOf(Buffer2), 0);
    FillChar(DestBuffer, SizeOf(DestBuffer), 0);
    
    BlockRead(F1, Buffer1, BitmapChunkBytes, BytesRead1);
    BlockRead(F2, Buffer2, BitmapChunkBytes, BytesRead2);
    
    { AND the buffers byte by byte }
    for BytesWritten := 1 to BitmapChunkBytes do
      DestBuffer[BytesWritten] := Buffer1[BytesWritten] and Buffer2[BytesWritten];
    
    if (BytesRead1 > 0) or (BytesRead2 > 0) then
      BlockWrite(DestF, DestBuffer, BitmapChunkBytes)
    else
      MoreData := False;
  end;
  
  CloseBitmapFile(F1);
  CloseBitmapFile(F2);
  CloseBitmapFile(DestF);
  if DBFilterDebug then
    WriteLn('ANDBitmapFiles ok dest=', DestBitmapFile);
  ANDBitmapFiles := True;
end;

function IntersectBitmapWithRowIds(SourceBitmapFile: string; var RowIds: PRowIdArray; 
  Count: Integer; DestBitmapFile: string): Boolean;
var
  SourceF, DestF: File;
  I: Integer;
begin
  if not CreateBitmapFile(DestF, DestBitmapFile) then 
  begin
    IntersectBitmapWithRowIds := False;
    Exit;
  end;
  
  {$I-}
  Assign(SourceF, SourceBitmapFile);
  Reset(SourceF, 1);
  if IOResult <> 0 then
  begin
    CloseBitmapFile(DestF);
    IntersectBitmapWithRowIds := False;
    Exit;
  end;
  {$I+}
  
  { For each RowId, check if it exists in source bitmap }
  for I := 0 to Count - 1 do
  begin
    if GetBitInBitmapFile(SourceF, RowIds^[I]) then
      SetBitInBitmapFile(DestF, RowIds^[I]);
  end;
  
  CloseBitmapFile(SourceF);
  CloseBitmapFile(DestF);
  IntersectBitmapWithRowIds := True;
end;

procedure ProcessIndexSearchesForGroup(var Group: TDBMatchGroup; var MatchesBitmap: string;
  var TempBitmap: string; var CandidateBitmap: string; TotalRows: LongInt);
var
  I, J, Count: Integer;
  Filter: TDBFilterSpec;
  RowIds: PRowIdArray;
  Success: Boolean;
  TotalProcessed: Integer;
  HasMoreResults: Boolean;
  TempF, MatchesF: File;
  Result: Boolean;
  EmptyF: File;

begin
  { Allocate fixed 100-element buffer for paging }
  GetMem(RowIds, RowIdBufferSize * SizeOf(LongInt));
  
  { Initialize bitmap files }
  Result := CreateBitmapFile(TempF, 'temp_index.bmp');
  Result := CreateBitmapFile(MatchesF, 'matches_index.bmp');
  
  { Process all index searches (fkStartsWith and fkFieldRange) in this group }
  for I := 1 to Group.FilterCount do
  begin
    Filter := Group.Filters[I];
    Success := False;
    TotalProcessed := 0;
    HasMoreResults := True;
    
    { Handle fkStartsWith with index - use paging }
    if (Filter.Kind = fkStartsWith) and (UnpackFilterIndexFile(Filter) <> '') then
    begin
      while HasMoreResults do
      begin
        Count := 0;
        Success := FindCharacterBegins(UnpackFilterIndexFile(Filter), 
          UnpackFilterValue(Filter), RowIds, RowIdBufferSize, Count);
        
        if Success and (Count > 0) then
        begin
          { Process this page of results }
          { Set bits in temp bitmap }
          SetMultipleBitsInBitmapFile(TempF, RowIds, Count);
          
          { If no candidate bitmap, use temp directly }
          if CandidateBitmap = '' then
          begin
            Result := ORBitmapFiles('matches_index.bmp', 'temp_index.bmp', 'matches_index.bmp');
          end
          else
          begin
            { Intersect with candidates }
            Result := IntersectBitmapWithRowIds('temp_index.bmp', RowIds, Count, 'matches_index.bmp');
          end;
          
          Inc(TotalProcessed, Count);
          
          { Check if we have more results }
          HasMoreResults := (Count = RowIdBufferSize) and Success;
        end
        else
          HasMoreResults := False;
      end;
    end
    else { Handle fkFieldRange with index - use paging }
    if (Filter.Kind = fkFieldRange) and (UnpackFilterIndexFile(Filter) <> '') then
    begin
      while HasMoreResults do
      begin
        Count := 0;
        Success := FindNumberRange(UnpackFilterIndexFile(Filter), 
        Filter.ValueNumMin, Filter.ValueNumMax, RowIds, RowIdBufferSize, Count);
        
        if Success and (Count > 0) then
        begin
          { Process this page of results }
          { Clear temp bitmap by recreating it }
          Result := CreateBitmapFile(TempF, 'temp_index.bmp');
          if not Result then Exit;
          for J := 0 to Count - 1 do
          begin
            { Only include if in candidates }
            if GetBitInBitmapFile(TempF, RowIds^[J]) then
              SetBitInBitmapFile(TempF, RowIds^[J]);
          end;
          
          { Apply to matches based on group mode }
          if Group.Mode = mmAny then
          begin
            Result := ORBitmapFiles('matches_index.bmp', 'temp_index.bmp', 'matches_index.bmp');  { OR: Add these matches }
            if not Result then Exit;
          end
          else
          begin
            Result := ANDBitmapFiles('matches_index.bmp', 'temp_index.bmp', 'matches_index.bmp'); { AND: Remove non-matches }
            if not Result then Exit;
          end;
            
          Inc(TotalProcessed, Count);
          { Check if we got a full buffer - might be more results }
          HasMoreResults := (Count = RowIdBufferSize);
        end
        else
          HasMoreResults := False;
      end;
    end;
    
    { Handle case where index search found nothing in AND mode }
    if (TotalProcessed = 0) and ((Success or (UnpackFilterIndexFile(Filter) <> '')) and (Group.Mode = mmAll)) then
    begin
      { Index search found nothing, AND mode means no matches }
      { Create empty matches bitmap file }
      Result := CreateBitmapFile(EmptyF, 'matches_index.bmp');
      CloseBitmapFile(EmptyF);
    end;
  end;
  
  { Clean up allocated memory }
  if RowIds <> nil then FreeMem(RowIds, RowIdBufferSize * SizeOf(LongInt));
end;

procedure ProcessNumericFiltersForGroup(var Dbf: PDBFFile;
  var Group: TDBMatchGroup; var MatchesBitmap: string; var TempBitmap: string;
  var CandidateBitmap: string; TotalRows: LongInt);
var
  I, J: Integer;
  RecNo: LongInt;
  Buf: Pointer;
  PassesFilter: Boolean;
  Filter: TDBFilterSpec;
  TempF: File;
  Result: Boolean;
begin
  if Group.Mode = mmAny then
  begin
    { OR mode: Process each filter incrementally }
    for I := 1 to Group.FilterCount do
    begin
      Filter := Group.Filters[I];
      { Skip index searches (already processed) and field ranges with index }
      if (Filter.Kind <> fkStartsWith) and 
         not ((Filter.Kind = fkFieldRange) and (UnpackFilterIndexFile(Filter) <> '')) then
      begin
        { Scan only records in CandidateBitmap }
        { Clear temp bitmap by recreating it }
        Result := CreateBitmapFile(TempF, 'temp_filter.bmp');
        if not Result then Exit;
        RecNo := 0;
        while RecNo < TotalRows do
        begin
          if GetBitInBitmapFile(TempF, RecNo) then
          begin
            if DBFGetRow(Dbf, RecNo, Buf) then
            begin
              if EvaluateFilterMatch(Dbf, Buf, Filter) then
                SetBitInBitmapFile(TempF, RecNo);
            end;
          end;
          Inc(RecNo);
        end;
        { OR this filter's results into Matches }
        Result := ORBitmapFiles('matches_index.bmp', 'temp_filter.bmp', 'matches_index.bmp');
        if not Result then Exit;
      end;
    end;
  end
  else
  begin
    { AND mode: Build combo filter, scan Matches once }
    RecNo := 0;
    while RecNo < TotalRows do
    begin
      if GetBitInBitmapFile(TempF, RecNo) then
      begin
        if DBFGetRow(Dbf, RecNo, Buf) then
        begin
          { Test ALL numeric filters at once }
          PassesFilter := True;
          J := 1;
          while (J <= Group.FilterCount) and PassesFilter do
          begin
            Filter := Group.Filters[J];
            { Skip index searches (already processed) and field ranges with index }
            if (Filter.Kind <> fkStartsWith) and 
               not ((Filter.Kind = fkFieldRange) and (UnpackFilterIndexFile(Filter) <> '')) then
            begin
              if not EvaluateFilterMatch(Dbf, Buf, Filter) then
                PassesFilter := False;
            end;
            Inc(J);
          end;
          { If fails combo filter, clear the bit }
          if not PassesFilter then
            ClearBitInBitmapFile(TempF, RecNo);
        end;
      end;
      Inc(RecNo);
    end;
  end;
end;

procedure DBFetchNextMatchesProgressive(var Dbf: PDBFFile;
  var Cursor: TDBMatchCursor; var RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer);
var
  MatchesBitmap, TempBitmap, PrevMatchesBitmap, FullSetBitmap: string;
  I: Integer;
  RecNo: LongInt;
  HasMatches: Boolean;
  Group: TDBMatchGroup;
  EmptyF, FullF, FullSetF, MatchesF: File;
  Result : Boolean;
begin
  
  { Initialize based on first group's mode }
  if Cursor.Groups[1].Mode = mmAny then
  begin
    { OR mode: start empty }
    Result := CreateBitmapFile(EmptyF, 'matches_index.bmp');
    if not Result then Exit;
    CloseBitmapFile(EmptyF);
  end
  else
  begin
    { AND mode: start full - create bitmap with all bits set }
    Result := CreateBitmapFile(FullF, 'matches_index.bmp');
    if not Result then Exit;
    { TODO: Set all bits to 1 for full bitmap }
    CloseBitmapFile(FullF);
  end;
  
  { Create full set for first OR group }
  Result := CreateBitmapFile(FullSetF, 'fullset_index.bmp');
  if not Result then Exit;
  { TODO: Set all bits to 1 for full set bitmap }
  CloseBitmapFile(FullSetF);
  
  { Process each group }
  HasMatches := True;
  I := 1;
  while (I <= Cursor.GroupCount) and HasMatches do
  begin
    Group := Cursor.Groups[I];
    
    if I = 1 then
    begin
      { First group: process based on its mode }
      if Group.Mode = mmAny then
      begin
        { OR mode: process index searches and numeric filters }
        MatchesBitmap := 'matches_index.bmp';
        TempBitmap := 'temp_index.bmp';
        FullSetBitmap := 'fullset_index.bmp';
        ProcessIndexSearchesForGroup(Group, MatchesBitmap, TempBitmap, FullSetBitmap, Cursor.TotalRows);
        ProcessNumericFiltersForGroup(Dbf, Group, MatchesBitmap, TempBitmap, FullSetBitmap, Cursor.TotalRows);
      end
      else
      begin
        { AND mode: filter down from all records }
        MatchesBitmap := 'matches_index.bmp';
        TempBitmap := 'temp_index.bmp';
        ProcessIndexSearchesForGroup(Group, MatchesBitmap, TempBitmap, MatchesBitmap, Cursor.TotalRows);
        ProcessNumericFiltersForGroup(Dbf, Group, MatchesBitmap, TempBitmap, MatchesBitmap, Cursor.TotalRows);
      end;
    end
    else
    begin
      { Subsequent groups: AND with previous results }
      if Group.Mode = mmAny then
      begin
        { OR mode: collect matches from candidates, then AND }
        Result := CreateBitmapFile(EmptyF, 'matches_index.bmp');
        if not Result then Exit;
        CloseBitmapFile(EmptyF);
        MatchesBitmap := 'matches_index.bmp';
        TempBitmap := 'temp_index.bmp';
        PrevMatchesBitmap := 'prev_matches_index.bmp';
        ProcessIndexSearchesForGroup(Group, MatchesBitmap, TempBitmap, PrevMatchesBitmap, Cursor.TotalRows);
        ProcessNumericFiltersForGroup(Dbf, Group, MatchesBitmap, TempBitmap, PrevMatchesBitmap, Cursor.TotalRows);
        Result := ANDBitmapFiles('matches_index.bmp', 'prev_matches_index.bmp', 'matches_index.bmp');
        if not Result then Exit;
      end
      else
      begin
        { AND mode: filter existing matches }
        MatchesBitmap := 'matches_index.bmp';
        TempBitmap := 'temp_index.bmp';
        ProcessIndexSearchesForGroup(Group, MatchesBitmap, TempBitmap, MatchesBitmap, Cursor.TotalRows);
        ProcessNumericFiltersForGroup(Dbf, Group, MatchesBitmap, TempBitmap, MatchesBitmap, Cursor.TotalRows);
      end;
    end;
    
    { Check if any matches remain }
    { TODO: Implement file-based bitmap empty check }
    HasMatches := True;  { For now, assume we have matches }
    Inc(I);
  end;
  
  { Extract results from bitmap }
  if HasMatches then
  begin
    Assign(MatchesF, 'matches_index.bmp');
    {$I-}
    Reset(MatchesF, 1);
    {$I+}
    if IOResult <> 0 then Exit;
    
    RecNo := 0;
    while (RecNo < Cursor.TotalRows) and (Count < MaxCount) do
    begin
      if GetBitInBitmapFile(MatchesF, RecNo) then
      begin
        RowIds^[Count] := RecNo;
        Inc(Count);
      end;
      Inc(RecNo);
    end;
    
    CloseBitmapFile(MatchesF);
  end;
end;

function DBFGetRow(Context: Pointer; RowIndex: LongInt; var Buf: Pointer): Boolean;
var
  Dbf: PDBFFile;
  HasRow: Boolean;
begin
  Dbf := PDBFFile(Context);
  if Dbf = nil then
  begin
    HasRow := False;
  end
  else
  begin
    { Load header on first call to get record size }
    if not GlobalHeaderLoaded then
    begin
      if DBFFileGetHeader(Dbf, GlobalHeader) then
      begin
        GlobalRecordSize := GlobalHeader.RecordSize;
        GlobalHeaderLoaded := True;
        GetMem(GlobalRowBuf, GlobalRecordSize);
      end;
    end;
    if not GlobalHeaderLoaded then
    begin
      HasRow := False;
    end
    else
    begin
      Buf := GlobalRowBuf;
      if not DBFFileSeekToRow(Dbf, RowIndex) then ;
      if not DBFFileReadRow(Dbf, Buf, GlobalRecordSize) then ;
      HasRow := True;
    end;
  end;

  DBFGetRow := HasRow;
end;

function DBFGetField(Context: Pointer; var Buf: Pointer; FieldIdx: Integer): string;
var
  Dbf: PDBFFile;
begin
  Dbf := PDBFFile(Context);
  if Dbf = nil then
  begin
    DBFGetField := '';
    Exit;
  end;
  DBFGetField := DBFFieldGetStr(Buf, GlobalHeader, FieldIdx);
end;

function DBFGetTotalRows(Context: Pointer): LongInt;
var
  Dbf: PDBFFile;
begin
  Dbf := PDBFFile(Context);
  if Dbf = nil then
  begin
    DBFGetTotalRows := 0;
    Exit;
  end;
  DBFGetTotalRows := DBFFileGetActualRowCount(Dbf);
end;

procedure DBFetchNextMatches(var Dbf: PDBFFile; var Cursor: TDBMatchCursor;
  var RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer);
begin
  DBFetchNextMatchesCore(Dbf, Cursor, RowIds, MaxCount, Count);
end;

{ ============================================================================ }
{ Disk-based Bitmap Operations for Large AND Operations                        }
{ ============================================================================ }

function CreateBitmapFile(var F: File; FileName: string): Boolean;
var
  IOR: Integer;
  Result: Boolean;
begin
  Assign(F, FileName);
  {$I-}
  Rewrite(F, 1);
  {$I+}
  IOR := IOResult;
  Result := (IOR = 0);
  if DBFilterDebug and not Result then
    WriteLn('CreateBitmapFile failed: ', FileName, ' IO=', IOR);
  CreateBitmapFile := Result;
end;

procedure SetBitInBitmapFile(var F: File; RecordID: LongInt);
var
  ChunkNum: LongInt;
  BitPos: Integer;
  ByteOffset: Integer;
  BitMask: Byte;
  ChunkBuffer: array[1..BitmapChunkBytes] of Byte;
  FilePos: LongInt;
  FileEnd: LongInt;
  IOR: Integer;
begin
  ChunkNum := RecordID shr BitmapChunkShift;  { Fast division by 128 }
  BitPos := RecordID and (BitmapChunkSize - 1); { Fast modulo 128 }
  ByteOffset := BitPos shr 3;  { Divide by 8 }
  BitMask := 1 shl (BitPos and 7);  { Modulo 8 }

  FilePos := ChunkNum * BitmapChunkBytes;

  {$I-}
  { Get current file size }
  FileEnd := FileSize(F);
  if IOResult <> 0 then Exit;

  { If target chunk is beyond file end, pad with zero-filled chunks }
  if FilePos >= FileEnd then
  begin
    FillChar(ChunkBuffer, SizeOf(ChunkBuffer), 0);
    Seek(F, FileEnd);
    if IOResult <> 0 then Exit;
    while FileEnd < FilePos do
    begin
      BlockWrite(F, ChunkBuffer, BitmapChunkBytes, IOR);
      Inc(FileEnd, BitmapChunkBytes);
    end;
    { Write the target chunk with the bit set }
    ChunkBuffer[ByteOffset + 1] := BitMask;
    BlockWrite(F, ChunkBuffer, BitmapChunkBytes, IOR);
  end
  else
  begin
    { Chunk exists - read, modify, write back }
    Seek(F, FilePos);
    if IOResult <> 0 then Exit;
    BlockRead(F, ChunkBuffer, BitmapChunkBytes, IOR);
    if IOR = BitmapChunkBytes then
    begin
      ChunkBuffer[ByteOffset + 1] := ChunkBuffer[ByteOffset + 1] or BitMask;
      Seek(F, FilePos);
      BlockWrite(F, ChunkBuffer, BitmapChunkBytes, IOR);
    end;
  end;
  {$I+}
end;

procedure ClearBitInBitmapFile(var F: File; RecordID: LongInt);
var
  ChunkNum: LongInt;
  BitPos: Integer;
  ByteOffset: Integer;
  BitMask: Byte;
  ChunkBuffer: array[1..BitmapChunkBytes] of Byte;
  FilePos: LongInt;
  IOR: Integer;
begin
  ChunkNum := RecordID shr BitmapChunkShift;  { Fast division by 128 }
  BitPos := RecordID and (BitmapChunkSize - 1); { Fast modulo 128 }
  ByteOffset := BitPos shr 3;  { Divide by 8 }
  BitMask := not (1 shl (BitPos and 7));  { Inverted mask for clearing }
  
  FilePos := ChunkNum * BitmapChunkBytes;
  
  {$I-}
  Seek(F, FilePos);
  if IOResult = 0 then
  begin
    BlockRead(F, ChunkBuffer, BitmapChunkBytes, IOR);
    if IOR = BitmapChunkBytes then
    begin
      ChunkBuffer[ByteOffset + 1] := ChunkBuffer[ByteOffset + 1] and BitMask;
      Seek(F, FilePos);
      BlockWrite(F, ChunkBuffer, BitmapChunkBytes, IOR);
    end;
    { If chunk doesn't exist, bit is already 0, so no action needed }
  end;
  {$I+}
end;

function GetBitInBitmapFile(var F: File; RecordID: LongInt): Boolean;
var
  ChunkNum: LongInt;
  BitPos: Integer;
  ByteOffset: Integer;
  BitMask: Byte;
  ChunkBuffer: array[1..BitmapChunkBytes] of Byte;
  FilePos: LongInt;
  IOR: Integer;
begin
  ChunkNum := RecordID shr BitmapChunkShift;
  BitPos := RecordID and (BitmapChunkSize - 1);
  ByteOffset := BitPos shr 3;
  BitMask := 1 shl (BitPos and 7);
  
  FilePos := ChunkNum * BitmapChunkBytes;
  
  {$I-}
  Seek(F, FilePos);
  if IOResult = 0 then
  begin
    BlockRead(F, ChunkBuffer, BitmapChunkBytes, IOR);
    GetBitInBitmapFile := (IOR = BitmapChunkBytes) and 
                        ((ChunkBuffer[ByteOffset + 1] and BitMask) <> 0);
  end
  else
    GetBitInBitmapFile := False;
  {$I+}
end;

procedure CloseBitmapFile(var F: File);
begin
  {$I-}
  Close(F);
  {$I+}
end;

procedure SetMultipleBitsInBitmapFile(var F: File; var RowIds: PRowIdArray; Count: Integer);
var
  I: Integer;
begin
  for I := 0 to Count - 1 do
    SetBitInBitmapFile(F, RowIds^[I]);
end;

function BitmapFileToRowIds(BitmapFile: string; var RowIds: PRowIdArray; 
  var Count: Integer; MaxCount: Integer): Boolean;
var
  F: File;
  Buffer: array[1..BitmapChunkBytes] of Byte;
  ChunkNum: LongInt;
  BytesRead: Integer;
  BitPos, BytePos: Integer;
  RecordID: LongInt;
  Done: Boolean;
begin
  BitmapFileToRowIds := False;
  Count := 0;
  
  {$I-}
  Assign(F, BitmapFile);
  Reset(F, 1);
  if IOResult <> 0 then Exit;
  {$I+}
  
  ChunkNum := 0;
  Done := False;
  while not EOF(F) and (Count < MaxCount) and not Done do
  begin
    FillChar(Buffer, SizeOf(Buffer), 0);
    BlockRead(F, Buffer, BitmapChunkBytes, BytesRead);
    
    if BytesRead > 0 then
    begin
      { Process each bit in the chunk }
      for BitPos := 0 to BitmapChunkSize - 1 do
      begin
        BytePos := BitPos shr 3;  { Divide by 8 }
        if (Buffer[BytePos + 1] and (1 shl (BitPos and 7))) <> 0 then
        begin
          RecordID := (ChunkNum * BitmapChunkSize) + BitPos;
          if Count < MaxCount then
          begin
            RowIds^[Count] := RecordID;
            Inc(Count);
          end
          else
            Done := True;  { Reached MaxCount limit }
        end;
        { if Done then the while loop condition will handle exit }
      end;
      Inc(ChunkNum);
    end;
  end;
  
  CloseBitmapFile(F);
  BitmapFileToRowIds := True;
end;

{ ============================================================================ }
{ Single-Pass Non-Indexed Filter Processing                                   }
{ ============================================================================ }

function ProcessNonIndexedFiltersSinglePass(var Dbf: PDBFFile; 
  var Group: TDBMatchGroup; StartRecord, EndRecord: LongInt): Boolean;
var
  FilterBitmaps: array[1..MaxFiltersPerGroup] of File;
  FilterBitmapFiles: array[1..MaxFiltersPerGroup] of string;
  RecordBuffers: array[0..RowIdBufferSize - 1] of Pointer;
  FilterIdx, BufferIdx: Integer;
  RecNo, RecordsInBatch: LongInt;
  NonIndexedFilterCount: Integer;
  Filter: TDBFilterSpec;
  TempFileName: string;
  RecordSize: Integer;
begin
  ProcessNonIndexedFiltersSinglePass := False;
  
  { Get record size from DBF header }
  if not GlobalHeaderLoaded then
  begin
    if not DBFFileGetHeader(Dbf, GlobalHeader) then Exit;
    GlobalRecordSize := GlobalHeader.RecordSize;
    GlobalHeaderLoaded := True;
  end;
  RecordSize := GlobalRecordSize;
  
  { Allocate memory for record buffers }
  for BufferIdx := 0 to RowIdBufferSize - 1 do
    GetMem(RecordBuffers[BufferIdx], RecordSize);
  
  { Count non-indexed filters and create bitmap files }
  NonIndexedFilterCount := 0;
  for FilterIdx := 1 to Group.FilterCount do
  begin
    Filter := Group.Filters[FilterIdx];
    { Skip indexed searches - only process non-indexed filters }
    if (Filter.Kind <> fkStartsWith) and 
       not ((Filter.Kind = fkFieldRange) and (UnpackFilterIndexFile(Filter) <> '')) then
    begin
      Inc(NonIndexedFilterCount);
      TempFileName := 'filter' + IntToStrLocal(NonIndexedFilterCount) + '.bmp';
      FilterBitmapFiles[NonIndexedFilterCount] := TempFileName;
      
      if not CreateBitmapFile(FilterBitmaps[NonIndexedFilterCount], TempFileName) then
      begin
        { Clean up allocated memory on failure }
        for BufferIdx := 0 to RowIdBufferSize - 1 do
          if RecordBuffers[BufferIdx] <> nil then
          begin
            FreeMem(RecordBuffers[BufferIdx], RecordSize);
            RecordBuffers[BufferIdx] := nil;
          end;
        Exit;
      end;
    end;
  end;
  
  if NonIndexedFilterCount = 0 then
  begin
    ProcessNonIndexedFiltersSinglePass := True;  { No non-indexed filters to process }
    Exit;
  end;
  
  { Seek to start position }
  if not DBFFileSeekToRow(Dbf, StartRecord) then ;
  RecNo := StartRecord;
  
  { Process records in batches of 128 }
  while RecNo <= EndRecord do
  begin
    { Calculate how many records to read in this batch }
    RecordsInBatch := RowIdBufferSize;
    if (RecNo + RecordsInBatch - 1) > EndRecord then
      RecordsInBatch := EndRecord - RecNo + 1;
    
    { Read batch of records sequentially }
    for BufferIdx := 0 to RecordsInBatch - 1 do
      if not DBFFileReadRow(Dbf, RecordBuffers[BufferIdx], RecordSize) then ;
    
    { Evaluate all non-indexed filters for all records in batch }
    FilterIdx := 0;
    for FilterIdx := 1 to Group.FilterCount do
    begin
      Filter := Group.Filters[FilterIdx];
      { Skip indexed searches }
      if (Filter.Kind <> fkStartsWith) and 
         not ((Filter.Kind = fkFieldRange) and (UnpackFilterIndexFile(Filter) <> '')) then
      begin
        Inc(FilterIdx);
        
        { Check each record in the batch against this filter }
        for BufferIdx := 0 to RecordsInBatch - 1 do
        begin
          if EvaluateFilterMatch(Dbf, RecordBuffers[BufferIdx], Filter) then
            SetBitInBitmapFile(FilterBitmaps[FilterIdx], RecNo + BufferIdx);
        end;
      end;
    end;
    
    Inc(RecNo, RecordsInBatch);
  end;
  
  { Close all bitmap files }
  for FilterIdx := 1 to NonIndexedFilterCount do
    CloseBitmapFile(FilterBitmaps[FilterIdx]);
    
  { Clean up allocated record buffers }
  for BufferIdx := 0 to RowIdBufferSize - 1 do
    if RecordBuffers[BufferIdx] <> nil then
    begin
      FreeMem(RecordBuffers[BufferIdx], RecordSize);
      RecordBuffers[BufferIdx] := nil;
    end;
    
  ProcessNonIndexedFiltersSinglePass := True;
end;

function CombineFilterBitmapFiles(var FilterBitmaps: TFilterBitmapArray; 
  FilterCount: Integer; Mode: TDBMatchMode; DestBitmapFile: string): Boolean;
var
  TempFile: string;
  I: Integer;
  F: File;
  Result: Boolean;
begin
 
  if FilterCount = 0 then begin
    CombineFilterBitmapFiles := False;
    Exit;
  end;
  if FilterCount = 1 then
  begin
    { Single filter - just copy to destination }
    {$I-}
    Assign(F, FilterBitmaps[1]);
    Reset(F, 1);
    if IOResult = 0 then
    begin
      Close(F);
      Result := RenameFile(FilterBitmaps[1], DestBitmapFile);
      if Result then
      begin
        CombineFilterBitmapFiles := True;
        Exit;
      end;
    end;
    {$I+}
    CombineFilterBitmapFiles := False;
    Exit;
  end;
  
  { Multiple filters - combine them }
  if Mode = mmAny then
  begin
    { OR mode: combine all filters with OR }
    if not ORBitmapFiles(FilterBitmaps[1], FilterBitmaps[2], DestBitmapFile) then Exit;
    
    for I := 3 to FilterCount do
    begin
      TempFile := 'temp_or' + IntToStrLocal(I) + '.bmp';
      if not ORBitmapFiles(DestBitmapFile, FilterBitmaps[I], TempFile) then
      begin
        Result := DeleteFile(TempFile);
        Exit;
      end;
      
      { Replace destination with temp result }
      Result := DeleteFile(DestBitmapFile);
      if not Result then Exit;
      Result := RenameFile(TempFile, DestBitmapFile);
      if not Result then Exit;
    end;
  end
  else
  begin
    { AND mode: combine all filters with AND }
    if not ANDBitmapFiles(FilterBitmaps[1], FilterBitmaps[2], DestBitmapFile) then Exit;
    
    for I := 3 to FilterCount do
    begin
      TempFile := 'temp_and' + IntToStrLocal(I) + '.bmp';
      if not ANDBitmapFiles(DestBitmapFile, FilterBitmaps[I], TempFile) then
      begin
        Result := DeleteFile(TempFile);
        Exit;
      end;
      
      { Replace destination with temp result }
      Result := DeleteFile(DestBitmapFile);
      if not Result then Exit;
      Result := RenameFile(TempFile, DestBitmapFile);
      if not Result then Exit;
    end;
  end;
  
  { Clean up temporary filter files }
  for I := 1 to FilterCount do
  begin
    Result := DeleteFile(FilterBitmaps[I]);
    { Don't exit on cleanup failure }
  end;
  
  CombineFilterBitmapFiles := True;
end;

{ ============================================================================ }
{ TDBFilterSpec Packing/Unpacking Helpers                                        }
{ ============================================================================ }

procedure PackFilterValue(var Filter: TDBFilterSpec; Value: string);
begin
  Filter.ValueStr := Value;
end;

procedure PackFilterIndexFile(var Filter: TDBFilterSpec; FileName: string);
begin
  Filter.IndexFileName := FileName;
end;

function UnpackFilterValue(var Filter: TDBFilterSpec): string;
begin
  UnpackFilterValue := Filter.ValueStr;
end;

function UnpackFilterIndexFile(var Filter: TDBFilterSpec): string;
begin
  UnpackFilterIndexFile := Filter.IndexFileName;
end;

procedure DBFilterReleaseGlobals;
begin
  if GlobalRowBuf <> nil then
  begin
    FreeMem(GlobalRowBuf, GlobalRecordSize);
    GlobalRowBuf := nil;
  end;
  GlobalRecordSize := 0;
  GlobalHeaderLoaded := False;
end;

begin
  GlobalRowBuf := nil;
  GlobalRecordSize := 0;
  GlobalHeaderLoaded := False;
end.
