unit DBFILTER;

interface

uses DBF;

type
  TDBFilterKind = (fkExactStr, fkExactNum, fkRangeNum, fkStartsWith);
  TDBMatchMode = (mmAny, mmAll);
  TDBFilterSpec = record
    Kind: TDBFilterKind;
    FieldIdx: Integer;
    FieldIdxMin: Integer;
    FieldIdxMax: Integer;
    ValueStr: string[255];
    ValueNum: LongInt;
  end;
  TDBFFilterSpecArray = array[1..8] of TDBFilterSpec;
  TDBFMatchGroup = record
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
  TDBGetRowFunc = function(Context: Pointer; RowIndex: LongInt; var Buf: TDBFRow): Boolean;
  TDBGetFieldFunc = function(Context: Pointer; var Buf: TDBFRow; FieldIdx: Integer): string;
  TDBGetTotalRowsFunc = function(Context: Pointer): LongInt;
  TDBRowAccessor = record
    Context: Pointer;
    GetRow: TDBGetRowFunc;
    GetField: TDBGetFieldFunc;
    GetTotalRows: TDBGetTotalRowsFunc;
  end;

procedure DBMatchCursorReset(var Cursor: TDBMatchCursor);
procedure DBMatchCursorAddGroup(var Cursor: TDBMatchCursor; Mode: TDBMatchMode);
procedure DBMatchCursorInitDefault(var Cursor: TDBMatchCursor);
procedure DBMatchCursorAddExact(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Value: string);
procedure DBMatchCursorAddExactNum(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Value: LongInt);
procedure DBMatchCursorAddRangeNum(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdxMin: Integer; FieldIdxMax: Integer; Value: LongInt);
procedure DBMatchCursorAddStartsWith(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdx: Integer; Prefix: string);
procedure DBFetchNextMatchesCore(var Accessor: TDBRowAccessor;
  var Cursor: TDBMatchCursor; var RowIds: TDBFRowIdArray; MaxCount: Integer;
  var Count: Integer);
procedure DBFetchNextMatches(var Dbf: PDBFFile; var Cursor: TDBMatchCursor;
  var RowIds: TDBFRowIdArray; MaxCount: Integer; var Count: Integer);

implementation

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
  Cursor.Groups[GroupIndex].Filters[Idx].ValueStr := Value;
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
  Cursor.Groups[GroupIndex].Filters[Idx].ValueStr := '';
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNum := Value;
end;

procedure DBMatchCursorAddRangeNum(var Cursor: TDBMatchCursor; GroupIndex: Integer; FieldIdxMin: Integer; FieldIdxMax: Integer; Value: LongInt);
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
  Cursor.Groups[GroupIndex].Filters[Idx].ValueStr := '';
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
  Cursor.Groups[GroupIndex].Filters[Idx].ValueStr := Prefix;
  Cursor.Groups[GroupIndex].Filters[Idx].ValueNum := 0;
end;

procedure DBFetchNextMatchesCore(var Accessor: TDBRowAccessor;
  var Cursor: TDBMatchCursor; var RowIds: TDBFRowIdArray; MaxCount: Integer;
  var Count: Integer);
var
  Buf: TDBFRow;
  FieldValue: string;
  MinStr, MaxStr: string;
  MinVal, MaxVal: LongInt;
  OverallMatch: Boolean;
  FilterMatch: Boolean;
  I, J: Integer;
  Filter: TDBFilterSpec;
  Group: TDBMatchGroup;
  GroupMatch: Boolean;
  function UpperStr(S: string): string;
  var
    K: Integer;
  begin
    for K := 1 to Length(S) do
      S[K] := UpCase(S[K]);
    UpperStr := S;
  end;
begin
  Count := 0;
  if MaxCount <= 0 then
    Exit;
  if Cursor.TotalRows < 0 then
    Cursor.TotalRows := Accessor.GetTotalRows(Accessor.Context);
  if Cursor.ScanPos < 0 then
    Cursor.ScanPos := 0;
  if Cursor.ScanPos >= Cursor.TotalRows then
    Exit;

  if Cursor.GroupCount = 0 then
  begin
    while (Cursor.ScanPos < Cursor.TotalRows) and (Count < MaxCount) do
    begin
      RowIds[Count] := Cursor.ScanPos;
      Inc(Count);
      Inc(Cursor.ScanPos);
    end;
    Exit;
  end;

  while (Cursor.ScanPos < Cursor.TotalRows) and (Count < MaxCount) do
  begin
    if not Accessor.GetRow(Accessor.Context, Cursor.ScanPos, Buf) then
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
            FieldValue := UpperStr(TrimString(Accessor.GetField(Accessor.Context, Buf, Filter.FieldIdx)));
            FilterMatch := FieldValue = UpperStr(TrimString(Filter.ValueStr));
          end;
          fkExactNum:
          begin
            FieldValue := TrimString(Accessor.GetField(Accessor.Context, Buf, Filter.FieldIdx));
            FilterMatch := ParseInt(FieldValue) = Filter.ValueNum;
          end;
          fkRangeNum:
          begin
            MinStr := TrimString(Accessor.GetField(Accessor.Context, Buf, Filter.FieldIdxMin));
            MaxStr := TrimString(Accessor.GetField(Accessor.Context, Buf, Filter.FieldIdxMax));
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
          fkStartsWith:
          begin
            FieldValue := UpperStr(TrimString(Accessor.GetField(Accessor.Context, Buf, Filter.FieldIdx)));
            FilterMatch := Copy(FieldValue, 1, Length(Filter.ValueStr)) = UpperStr(TrimString(Filter.ValueStr));
          end;
        end;

        if Group.Mode = mmAll then
          GroupMatch := GroupMatch and FilterMatch
        else
          GroupMatch := GroupMatch or FilterMatch;

        if (Group.Mode = mmAll) and (not GroupMatch) then
          Break;
        if (Group.Mode = mmAny) and GroupMatch then
          Break;
      end;
      if not GroupMatch then
      begin
        OverallMatch := False;
        Break;
      end;
    end;
    if OverallMatch then
    begin
      RowIds[Count] := Cursor.ScanPos;
      Inc(Count);
    end;
    Inc(Cursor.ScanPos);
  end;
end;

function DBFGetRow(Context: Pointer; RowIndex: LongInt; var Buf: TDBFRow): Boolean;
var
  Dbf: PDBFFile;
begin
  Dbf := PDBFFile(Context);
  if Dbf = nil then
  begin
    DBFGetRow := False;
    Exit;
  end;
  DBFFileSeekToRow(Dbf, RowIndex);
  DBFFileReadRow(Dbf, Buf);
  DBFGetRow := True;
end;

function DBFGetField(Context: Pointer; var Buf: TDBFRow; FieldIdx: Integer): string;
var
  Dbf: PDBFFile;
begin
  Dbf := PDBFFile(Context);
  if Dbf = nil then
  begin
    DBFGetField := '';
    Exit;
  end;
  DBFGetField := DBFFileGetFieldStr(Buf, Dbf, FieldIdx);
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
  var RowIds: TDBFRowIdArray; MaxCount: Integer; var Count: Integer);
var
  Accessor: TDBRowAccessor;
begin
  Accessor.Context := Dbf;
  Accessor.GetRow := DBFGetRow;
  Accessor.GetField := DBFGetField;
  Accessor.GetTotalRows := DBFGetTotalRows;
  DBFetchNextMatchesCore(Accessor, Cursor, RowIds, MaxCount, Count);
end;

end.
