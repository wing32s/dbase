unit DBFFind;

{ procedures for brute-force value matches }
{ Uses public DBF API and heap-allocated buffers }

interface

uses DBFUTIL, DBF;

type
  PRowIdArray = ^TRowIdArray;
  TRowIdArray = array[0..0] of LongInt;  { Open array for pointer math }

function RowIdAt(RowIds: PRowIdArray; Index: Integer): LongInt;

function DBFFileFindRowsExact(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: string; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;
function DBFFileFindRowsExactNum(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: LongInt; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;
function DBFFileFindRowsInRangeNum(var Dbf: PDBFFile; FieldIdxMin: Integer;
  FieldIdxMax: Integer; Value: LongInt; RowIds: PRowIdArray;
  MaxCount: Integer; var Count: Integer; var ScanPos: LongInt): Boolean;
function DBFFileFindRowsStartsWith(var Dbf: PDBFFile; FieldIdx: Integer;
  Prefix: string; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;

implementation

function RowIdAt(RowIds: PRowIdArray; Index: Integer): LongInt;
begin
  RowIdAt := RowIds^[Index];
end;


function DBFFileFindRowsExact(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: string; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;
var
  Header: TDBFHeader;
  Buf: Pointer;
  RowIndex: LongInt;
  Total: LongInt;
  FieldValue: string;
  ValueTrim: string;
begin
  DBFFileFindRowsExact := False;
  Count := 0;
  if Dbf = nil then
    Exit;
  if RowIds = nil then
    Exit;
  if MaxCount <= 0 then
    Exit;
  if ScanPos < 0 then
    ScanPos := 0;

  if not DBFFileGetHeader(Dbf, Header) then
    Exit;
  if (FieldIdx < 1) or (FieldIdx > Header.FieldCount) then
    Exit;

  ValueTrim := UpperStr(TrimSpaces(Value));

  Total := DBFFileGetActualRowCount(Dbf);
  if ScanPos >= Total then
    Exit;

  { Allocate buffer for row data }
  GetMem(Buf, Header.RecordSize);

  if not DBFFileSeekToRow(Dbf, ScanPos) then
  begin
    FreeMem(Buf, Header.RecordSize);
    Exit;
  end;
  for RowIndex := ScanPos to Total - 1 do
  begin
    if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then
    begin
      FreeMem(Buf, Header.RecordSize);
      Exit;
    end;
    FieldValue := DBFFieldGetStr(Buf, Header, FieldIdx);
    FieldValue := UpperStr(TrimSpaces(FieldValue));
    if FieldValue = ValueTrim then
    begin
      if Count >= MaxCount then
      begin
        ScanPos := RowIndex;
        FreeMem(Buf, Header.RecordSize);
        DBFFileFindRowsExact := True;
        Exit;
      end;
      RowIds^[Count] := RowIndex;
      Inc(Count);
    end;
  end;
  ScanPos := Total;
  FreeMem(Buf, Header.RecordSize);
  DBFFileFindRowsExact := True;
end;

function DBFFileFindRowsExactNum(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: LongInt; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;
var
  Header: TDBFHeader;
  Buf: Pointer;
  RowIndex: LongInt;
  Total: LongInt;
  FieldValue: string;
  Num: LongInt;
  Code: Integer;
begin
  DBFFileFindRowsExactNum := False;
  Count := 0;
  if Dbf = nil then
    Exit;
  if RowIds = nil then
    Exit;
  if MaxCount <= 0 then
    Exit;
  if ScanPos < 0 then
    ScanPos := 0;

  if not DBFFileGetHeader(Dbf, Header) then
    Exit;
  if (FieldIdx < 1) or (FieldIdx > Header.FieldCount) then
    Exit;

  Total := DBFFileGetActualRowCount(Dbf);
  if ScanPos >= Total then
    Exit;

  { Allocate buffer for row data }
  GetMem(Buf, Header.RecordSize);

  if not DBFFileSeekToRow(Dbf, ScanPos) then
  begin
    FreeMem(Buf, Header.RecordSize);
    Exit;
  end;
  for RowIndex := ScanPos to Total - 1 do
  begin
    if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then
    begin
      FreeMem(Buf, Header.RecordSize);
      Exit;
    end;
    FieldValue := DBFFieldGetStr(Buf, Header, FieldIdx);
    FieldValue := TrimSpaces(FieldValue);
    if FieldValue <> '' then
    begin
      Val(FieldValue, Num, Code);
      if (Code = 0) and (Num = Value) then
      begin
        if Count >= MaxCount then
        begin
          ScanPos := RowIndex;
          FreeMem(Buf, Header.RecordSize);
          DBFFileFindRowsExactNum := True;
          Exit;
        end;
        RowIds^[Count] := RowIndex;
        Inc(Count);
      end;
    end;
  end;
  ScanPos := Total;
  FreeMem(Buf, Header.RecordSize);
  DBFFileFindRowsExactNum := True;
end;

function DBFFileFindRowsInRangeNum(var Dbf: PDBFFile; FieldIdxMin: Integer;
  FieldIdxMax: Integer; Value: LongInt; RowIds: PRowIdArray;
  MaxCount: Integer; var Count: Integer; var ScanPos: LongInt): Boolean;
var
  Header: TDBFHeader;
  Buf: Pointer;
  RowIndex: LongInt;
  Total: LongInt;
  MinStr, MaxStr: string;
  MinVal, MaxVal: LongInt;
  CodeMin, CodeMax: Integer;
begin
  DBFFileFindRowsInRangeNum := False;
  Count := 0;
  if Dbf = nil then
    Exit;
  if RowIds = nil then
    Exit;
  if MaxCount <= 0 then
    Exit;

  if not DBFFileGetHeader(Dbf, Header) then
    Exit;
  if (FieldIdxMin < 1) or (FieldIdxMin > Header.FieldCount) then
    Exit;
  if (FieldIdxMax < 1) or (FieldIdxMax > Header.FieldCount) then
    Exit;

  Total := DBFFileGetActualRowCount(Dbf);
  if ScanPos >= Total then
    Exit;

  { Allocate buffer for row data }
  GetMem(Buf, Header.RecordSize);

  if not DBFFileSeekToRow(Dbf, ScanPos) then
  begin
    FreeMem(Buf, Header.RecordSize);
    Exit;
  end;
  for RowIndex := ScanPos to Total - 1 do
  begin
    if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then
    begin
      FreeMem(Buf, Header.RecordSize);
      Exit;
    end;
    MinStr := TrimSpaces(DBFFieldGetStr(Buf, Header, FieldIdxMin));
    MaxStr := TrimSpaces(DBFFieldGetStr(Buf, Header, FieldIdxMax));

    MinVal := 0;
    MaxVal := 0;
    CodeMin := 1;
    CodeMax := 1;
    if MinStr <> '' then
      Val(MinStr, MinVal, CodeMin);
    if MaxStr <> '' then
      Val(MaxStr, MaxVal, CodeMax);

    if (CodeMin = 0) and (CodeMax = 0) then
    begin
      if not ((MinVal = 0) and (MaxVal = 0)) then
      begin
        if MinVal = 0 then
          MinVal := MaxVal;
        if MaxVal = 0 then
          MaxVal := MinVal;

        if (Value >= MinVal) and (Value <= MaxVal) then
        begin
          if Count >= MaxCount then
          begin
            ScanPos := RowIndex;
            FreeMem(Buf, Header.RecordSize);
            DBFFileFindRowsInRangeNum := True;
            Exit;
          end;
          RowIds^[Count] := RowIndex;
          Inc(Count);
        end;
      end;
    end;
  end;
  ScanPos := Total;
  FreeMem(Buf, Header.RecordSize);
  DBFFileFindRowsInRangeNum := True;
end;

function DBFFileFindRowsStartsWith(var Dbf: PDBFFile; FieldIdx: Integer;
  Prefix: string; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;
var
  Header: TDBFHeader;
  Buf: Pointer;
  RowIndex: LongInt;
  Total: LongInt;
  FieldValue: string;
  PrefixTrim: string;
begin
  DBFFileFindRowsStartsWith := False;
  Count := 0;
  if Dbf = nil then
    Exit;
  if RowIds = nil then
    Exit;
  if MaxCount <= 0 then
    Exit;

  if not DBFFileGetHeader(Dbf, Header) then
    Exit;
  if (FieldIdx < 1) or (FieldIdx > Header.FieldCount) then
    Exit;

  PrefixTrim := UpperStr(TrimSpaces(Prefix));
  if PrefixTrim = '' then
    Exit;

  Total := DBFFileGetActualRowCount(Dbf);
  if ScanPos >= Total then
    Exit;

  { Allocate buffer for row data }
  GetMem(Buf, Header.RecordSize);

  if not DBFFileSeekToRow(Dbf, ScanPos) then
  begin
    FreeMem(Buf, Header.RecordSize);
    Exit;
  end;
  for RowIndex := ScanPos to Total - 1 do
  begin
    if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then
    begin
      FreeMem(Buf, Header.RecordSize);
      Exit;
    end;
    FieldValue := DBFFieldGetStr(Buf, Header, FieldIdx);
    FieldValue := UpperStr(TrimSpaces(FieldValue));
    if Copy(FieldValue, 1, Length(PrefixTrim)) = PrefixTrim then
    begin
      if Count >= MaxCount then
      begin
        ScanPos := RowIndex;
        FreeMem(Buf, Header.RecordSize);
        DBFFileFindRowsStartsWith := True;
        Exit;
      end;
      RowIds^[Count] := RowIndex;
      Inc(Count);
    end;
  end;
  ScanPos := Total;
  FreeMem(Buf, Header.RecordSize);
  DBFFileFindRowsStartsWith := True;
end;

end.
