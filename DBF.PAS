unit DBF;

{ TODO: Discuss a common libary for creating indexes (separate from this file) }
{ string IDX files, multi-field index (trucated string) }

interface

type
  TDBFColumn = record
    Name: string[11];   { Field name (max 11 chars) }
    FieldType: Char;    { 'C', 'N', 'L', etc. }
    Length: Byte;       { Field length in bytes }
    Decimals: Byte;     { Number of decimal places (for numeric) }
    Offset: Word;       { offset within record; first field starts at 1 }
  end;

const
  DBFMaxFields = 64;
  DBFMaxRecordSize = 4096;
  DBFMaxRowIds = 2000;
  DBFLangUS = $01;
  DBFLangWesternEurope = $02;
  DBFLangJapan = $7B;
  DBFMemoBlockSize = 512;

type
  TDBFHeader = record
    Version: Byte;                { dBase version, e.g., $03 for dBase III }
    Year: Byte;                   { Last update year (since 1900) }
    Month: Byte;                  { Last update month }
    Day: Byte;                    { Last update day }
    RecordCount: LongInt;         { Number of records }
    HeaderSize: Word;             { Header size in bytes }
    RecordSize: Word;             { Record size in bytes }
    TableFlags: Byte;             { dBase IV table flags }
    LanguageDriver: Byte;         { dBase IV language driver id }
    Fields: array[1..DBFMaxFields] of TDBFColumn; { Field descriptors }
    FieldCount: Integer;          { Actual number of fields used }
  end;

  TDBFValues = array[1..DBFMaxFields] of string[255];
  TDBFRow = array[0..DBFMaxRecordSize - 1] of Byte;
  TDBFRowIdArray = array[0..DBFMaxRowIds - 1] of LongInt;
  TMemoWriteState = record
    F: File;
    Open: Boolean;
    StartBlock: LongInt;
    TotalLen: LongInt;
    Written: LongInt;
  end;
  PDBFFile = Pointer;

{ Internal helpers are in the implementation section to avoid external bypass. }

procedure DBFFileOpen(var Dbf: PDBFFile; FileName: string);
procedure DBFFileCreate(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader);
procedure DBFFileCreateDBase3(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader);
procedure DBFFileClose(var Dbf: PDBFFile);
procedure DBFFileDispose(var Dbf: PDBFFile);
function DBFFileGetHeader(var Dbf: PDBFFile; var Header: TDBFHeader): Boolean;
procedure DBFFileReadRow(var Dbf: PDBFFile; var Buf: TDBFRow);
procedure DBFFileWriteRow(var Dbf: PDBFFile; Values: TDBFValues);
procedure DBFFileSeekToRow(var Dbf: PDBFFile; RowIndex: LongInt);
procedure DBFFileSeekToFirstRow(var Dbf: PDBFFile);
procedure DBFFileSeekToEnd(var Dbf: PDBFFile);
function DBFFileGetFieldStr(var Buf: TDBFRow; var Dbf: PDBFFile;
  FieldIdx: Integer): string;
procedure DBFFileSetFieldStr(var Buf: TDBFRow; var Dbf: PDBFFile;
  FieldIdx: Integer; Value: string);
function DBFFileGetActualRowCount(var Dbf: PDBFFile): LongInt;
procedure DBFFileGetDate(var Dbf: PDBFFile; var Year, Month, Day: Byte);
procedure DBFFileSetDate(var Dbf: PDBFFile; Year, Month, Day: Byte);
function DBFFileIsDateOlder(var Dbf: PDBFFile; Year, Month, Day: Byte): Boolean;
procedure DBFFileGetLanguageDriver(var Dbf: PDBFFile; var Lang: Byte);
procedure DBFFileSetLanguageDriver(var Dbf: PDBFFile; Lang: Byte);
procedure DBFFileFindRowsExact(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: string; var RowIds: TDBFRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt);
procedure DBFFileFindRowsExactNum(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: LongInt; var RowIds: TDBFRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt);
procedure DBFFileFindRowsInRangeNum(var Dbf: PDBFFile; FieldIdxMin: Integer;
  FieldIdxMax: Integer; Value: LongInt; var RowIds: TDBFRowIdArray;
  MaxCount: Integer; var Count: Integer; var ScanPos: LongInt);
procedure DBFFileFindRowsStartsWith(var Dbf: PDBFFile; FieldIdx: Integer;
  Prefix: string; var RowIds: TDBFRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt);
procedure DBFFileAppendRow(var Dbf: PDBFFile; Values: TDBFValues);
procedure DBFFileSetRowDeleted(var Dbf: PDBFFile; RowIndex: LongInt; Deleted: Boolean);
procedure DBFFileClearMemoFields(var Dbf: PDBFFile);
procedure DBFMemoWrite(MemoFileName: string; MemoType: LongInt; Text: string;
  var StartBlock: LongInt);
procedure DBFMemoWriteBuffer(MemoFileName: string; MemoType: LongInt;
  var Buf; Len: LongInt; var StartBlock: LongInt);
procedure DBFMemoWriteBegin(MemoFileName: string; MemoType: LongInt;
  TotalLen: LongInt; var StartBlock: LongInt; var State: TMemoWriteState);
procedure DBFMemoWriteChunk(var State: TMemoWriteState; var Buf; Len: Word);
procedure DBFMemoWriteEnd(var State: TMemoWriteState);
procedure DBFMemoWriteBeginAtBlock(MemoFileName: string; MemoType: LongInt;
  TotalLen: LongInt; StartBlock: LongInt; var State: TMemoWriteState);
procedure DBFMemoWriteEndAtBlock(var State: TMemoWriteState);
function DBFMemoGetInfo(MemoFileName: string; StartBlock: LongInt;
  var MemoType: LongInt; var Len: LongInt): Boolean;
function DBFMemoReadChunk(MemoFileName: string; StartBlock: LongInt;
  Offset: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;
function DBFMemoReadSmall(MemoFileName: string; StartBlock: LongInt;
  var MemoType: LongInt; var Text: string): Boolean;
function DBFMemoReadBuffer(MemoFileName: string; StartBlock: LongInt;
  var MemoType: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;

function TrimString(T: string): string;
function PadString(S: string; Len: Integer): string;
function ParseInt(T: string): LongInt;
function ParseWord(T: string): Word;
function ParseByte(T: string): Byte;
function ParseBool(T: string): Boolean;

procedure ExportDBFToText(FileName: string);
procedure ImportDBFFromText(FileName: string);
procedure ExportDBFMemosToText(FileName: string);
procedure ImportDBFMemosFromText(FileName: string);
procedure ImportDBFMemosFromTextEx(FileName: string; PreserveBlocks: Boolean);
procedure CompactDBF(InFileName, OutFileName: string);
procedure DBFFileBuildNDX(var Dbf: PDBFFile; FieldName: string);

implementation

type
  TByteArray = array[0..65520] of Byte;
  PByteArray = ^TByteArray;
  TDBFFile = record
    F: File;
    Header: TDBFHeader;
    IsOpen: Boolean;
  end;
  PInternalDBFFile = ^TDBFFile;

const
  DebugMemoImport = True;
  NDXBlockSize = 512;
  NDXMaxKeyLen = 80;
  NDXMaxKeys = 64;

function ReadFieldStr(P: Pointer; Len: Integer): string;
var
  T: string[255];
  I: Integer;
begin
  T := '';
  for I := 0 to Len - 1 do
    T := T + Chr(PByteArray(P)^[I]);
  while (Length(T) > 0) and (T[Length(T)] = ' ') do
    Delete(T, Length(T), 1);
  ReadFieldStr := T;
end;

function ReadFieldNum(P: Pointer; Len: Integer): LongInt;
var
  T: string;
  V: LongInt;
  Code: Integer;
begin
  T := ReadFieldStr(P, Len);
  V := 0;
  Val(T, V, Code);
  ReadFieldNum := V;
end;

function ReadFieldWord(P: Pointer; Len: Integer): Word;
var
  T: string;
  V: LongInt;
  Code: Integer;
begin
  T := ReadFieldStr(P, Len);
  V := 0;
  Val(T, V, Code);
  ReadFieldWord := V;
end;

function ReadFieldByte(P: Pointer; Len: Integer): Byte;
var
  T: string;
  V: LongInt;
  Code: Integer;
begin
  T := ReadFieldStr(P, Len);
  V := 0;
  Val(T, V, Code);
  ReadFieldByte := V;
end;


function UpperStr(S: string): string;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    S[I] := UpCase(S[I]);
  UpperStr := S;
end;

function LowerStr(S: string): string;
var
  I: Integer;
  C: Char;
begin
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (C >= 'A') and (C <= 'Z') then
      S[I] := Chr(Ord(C) + 32);
  end;
  LowerStr := S;
end;

  function TrimString(T: string): string;
  var
    L, R: Integer;
  begin
    L := 1;
    R := Length(T);
    while (L <= R) and (T[L] = ' ') do
      Inc(L);
    while (R >= L) and (T[R] = ' ') do
      Dec(R);
    if L > R then
      TrimString := ''
    else
      TrimString := Copy(T, L, R - L + 1);
  end;

function TrimSpaces(S: string): string;
begin
  TrimSpaces := TrimString(S);
end;
  function ParseInt(T: string): LongInt;
  var
    V: LongInt;
    Code: Integer;
  begin
    Val(TrimString(T), V, Code);
    if Code <> 0 then
      ParseInt := 0
    else
      ParseInt := V;
  end;
  function ParseWord(T: string): Word;
  var
    W: Word;
    Code: Integer;
  begin
    Val(TrimString(T), W, Code);
    if Code <> 0 then
      W := 0;
    ParseWord := W;
  end;
  function ParseByte(T: string): Byte;
  var
    B: Integer;
    Code: Integer;
  begin
    Val(TrimString(T), B, Code);
    if Code <> 0 then
      B := 0;
    ParseByte := B;
  end;
  function ParseBool(T: string): Boolean;
  var
    C: Char;
  begin
    T := TrimString(T);
    if Length(T) = 0 then
      ParseBool := False
    else
    begin
      C := UpCase(T[1]);
      ParseBool := (C = 'T') or (C = 'Y') or (C = '1');
    end;
  end;

function PadString(S: string; Len: Integer): string;
begin
  while Length(S) < Len do
    S := S + ' ';
  if Length(S) > Len then
    S := Copy(S, 1, Len);
  PadString := S;
end;

function IntToStrLocal(Value: Integer): string;
var
  S: string;
begin
  Str(Value, S);
  IntToStrLocal := S;
end;

function BuildFieldSpec(Field: TDBFColumn): string;
var
  S: string;
begin
  S := Field.FieldType + '(' + IntToStrLocal(Field.Length);
  if Field.Decimals > 0 then
    S := S + ',' + IntToStrLocal(Field.Decimals);
  S := S + ')';
  BuildFieldSpec := S;
end;

function ParseFieldSpec(S: string; var FieldType: Char; var Len: Byte; var Dec: Byte): Boolean;
var
  P1, P2, PComma: Integer;
  NumStr: string;
  LVal, DVal: Integer;
  Code: Integer;
begin
  ParseFieldSpec := False;
  S := TrimString(S);
  if Length(S) < 3 then
    Exit;
  FieldType := UpCase(S[1]);
  P1 := Pos('(', S);
  P2 := Pos(')', S);
  if (P1 = 0) or (P2 = 0) or (P2 <= P1 + 1) then
    Exit;
  NumStr := Copy(S, P1 + 1, P2 - P1 - 1);
  PComma := Pos(',', NumStr);
  if PComma > 0 then
  begin
    Val(Copy(NumStr, 1, PComma - 1), LVal, Code);
    if Code <> 0 then
      Exit;
    Val(Copy(NumStr, PComma + 1, Length(NumStr)), DVal, Code);
    if Code <> 0 then
      Exit;
  end
  else
  begin
    Val(NumStr, LVal, Code);
    if Code <> 0 then
      Exit;
    DVal := 0;
  end;
  if (LVal <= 0) or (LVal > 255) then
    Exit;
  Len := LVal;
  Dec := DVal;
  ParseFieldSpec := True;
end;

function HasMemoField(var Header: TDBFHeader): Boolean;
var
  I: Integer;
begin
  HasMemoField := False;
  for I := 1 to Header.FieldCount do
    if UpCase(Header.Fields[I].FieldType) = 'M' then
    begin
      HasMemoField := True;
      Exit;
    end;
end;

procedure InitDBFHeader(var Header: TDBFHeader);
var
  I: Integer;
  Offs: Word;
  HasMemo: Boolean;
begin
  HasMemo := HasMemoField(Header);
  Header.TableFlags := 0;
  Header.LanguageDriver := DBFLangUS;
  if Header.Version = 0 then
  begin
    if HasMemo then
      Header.Version := $05
    else
      Header.Version := $04;
  end
  else if (Header.Version = $04) and HasMemo then
    Header.Version := $05
  else if (Header.Version = $05) and (not HasMemo) then
    Header.Version := $04;
  Header.RecordCount := 0;
  Offs := 1;
  for I := 1 to Header.FieldCount do
  begin
    Header.Fields[I].Offset := Offs;
    Inc(Offs, Header.Fields[I].Length);
  end;
  Header.RecordSize := Offs;
  Header.HeaderSize := 32 + (Header.FieldCount * 32) + 1;
end;

procedure WriteDBFHeader(var F: File; Header: TDBFHeader);
var
  I, J: Integer;
  Buf: array[1..32] of Byte;
begin
  { Write main file header (32 bytes) }
  FillChar(Buf, SizeOf(Buf), 0);
  Buf[1] := Header.Version;
  Buf[2] := Header.Year;
  Buf[3] := Header.Month;
  Buf[4] := Header.Day;
  Buf[5] := Header.RecordCount and $FF;
  Buf[6] := (Header.RecordCount shr 8) and $FF;
  Buf[7] := (Header.RecordCount shr 16) and $FF;
  Buf[8] := (Header.RecordCount shr 24) and $FF;
  Buf[9] := Header.HeaderSize and $FF;
  Buf[10] := (Header.HeaderSize shr 8) and $FF;
  Buf[11] := Header.RecordSize and $FF;
  Buf[12] := (Header.RecordSize shr 8) and $FF;
  Buf[29] := Header.TableFlags;
  Buf[30] := Header.LanguageDriver;
  BlockWrite(F, Buf, 32);

  { Write field descriptors (32 bytes each) }
  for I := 1 to Header.FieldCount do
  begin
    FillChar(Buf, SizeOf(Buf), 0);
    for J := 1 to Length(Header.Fields[I].Name) do
      Buf[J] := Ord(Header.Fields[I].Name[J]);
    Buf[12] := Ord(Header.Fields[I].FieldType);
    Buf[17] := Header.Fields[I].Length;
    Buf[18] := Header.Fields[I].Decimals;
    BlockWrite(F, Buf, 32);
  end;

  { Field descriptor terminator (0x0D) }
  Buf[1] := $0D;
  BlockWrite(F, Buf, 1);

  { Write file terminator (0x1A) to indicate no rows }
  Buf[1] := $1A;
  BlockWrite(F, Buf, 1);
end;

procedure UpdateDBFRecordCount(var F: File; NewCount: LongInt);
var
  Buf: array[1..4] of Byte;
  OldPos: LongInt;
begin
  OldPos := FilePos(F);

  { Seek to record count offset (byte 4, zero-based) }
  Seek(F, 4);
  Buf[1] := NewCount and $FF;
  Buf[2] := (NewCount shr 8) and $FF;
  Buf[3] := (NewCount shr 16) and $FF;
  Buf[4] := (NewCount shr 24) and $FF;
  BlockWrite(F, Buf, 4);

  Seek(F, OldPos);
end;

procedure UpdateDBFHeaderDate(var F: File; Year, Month, Day: Byte);
var
  Buf: array[1..3] of Byte;
  OldPos: LongInt;
begin
  OldPos := FilePos(F);
  Seek(F, 1);
  Buf[1] := Year;
  Buf[2] := Month;
  Buf[3] := Day;
  BlockWrite(F, Buf, 3);
  Seek(F, OldPos);
end;

procedure UpdateDBFLanguageDriver(var F: File; Lang: Byte);
var
  OldPos: LongInt;
begin
  OldPos := FilePos(F);
  Seek(F, 29);
  BlockWrite(F, Lang, 1);
  Seek(F, OldPos);
end;

procedure WriteLongIntLE(var F: File; Value: LongInt);
var
  Buf: array[1..4] of Byte;
begin
  Buf[1] := Value and $FF;
  Buf[2] := (Value shr 8) and $FF;
  Buf[3] := (Value shr 16) and $FF;
  Buf[4] := (Value shr 24) and $FF;
  BlockWrite(F, Buf, 4);
end;

function ReadLongIntLE(var F: File): LongInt;
var
  Buf: array[1..4] of Byte;
begin
  BlockRead(F, Buf, 4);
  ReadLongIntLE := Buf[1] + (Buf[2] shl 8) + (Buf[3] shl 16) + (Buf[4] shl 24);
end;

procedure MemoInitFile(var F: File);
var
  Buf: array[1..DBFMemoBlockSize] of Byte;
  NextFree: LongInt;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  NextFree := 1;
  Buf[1] := NextFree and $FF;
  Buf[2] := (NextFree shr 8) and $FF;
  Buf[3] := (NextFree shr 16) and $FF;
  Buf[4] := (NextFree shr 24) and $FF;
  Buf[5] := DBFMemoBlockSize and $FF;
  Buf[6] := (DBFMemoBlockSize shr 8) and $FF;
  BlockWrite(F, Buf, DBFMemoBlockSize);
end;

function MemoReadHeader(var F: File; var NextFree: LongInt): Boolean;
var
  Buf: array[1..DBFMemoBlockSize] of Byte;
begin
  if FileSize(F) < DBFMemoBlockSize then
  begin
    MemoReadHeader := False;
    Exit;
  end;
  Seek(F, 0);
  BlockRead(F, Buf, DBFMemoBlockSize);
  NextFree := Buf[1] + (Buf[2] shl 8) + (Buf[3] shl 16) + (Buf[4] shl 24);
  if NextFree < 1 then
    NextFree := 1;
  MemoReadHeader := True;
end;

procedure MemoUpdateNextFree(var F: File; NextFree: LongInt);
begin
  Seek(F, 0);
  WriteLongIntLE(F, NextFree);
end;

procedure MemoWriteZeros(var F: File; Len: LongInt);
var
  Zeros: array[1..DBFMemoBlockSize] of Byte;
begin
  if Len <= 0 then
    Exit;
  FillChar(Zeros, SizeOf(Zeros), 0);
  while Len > 0 do
  begin
    if Len >= DBFMemoBlockSize then
      BlockWrite(F, Zeros, DBFMemoBlockSize)
    else
      BlockWrite(F, Zeros, Len);
    Dec(Len, DBFMemoBlockSize);
  end;
end;

procedure DBFMemoWriteBegin(MemoFileName: string; MemoType: LongInt;
  TotalLen: LongInt; var StartBlock: LongInt; var State: TMemoWriteState);
var
  Res: Integer;
  NextFree: LongInt;
  StartPos: LongInt;
begin
  StartBlock := 0;
  State.Open := False;
  State.StartBlock := 0;
  State.TotalLen := 0;
  State.Written := 0;
  if TotalLen < 0 then
    TotalLen := 0;
  Assign(State.F, MemoFileName);
  {$I-}
  Reset(State.F, 1);
  Res := IOResult;
  {$I+}
  if Res <> 0 then
  begin
    Rewrite(State.F, 1);
    MemoInitFile(State.F);
  end;

  if not MemoReadHeader(State.F, NextFree) then
  begin
    Seek(State.F, 0);
    MemoInitFile(State.F);
    NextFree := 1;
  end;

  StartBlock := NextFree;
  StartPos := StartBlock * DBFMemoBlockSize;
  Seek(State.F, StartPos);
  WriteLongIntLE(State.F, MemoType);
  WriteLongIntLE(State.F, TotalLen);
  State.Open := True;
  State.StartBlock := StartBlock;
  State.TotalLen := TotalLen;
  State.Written := 0;
end;

procedure DBFMemoWriteChunk(var State: TMemoWriteState; var Buf; Len: Word);
var
  ToWrite: Word;
begin
  if (not State.Open) or (Len = 0) then
    Exit;
  if State.Written >= State.TotalLen then
    Exit;
  ToWrite := Len;
  if (State.Written + ToWrite) > State.TotalLen then
    ToWrite := State.TotalLen - State.Written;
  BlockWrite(State.F, Buf, ToWrite);
  Inc(State.Written, ToWrite);
end;

procedure DBFMemoWriteEnd(var State: TMemoWriteState);
var
  Remaining: LongInt;
  TotalLen: LongInt;
  BlocksNeeded: LongInt;
  PadLen: LongInt;
  NextFree: LongInt;
  Ch: Char;
begin
  if not State.Open then
    Exit;

  Remaining := State.TotalLen - State.Written;
  if Remaining > 0 then
    MemoWriteZeros(State.F, Remaining);

  Ch := Chr($1A);
  BlockWrite(State.F, Ch, 1);

  TotalLen := 8 + State.TotalLen + 1;
  BlocksNeeded := (TotalLen + DBFMemoBlockSize - 1) div DBFMemoBlockSize;
  PadLen := (BlocksNeeded * DBFMemoBlockSize) - TotalLen;
  MemoWriteZeros(State.F, PadLen);

  NextFree := State.StartBlock + BlocksNeeded;
  MemoUpdateNextFree(State.F, NextFree);
  Close(State.F);
  State.Open := False;
end;

procedure DBFMemoWriteBeginAtBlock(MemoFileName: string; MemoType: LongInt;
  TotalLen: LongInt; StartBlock: LongInt; var State: TMemoWriteState);
var
  Res: Integer;
  NextFree: LongInt;
  StartPos: LongInt;
  TotalBytes: LongInt;
  BlocksNeeded: LongInt;
  FileLen: LongInt;
  MinSize: LongInt;
begin
  State.Open := False;
  State.StartBlock := 0;
  State.TotalLen := 0;
  State.Written := 0;
  if TotalLen < 0 then
    TotalLen := 0;
  if StartBlock < 1 then
    StartBlock := 1;
  Assign(State.F, MemoFileName);
  {$I-}
  Reset(State.F, 1);
  Res := IOResult;
  {$I+}
  if Res <> 0 then
  begin
    Rewrite(State.F, 1);
    MemoInitFile(State.F);
  end;

  if not MemoReadHeader(State.F, NextFree) then
  begin
    Seek(State.F, 0);
    MemoInitFile(State.F);
    NextFree := 1;
  end;
  if DebugMemoImport then
    WriteLn('MEMO DBG: begin at block=', StartBlock, ' type=', MemoType, ' len=', TotalLen, ' nextfree=', NextFree);

  TotalBytes := 8 + TotalLen + 1;
  BlocksNeeded := (TotalBytes + DBFMemoBlockSize - 1) div DBFMemoBlockSize;
  MinSize := (StartBlock + BlocksNeeded) * DBFMemoBlockSize;
  FileLen := FileSize(State.F);
  if FileLen < MinSize then
  begin
    Seek(State.F, FileLen);
    MemoWriteZeros(State.F, MinSize - FileLen);
  end;

  StartPos := StartBlock * DBFMemoBlockSize;
  Seek(State.F, StartPos);
  WriteLongIntLE(State.F, MemoType);
  WriteLongIntLE(State.F, TotalLen);
  State.Open := True;
  State.StartBlock := StartBlock;
  State.TotalLen := TotalLen;
  State.Written := 0;
end;

procedure DBFMemoWriteEndAtBlock(var State: TMemoWriteState);
var
  Remaining: LongInt;
  TotalLen: LongInt;
  BlocksNeeded: LongInt;
  PadLen: LongInt;
  NextFree: LongInt;
  CurrentNextFree: LongInt;
  Ch: Char;
begin
  if not State.Open then
    Exit;

  Remaining := State.TotalLen - State.Written;
  if Remaining > 0 then
    MemoWriteZeros(State.F, Remaining);

  Ch := Chr($1A);
  BlockWrite(State.F, Ch, 1);

  TotalLen := 8 + State.TotalLen + 1;
  BlocksNeeded := (TotalLen + DBFMemoBlockSize - 1) div DBFMemoBlockSize;
  PadLen := (BlocksNeeded * DBFMemoBlockSize) - TotalLen;
  MemoWriteZeros(State.F, PadLen);

  if MemoReadHeader(State.F, CurrentNextFree) then
  begin
    NextFree := State.StartBlock + BlocksNeeded;
    if NextFree > CurrentNextFree then
      MemoUpdateNextFree(State.F, NextFree);
  end;
  if DebugMemoImport then
    WriteLn('MEMO DBG: end at block=', State.StartBlock, ' blocks=', BlocksNeeded, ' nextfree=', NextFree);

  Close(State.F);
  State.Open := False;
end;

procedure DBFMemoWriteBuffer(MemoFileName: string; MemoType: LongInt;
  var Buf; Len: LongInt; var StartBlock: LongInt);
var
  F: File;
  Res: Integer;
  NextFree: LongInt;
  StartPos: LongInt;
  TotalLen: LongInt;
  BlocksNeeded: LongInt;
  PadLen: LongInt;
  Zeros: array[1..DBFMemoBlockSize] of Byte;
  Ch: Char;
begin
  StartBlock := 0;
  if Len < 0 then
    Len := 0;
  Assign(F, MemoFileName);
  {$I-}
  Reset(F, 1);
  Res := IOResult;
  {$I+}
  if Res <> 0 then
  begin
    Rewrite(F, 1);
    MemoInitFile(F);
  end;

  if not MemoReadHeader(F, NextFree) then
  begin
    Seek(F, 0);
    MemoInitFile(F);
    NextFree := 1;
  end;

  StartBlock := NextFree;
  StartPos := StartBlock * DBFMemoBlockSize;
  Seek(F, StartPos);
  WriteLongIntLE(F, MemoType);
  WriteLongIntLE(F, Len);
  if Len > 0 then
    BlockWrite(F, Buf, Len);
  Ch := Chr($1A);
  BlockWrite(F, Ch, 1);

  TotalLen := 8 + Len + 1;
  BlocksNeeded := (TotalLen + DBFMemoBlockSize - 1) div DBFMemoBlockSize;
  PadLen := (BlocksNeeded * DBFMemoBlockSize) - TotalLen;
  MemoWriteZeros(F, PadLen);

  NextFree := StartBlock + BlocksNeeded;
  MemoUpdateNextFree(F, NextFree);
  Close(F);
end;

procedure DBFMemoWrite(MemoFileName: string; MemoType: LongInt; Text: string;
  var StartBlock: LongInt);
var
  Dummy: Byte;
begin
  if Length(Text) > 0 then
    DBFMemoWriteBuffer(MemoFileName, MemoType, Text[1], Length(Text), StartBlock)
  else
    DBFMemoWriteBuffer(MemoFileName, MemoType, Dummy, 0, StartBlock);
end;

function DBFMemoGetInfo(MemoFileName: string; StartBlock: LongInt;
  var MemoType: LongInt; var Len: LongInt): Boolean;
var
  F: File;
  Res: Integer;
  StartPos: LongInt;
  MemoLen: LongInt;
begin
  MemoType := 0;
  Len := 0;
  DBFMemoGetInfo := False;
  if StartBlock <= 0 then
    Exit;
  Assign(F, MemoFileName);
  {$I-}
  Reset(F, 1);
  Res := IOResult;
  {$I+}
  if Res <> 0 then
    Exit;

  StartPos := StartBlock * DBFMemoBlockSize;
  if FileSize(F) <= StartPos then
  begin
    Close(F);
    Exit;
  end;

  Seek(F, StartPos);
  MemoType := ReadLongIntLE(F);
  MemoLen := ReadLongIntLE(F);
  if MemoLen < 0 then
    MemoLen := 0;
  Len := MemoLen;
  DBFMemoGetInfo := True;
  Close(F);
end;

function DBFMemoReadChunk(MemoFileName: string; StartBlock: LongInt;
  Offset: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;
var
  F: File;
  Res: Integer;
  StartPos: LongInt;
  MemoType: LongInt;
  MemoLen: LongInt;
  ToRead: LongInt;
begin
  ReadLen := 0;
  DBFMemoReadChunk := False;
  if (StartBlock <= 0) or (BufSize = 0) or (Offset < 0) then
    Exit;
  Assign(F, MemoFileName);
  {$I-}
  Reset(F, 1);
  Res := IOResult;
  {$I+}
  if Res <> 0 then
    Exit;

  StartPos := StartBlock * DBFMemoBlockSize;
  if FileSize(F) <= StartPos then
  begin
    Close(F);
    Exit;
  end;

  Seek(F, StartPos);
  MemoType := ReadLongIntLE(F);
  MemoLen := ReadLongIntLE(F);
  if MemoLen < 0 then
    MemoLen := 0;
  if Offset >= MemoLen then
  begin
    Close(F);
    DBFMemoReadChunk := True;
    Exit;
  end;

  Seek(F, StartPos + 8 + Offset);
  ToRead := MemoLen - Offset;
  if ToRead > BufSize then
    ToRead := BufSize;
  BlockRead(F, Buf, ToRead);
  ReadLen := ToRead;
  DBFMemoReadChunk := True;
  Close(F);
end;

function DBFMemoReadSmall(MemoFileName: string; StartBlock: LongInt;
  var MemoType: LongInt; var Text: string): Boolean;
var
  MemoLen: LongInt;
  Buf: array[1..255] of Byte;
  Offset: LongInt;
  ReadLen: Word;
  I: Integer;
  Ok: Boolean;
begin
  Text := '';
  Ok := DBFMemoGetInfo(MemoFileName, StartBlock, MemoType, MemoLen);
  if not Ok then
  begin
    DBFMemoReadSmall := False;
    Exit;
  end;
  if MemoLen > 255 then
    MemoLen := 255;
  Offset := 0;
  while Offset < MemoLen do
  begin
    Ok := DBFMemoReadChunk(MemoFileName, StartBlock, Offset, Buf, SizeOf(Buf), ReadLen);
    if not Ok then
    begin
      DBFMemoReadSmall := False;
      Exit;
    end;
    for I := 1 to ReadLen do
      Text := Text + Chr(Buf[I]);
    Inc(Offset, ReadLen);
    if ReadLen = 0 then
      Offset := MemoLen;
  end;
  DBFMemoReadSmall := True;
end;

function DBFMemoReadBuffer(MemoFileName: string; StartBlock: LongInt;
  var MemoType: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;
var
  MemoLen: LongInt;
  ToRead: Word;
  Ok: Boolean;
begin
  ReadLen := 0;
  Ok := DBFMemoGetInfo(MemoFileName, StartBlock, MemoType, MemoLen);
  if not Ok then
  begin
    DBFMemoReadBuffer := False;
    Exit;
  end;
  if MemoLen < 0 then
    MemoLen := 0;
  if MemoLen > BufSize then
    ToRead := BufSize
  else
    ToRead := MemoLen;
  Ok := DBFMemoReadChunk(MemoFileName, StartBlock, 0, Buf, ToRead, ReadLen);
  DBFMemoReadBuffer := Ok;
end;

procedure WriteDBFRow(var F: File; Header: TDBFHeader; Values: TDBFValues);
var
  I, J, FieldLen: Integer;
  Buf: Pointer;
  S: string[255];
begin
  GetMem(Buf, Header.RecordSize);
  FillChar(Buf^, Header.RecordSize, Ord(' '));
  PByteArray(Buf)^[0] := Ord(' '); { delete flag }
  for I := 1 to Header.FieldCount do
  begin
    FieldLen := Header.Fields[I].Length;
    S := Values[I];
    if Length(S) > FieldLen then
      S := Copy(S, 1, FieldLen);
    while Length(S) < FieldLen do
      S := S + ' ';
    for J := 1 to FieldLen do
      PByteArray(Buf)^[Header.Fields[I].Offset + J - 1] := Ord(S[J]);
  end;
  BlockWrite(F, Buf^, Header.RecordSize);
  FreeMem(Buf, Header.RecordSize);
end;

procedure SetDBFRowDeleted(var F: File; Deleted: Boolean);
var
  Flag: Byte;
begin
  if Deleted then
    Flag := Ord('*')
  else
    Flag := Ord(' ');
  BlockWrite(F, Flag, 1);
end;

procedure ReadDBFHeader(var F: File; var Header: TDBFHeader);
var
  I, J: Integer;
  Buf: array[1..32] of Byte;
  FieldName: string[11];
  Offs: Integer;
  Done: Boolean;
begin
  { Read main file header (32 bytes) }
  BlockRead(F, Buf, 32);
  Header.Version := Buf[1];
  Header.Year := Buf[2];
  Header.Month := Buf[3];
  Header.Day := Buf[4];
  Header.RecordCount := Buf[5] + (Buf[6] shl 8) + (Buf[7] shl 16) + (Buf[8] shl 24);
  Header.HeaderSize := Buf[9] + (Buf[10] shl 8);
  Header.RecordSize := Buf[11] + (Buf[12] shl 8);
  Header.TableFlags := Buf[29];
  Header.LanguageDriver := Buf[30];

  { Read field descriptors until 0x0D (field descriptor terminator) }
  I := 1;
  Done := False;
  while (I <= DBFMaxFields) and not Done do
  begin
    BlockRead(F, Buf, 1); { peek 1 byte }
    if Buf[1] = $0D then
      Done := True
    else
    begin
      Seek(F, FilePos(F) - 1); { rewind 1 byte }
      BlockRead(F, Buf, 32);   { read descriptor }
      FieldName := '';
      for J := 1 to 11 do
        if Buf[J] <> 0 then
          FieldName := FieldName + Chr(Buf[J]);
      Header.Fields[I].Name := FieldName;
      Header.Fields[I].FieldType := Chr(Buf[12]);
      Header.Fields[I].Length := Buf[17];
      Header.Fields[I].Decimals := Buf[18];
      Inc(I);
    end;
  end;
  Header.FieldCount := I - 1;

  Offs := 1;
  for I := 1 to Header.FieldCount do
  begin
    Header.Fields[I].Offset := Offs;
    Inc(Offs, Header.Fields[I].Length);
  end;
  Header.RecordSize := Offs;
end;

procedure ReadDBFRow(var F: File; var Buf: TDBFRow; RecordSize: Integer);
begin
  BlockRead(F, Buf, RecordSize);
end;

function GetFieldStr(var Buf: TDBFRow; Header: TDBFHeader; FieldIdx: Integer): string;
var
  Offs, Len, I: Integer;
  S: string[255];
begin
  Offs := Header.Fields[FieldIdx].Offset;
  Len := Header.Fields[FieldIdx].Length;
  S := '';
  for I := 1 to Len do
    S := S + Chr(Buf[Offs + I - 1]);
  GetFieldStr := S;
end;

procedure SetFieldStr(var Buf: TDBFRow; Header: TDBFHeader; FieldIdx: Integer; Value: string);
var
  Offs, Len, I: Integer;
  S: string[255];
begin
  Offs := Header.Fields[FieldIdx].Offset;
  Len := Header.Fields[FieldIdx].Length;
  S := Value;
  if Length(S) > Len then
    S := Copy(S, 1, Len);
  while Length(S) < Len do
    S := S + ' ';
  for I := 1 to Len do
    Buf[Offs + I - 1] := Ord(S[I]);
end;

function GetActualDBFRowCount(var F: File; Header: TDBFHeader): LongInt;
var
  DiskSize: LongInt;
begin
  DiskSize := FileSize(F);
  if Header.RecordSize = 0 then
    GetActualDBFRowCount := 0
  else if DiskSize < Header.HeaderSize then
    GetActualDBFRowCount := 0
  else
    GetActualDBFRowCount := (DiskSize - Header.HeaderSize) div Header.RecordSize;
end;

procedure SeekToFirstRow(var F: File; Header: TDBFHeader);
begin
  Seek(F, Header.HeaderSize);
end;

procedure SeekToEnd(var F: File; Header: TDBFHeader);
var
  Posn: LongInt;
  DiskRecordCount: LongInt;
  RecordCount: LongInt;
begin
  DiskRecordCount := GetActualDBFRowCount(F, Header);
  RecordCount := Header.RecordCount;

  if DiskRecordCount <> RecordCount then
  begin
    RecordCount := DiskRecordCount;
    UpdateDBFRecordCount(F, RecordCount);
  end;
  if RecordCount = 0 then
    Posn := Header.HeaderSize
  else
    Posn := Header.HeaderSize + (RecordCount) * Header.RecordSize;
  Seek(F, Posn);
end;

procedure SeekToRow(var F: File; Header: TDBFHeader; RowIndex: LongInt);
var
  Posn: LongInt;
  DiskRecordCount: LongInt;
  RecordCount: LongInt;
begin
  DiskRecordCount := GetActualDBFRowCount(F, Header);
  RecordCount := Header.RecordCount;

  if DiskRecordCount <> RecordCount then
  begin
    RecordCount := DiskRecordCount;
    UpdateDBFRecordCount(F, RecordCount);
  end;

  if RecordCount <= 0 then
  begin
    Seek(F, Header.HeaderSize);
    Exit;
  end;

  if RowIndex < 0 then
    RowIndex := 0;
  if RowIndex > RecordCount - 1 then
    RowIndex := RecordCount - 1;

  Posn := Header.HeaderSize + RowIndex * Header.RecordSize;
  Seek(F, Posn);
end;

procedure AppendDBFRow(var F: File; var Header: TDBFHeader; Values: TDBFValues);
var
  Terminator: Byte;
begin
  SeekToEnd(F, Header);
  WriteDBFRow(F, Header, Values);
  Inc(Header.RecordCount);
  UpdateDBFRecordCount(F, Header.RecordCount);
  Terminator := $1A;
  BlockWrite(F, Terminator, 1);
end;

procedure DBFFileAlloc(var Dbf: PDBFFile);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    New(P);
    FillChar(P^, SizeOf(TDBFFile), 0);
    Dbf := P;
  end;
end;

procedure DBFFileOpen(var Dbf: PDBFFile; FileName: string);
var
  P: PInternalDBFFile;
begin
  DBFFileAlloc(Dbf);
  P := PInternalDBFFile(Dbf);
  Assign(P^.F, FileName);
  Reset(P^.F, 1);
  ReadDBFHeader(P^.F, P^.Header);
  P^.IsOpen := True;
end;

procedure DBFMemoCreate(FileName: string);
var
  F : File;
begin
  Assign(F, FileName + '.DBT');
  Rewrite(F, 1);
  Close(F);
end;

procedure DBFFileCreate(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader);
var
  P: PInternalDBFFile;
begin
  DBFFileAlloc(Dbf);
  P := PInternalDBFFile(Dbf);
  Assign(P^.F, FileName + '.DBF');
  Rewrite(P^.F, 1);
  InitDBFHeader(Header);
  WriteDBFHeader(P^.F, Header);
  P^.Header := Header;
  P^.IsOpen := True;

  if P^.Header.Version = $05 then
    DBFMemoCreate(FileName);
end;

procedure DBFFileCreateDBase3(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader);
begin
  Header.Version := $03;
  Header.TableFlags := 0;
  Header.LanguageDriver := 0;
  DBFFileCreate(Dbf, FileName, Header);
end;

procedure DBFFileClose(var Dbf: PDBFFile);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  if P^.IsOpen then
    Close(P^.F);
  P^.IsOpen := False;
end;

function DBFFileGetHeader(var Dbf: PDBFFile; var Header: TDBFHeader): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    FillChar(Header, SizeOf(Header), 0);
    DBFFileGetHeader := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  Header := P^.Header;
  DBFFileGetHeader := True;
end;

procedure DBFFileDispose(var Dbf: PDBFFile);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  if P^.IsOpen then
    Close(P^.F);
  Dispose(P);
  Dbf := nil;
end;

procedure DBFFileReadRow(var Dbf: PDBFFile; var Buf: TDBFRow);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  ReadDBFRow(P^.F, Buf, P^.Header.RecordSize);
end;

procedure DBFFileWriteRow(var Dbf: PDBFFile; Values: TDBFValues);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  WriteDBFRow(P^.F, P^.Header, Values);
end;

procedure DBFFileSeekToRow(var Dbf: PDBFFile; RowIndex: LongInt);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  SeekToRow(P^.F, P^.Header, RowIndex);
end;

procedure DBFFileSeekToFirstRow(var Dbf: PDBFFile);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  SeekToFirstRow(P^.F, P^.Header);
end;

procedure DBFFileSeekToEnd(var Dbf: PDBFFile);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  SeekToEnd(P^.F, P^.Header);
end;

function DBFFileGetFieldStr(var Buf: TDBFRow; var Dbf: PDBFFile;
  FieldIdx: Integer): string;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileGetFieldStr := '';
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  DBFFileGetFieldStr := GetFieldStr(Buf, P^.Header, FieldIdx);
end;

procedure DBFFileSetFieldStr(var Buf: TDBFRow; var Dbf: PDBFFile;
  FieldIdx: Integer; Value: string);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  SetFieldStr(Buf, P^.Header, FieldIdx, Value);
end;

function DBFFileGetActualRowCount(var Dbf: PDBFFile): LongInt;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileGetActualRowCount := 0;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  DBFFileGetActualRowCount := GetActualDBFRowCount(P^.F, P^.Header);
end;

procedure DBFFileGetDate(var Dbf: PDBFFile; var Year, Month, Day: Byte);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    Year := 0;
    Month := 0;
    Day := 0;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  Year := P^.Header.Year;
  Month := P^.Header.Month;
  Day := P^.Header.Day;
end;

procedure DBFFileSetDate(var Dbf: PDBFFile; Year, Month, Day: Byte);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  P^.Header.Year := Year;
  P^.Header.Month := Month;
  P^.Header.Day := Day;
  UpdateDBFHeaderDate(P^.F, Year, Month, Day);
end;

procedure DBFFileGetLanguageDriver(var Dbf: PDBFFile; var Lang: Byte);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    Lang := 0;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  Lang := P^.Header.LanguageDriver;
end;

procedure DBFFileSetLanguageDriver(var Dbf: PDBFFile; Lang: Byte);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  P^.Header.LanguageDriver := Lang;
  UpdateDBFLanguageDriver(P^.F, Lang);
end;

function DBFFileIsDateOlder(var Dbf: PDBFFile; Year, Month, Day: Byte): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileIsDateOlder := True;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  if P^.Header.Year < Year then
    DBFFileIsDateOlder := True
  else if P^.Header.Year > Year then
    DBFFileIsDateOlder := False
  else if P^.Header.Month < Month then
    DBFFileIsDateOlder := True
  else if P^.Header.Month > Month then
    DBFFileIsDateOlder := False
  else
    DBFFileIsDateOlder := P^.Header.Day < Day;
end;

procedure DBFFileFindRowsExact(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: string; var RowIds: TDBFRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt);
var
  P: PInternalDBFFile;
  Buf: TDBFRow;
  RowIndex: LongInt;
  Total: LongInt;
  FieldValue: string;
  Offs, Len: Integer;
  ValueTrim: string;
  I: Integer;
begin
  Count := 0;
  if Dbf = nil then
    Exit;
  if MaxCount <= 0 then
    Exit;
  if ScanPos < 0 then
    ScanPos := 0;
  if ScanPos < 0 then
    ScanPos := 0;
  if ScanPos < 0 then
    ScanPos := 0;
  if ScanPos < 0 then
    ScanPos := 0;
  P := PInternalDBFFile(Dbf);
  if (FieldIdx < 1) or (FieldIdx > P^.Header.FieldCount) then
    Exit;

  ValueTrim := UpperStr(TrimSpaces(Value));

  Offs := P^.Header.Fields[FieldIdx].Offset;
  Len := P^.Header.Fields[FieldIdx].Length;

  Total := GetActualDBFRowCount(P^.F, P^.Header);
  if ScanPos >= Total then
    Exit;
  SeekToRow(P^.F, P^.Header, ScanPos);
  for RowIndex := ScanPos to Total - 1 do
  begin
    ReadDBFRow(P^.F, Buf, P^.Header.RecordSize);
    FieldValue := ReadFieldStr(@Buf[Offs], Len);
    FieldValue := UpperStr(TrimSpaces(FieldValue));
    if FieldValue = ValueTrim then
    begin
      if Count >= MaxCount then
      begin
        ScanPos := RowIndex + 1;
        Exit;
      end;
      RowIds[Count] := RowIndex;
      Inc(Count);
    end;
  end;
  ScanPos := Total;
end;

procedure DBFFileFindRowsExactNum(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: LongInt; var RowIds: TDBFRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt);
var
  P: PInternalDBFFile;
  Buf: TDBFRow;
  RowIndex: LongInt;
  Total: LongInt;
  FieldValue: string;
  Offs, Len: Integer;
  Num: LongInt;
  Code: Integer;
begin
  Count := 0;
  if Dbf = nil then
    Exit;
  if MaxCount <= 0 then
    Exit;
  if ScanPos < 0 then
    ScanPos := 0;
  P := PInternalDBFFile(Dbf);
  if (FieldIdx < 1) or (FieldIdx > P^.Header.FieldCount) then
    Exit;

  Offs := P^.Header.Fields[FieldIdx].Offset;
  Len := P^.Header.Fields[FieldIdx].Length;

  Total := GetActualDBFRowCount(P^.F, P^.Header);
  if ScanPos >= Total then
    Exit;
  SeekToRow(P^.F, P^.Header, ScanPos);
  for RowIndex := ScanPos to Total - 1 do
  begin
    ReadDBFRow(P^.F, Buf, P^.Header.RecordSize);
    FieldValue := ReadFieldStr(@Buf[Offs], Len);
    FieldValue := TrimSpaces(FieldValue);
    if FieldValue <> '' then
    begin
      Val(FieldValue, Num, Code);
      if (Code = 0) and (Num = Value) then
      begin
        if Count >= MaxCount then
          Exit;
        RowIds[Count] := RowIndex;
        Inc(Count);
      end;
    end;
  end;
end;

procedure DBFFileFindRowsInRangeNum(var Dbf: PDBFFile; FieldIdxMin: Integer;
  FieldIdxMax: Integer; Value: LongInt; var RowIds: TDBFRowIdArray;
  MaxCount: Integer; var Count: Integer; var ScanPos: LongInt);
var
  P: PInternalDBFFile;
  Buf: TDBFRow;
  RowIndex: LongInt;
  Total: LongInt;
  MinStr, MaxStr: string;
  MinVal, MaxVal: LongInt;
  CodeMin, CodeMax: Integer;
  OffsMin, LenMin, OffsMax, LenMax: Integer;
begin
  Count := 0;
  if Dbf = nil then
    Exit;
  if MaxCount <= 0 then
    Exit;
  P := PInternalDBFFile(Dbf);
  if (FieldIdxMin < 1) or (FieldIdxMin > P^.Header.FieldCount) then
    Exit;
  if (FieldIdxMax < 1) or (FieldIdxMax > P^.Header.FieldCount) then
    Exit;

  OffsMin := P^.Header.Fields[FieldIdxMin].Offset;
  LenMin := P^.Header.Fields[FieldIdxMin].Length;
  OffsMax := P^.Header.Fields[FieldIdxMax].Offset;
  LenMax := P^.Header.Fields[FieldIdxMax].Length;

  Total := GetActualDBFRowCount(P^.F, P^.Header);
  if ScanPos >= Total then
    Exit;
  SeekToRow(P^.F, P^.Header, ScanPos);
  for RowIndex := ScanPos to Total - 1 do
  begin
    ReadDBFRow(P^.F, Buf, P^.Header.RecordSize);
    MinStr := TrimSpaces(ReadFieldStr(@Buf[OffsMin - 1], LenMin));
    MaxStr := TrimSpaces(ReadFieldStr(@Buf[OffsMax - 1], LenMax));

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
            ScanPos := RowIndex + 1;
            Exit;
          end;
          RowIds[Count] := RowIndex;
          Inc(Count);
        end;
      end;
    end;
  end;
  ScanPos := Total;
end;

procedure DBFFileFindRowsStartsWith(var Dbf: PDBFFile; FieldIdx: Integer;
  Prefix: string; var RowIds: TDBFRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt);
var
  P: PInternalDBFFile;
  Buf: TDBFRow;
  RowIndex: LongInt;
  Total: LongInt;
  FieldValue: string;
  Offs, Len: Integer;
  PrefixTrim: string;
begin
  Count := 0;
  if Dbf = nil then
    Exit;
  if MaxCount <= 0 then
    Exit;
  P := PInternalDBFFile(Dbf);
  if (FieldIdx < 1) or (FieldIdx > P^.Header.FieldCount) then
    Exit;

  PrefixTrim := UpperStr(TrimSpaces(Prefix));
  if PrefixTrim = '' then
    Exit;

  Offs := P^.Header.Fields[FieldIdx].Offset;
  Len := P^.Header.Fields[FieldIdx].Length;

  Total := GetActualDBFRowCount(P^.F, P^.Header);
  if ScanPos >= Total then
    Exit;
  SeekToRow(P^.F, P^.Header, ScanPos);
  for RowIndex := ScanPos to Total - 1 do
  begin
    ReadDBFRow(P^.F, Buf, P^.Header.RecordSize);
    FieldValue := ReadFieldStr(@Buf[Offs], Len);
    FieldValue := UpperStr(TrimSpaces(FieldValue));
    if Copy(FieldValue, 1, Length(PrefixTrim)) = PrefixTrim then
    begin
      if Count >= MaxCount then
      begin
        ScanPos := RowIndex + 1;
        Exit;
      end;
      RowIds[Count] := RowIndex;
      Inc(Count);
    end;
  end;
  ScanPos := Total;
end;

procedure DBFFileAppendRow(var Dbf: PDBFFile; Values: TDBFValues);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  AppendDBFRow(P^.F, P^.Header, Values);
end;

procedure DBFFileSetRowDeleted(var Dbf: PDBFFile; RowIndex: LongInt; Deleted: Boolean);
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  SeekToRow(P^.F, P^.Header, RowIndex);
  SetDBFRowDeleted(P^.F, Deleted);
end;

procedure DBFFileClearMemoFields(var Dbf: PDBFFile);
var
  P: PInternalDBFFile;
  RowIndex, RowCount: LongInt;
  ExportRowIndex: LongInt;
  FieldIdx, MemoCount, MemoIdx: Integer;
  MemoFields: array[1..DBFMaxFields] of Integer;
  Buf: TDBFRow;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  MemoCount := 0;
  for FieldIdx := 1 to P^.Header.FieldCount do
    if P^.Header.Fields[FieldIdx].FieldType = 'M' then
    begin
      Inc(MemoCount);
      MemoFields[MemoCount] := FieldIdx;
    end;
  if MemoCount = 0 then
    Exit;
  RowCount := GetActualDBFRowCount(P^.F, P^.Header);
  for RowIndex := 0 to RowCount - 1 do
  begin
    SeekToRow(P^.F, P^.Header, RowIndex);
    ReadDBFRow(P^.F, Buf, P^.Header.RecordSize);
    for MemoIdx := 1 to MemoCount do
      SetFieldStr(Buf, P^.Header, MemoFields[MemoIdx], '0');
    SeekToRow(P^.F, P^.Header, RowIndex);
    BlockWrite(P^.F, Buf, P^.Header.RecordSize);
  end;
end;

type
  TStringArray = array[1..DBFMaxFields] of string[255];
  PStringArray = ^TStringArray;
  PDBFValues = ^TDBFValues;
  TNDXEntry = record
    Key: string[NDXMaxKeyLen];
    Recno: LongInt;
  end;
  TNDXEntryArray = array[0..0] of TNDXEntry;
  PNDXEntryArray = ^TNDXEntryArray;
  TNDXNodeInfo = record
    Block: LongInt;
    MaxKey: string[NDXMaxKeyLen];
  end;
  TNDXNodeInfoArray = array[0..0] of TNDXNodeInfo;
  PNDXNodeInfoArray = ^TNDXNodeInfoArray;
  TNDXChildArray = array[0..NDXMaxKeys] of LongInt;
  TNDXBlock = array[1..NDXBlockSize] of Byte;

procedure SplitPipe(Line: string; var Parts: TStringArray; var Count: Integer);
var
  I: Integer;
  S: string;
begin
  FillChar(Parts, SizeOf(Parts), 0);
  Count := 0;
  S := '';
  for I := 1 to Length(Line) do
  begin
    if Line[I] = '|' then
    begin
      if Count < DBFMaxFields then
      begin
        Inc(Count);
        Parts[Count] := S;
      end;
      S := '';
    end
    else
      S := S + Line[I];
  end;
  if (Count < DBFMaxFields) then
  begin
    Inc(Count);
    Parts[Count] := S;
  end;
end;

procedure SplitPipeValues(Line: string; var Parts: TDBFValues; var Count: Integer);
var
  I: Integer;
  S: string;
begin
  FillChar(Parts, SizeOf(Parts), 0);
  Count := 0;
  S := '';
  for I := 1 to Length(Line) do
  begin
    if Line[I] = '|' then
    begin
      if Count < DBFMaxFields then
      begin
        Inc(Count);
        Parts[Count] := S;
      end;
      S := '';
    end
    else
      S := S + Line[I];
  end;
  if (Count < DBFMaxFields) then
  begin
    Inc(Count);
    Parts[Count] := S;
  end;
end;

procedure SetWordLE(var Buf: TNDXBlock; Pos: Integer; Value: Word);
begin
  Buf[Pos] := Value and $FF;
  Buf[Pos + 1] := (Value shr 8) and $FF;
end;

procedure SetLongIntLE(var Buf: TNDXBlock; Pos: Integer; Value: LongInt);
begin
  Buf[Pos] := Value and $FF;
  Buf[Pos + 1] := (Value shr 8) and $FF;
  Buf[Pos + 2] := (Value shr 16) and $FF;
  Buf[Pos + 3] := (Value shr 24) and $FF;
end;

function MakeNDXFileName(FieldName: string): string;
var
  S: string;
begin
  S := TrimString(FieldName);
  if Length(S) > 8 then
    S := Copy(S, 1, 8);
  S := UpperStr(S);
  MakeNDXFileName := S + '.NDX';
end;

procedure NormalizeKey(var S: string; KeyLen: Integer; DoUpcase: Boolean);
var
  I: Integer;
begin
  if Length(S) > KeyLen then
    S := Copy(S, 1, KeyLen);
  if DoUpcase then
    for I := 1 to Length(S) do
      S[I] := UpCase(S[I]);
  while Length(S) < KeyLen do
    S := S + ' ';
end;

function CompareNDXKey(var A, B: TNDXEntry; KeyLen: Integer): Integer;
var
  I: Integer;
begin
  for I := 1 to KeyLen do
  begin
    if A.Key[I] < B.Key[I] then
    begin
      CompareNDXKey := -1;
      Exit;
    end
    else if A.Key[I] > B.Key[I] then
    begin
      CompareNDXKey := 1;
      Exit;
    end;
  end;
  if A.Recno < B.Recno then
    CompareNDXKey := -1
  else if A.Recno > B.Recno then
    CompareNDXKey := 1
  else
    CompareNDXKey := 0;
end;

procedure QuickSortNDX(var A: TNDXEntryArray; L, R, KeyLen: Integer);
var
  I, J: Integer;
  Pivot: TNDXEntry;
  Temp: TNDXEntry;
begin
  I := L;
  J := R;
  Pivot := A[(L + R) div 2];
  repeat
    while CompareNDXKey(A[I], Pivot, KeyLen) < 0 do
      Inc(I);
    while CompareNDXKey(A[J], Pivot, KeyLen) > 0 do
      Dec(J);
    if I <= J then
    begin
      Temp := A[I];
      A[I] := A[J];
      A[J] := Temp;
      Inc(I);
      Dec(J);
    end;
  until I > J;
  if L < J then
    QuickSortNDX(A, L, J, KeyLen);
  if I < R then
    QuickSortNDX(A, I, R, KeyLen);
end;

procedure WriteNDXNode(var F: File; Block: LongInt; KeyLen, GroupLen: Integer;
  NumKeys: Integer; var Keys: TNDXEntryArray; var Childs: TNDXChildArray;
  UseRecno: Boolean; LastChild: LongInt);
var
  Buf: TNDXBlock;
  I: Integer;
  Offs: Integer;
  Recno: LongInt;
begin
  FillChar(Buf, SizeOf(Buf), 0);
  SetWordLE(Buf, 1, NumKeys);
  SetWordLE(Buf, 3, 0);
  for I := 0 to NumKeys - 1 do
  begin
    Offs := 5 + (I * GroupLen);
    SetLongIntLE(Buf, Offs, Childs[I]);
    if UseRecno then
      Recno := Keys[I].Recno
    else
      Recno := 0;
    SetLongIntLE(Buf, Offs + 4, Recno);
    Move(Keys[I].Key[1], Buf[Offs + 8], KeyLen);
  end;
  Offs := 5 + (NumKeys * GroupLen);
  SetLongIntLE(Buf, Offs, LastChild);
  Seek(F, Block * NDXBlockSize);
  BlockWrite(F, Buf, SizeOf(Buf));
end;

procedure DBFFileBuildNDX(var Dbf: PDBFFile; FieldName: string);
var
  P: PInternalDBFFile;
  FieldIdx: Integer;
  FieldType: Char;
  KeyLen: Integer;
  GroupLen: Integer;
  KeysMax: Integer;
  RowCount: LongInt;
  RowIndex: LongInt;
  Entries: PNDXEntryArray;
  EntryCount: LongInt;
  RowBuf: TDBFRow;
  KeyStr: string;
  NdxName: string;
  F: File;
  LeafCount: LongInt;
  NodeInfos: PNDXNodeInfoArray;
  NextNodeInfos: PNDXNodeInfoArray;
  NodeCount: LongInt;
  NextCount: LongInt;
  Block: LongInt;
  I: Integer;
  StartIdx: LongInt;
  NumKeys: Integer;
  ChildCount: Integer;
  ChildPerNode: Integer;
  KeysBuf: PNDXEntryArray;
  ChildsBuf: TNDXChildArray;
  LastChild: LongInt;
  RootBlock: LongInt;
  EOFBlock: LongInt;
  HeaderBuf: TNDXBlock;
  Expr: string;
  ParentIdx: LongInt;
  ChildIdx: LongInt;
begin
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  FieldIdx := 0;
  I := 1;
  while (I <= P^.Header.FieldCount) and (FieldIdx = 0) do
  begin
    if UpperStr(P^.Header.Fields[I].Name) = UpperStr(FieldName) then
      FieldIdx := I;
    Inc(I);
  end;
  if FieldIdx = 0 then
    Exit;

  FieldType := P^.Header.Fields[FieldIdx].FieldType;
  if (FieldType <> 'C') and (FieldType <> 'D') then
    Exit;
  KeyLen := P^.Header.Fields[FieldIdx].Length;
  if (KeyLen <= 0) or (KeyLen > NDXMaxKeyLen) then
    Exit;

  GroupLen := KeyLen + 8;
  if (GroupLen mod 4) <> 0 then
    GroupLen := GroupLen + (4 - (GroupLen mod 4));
  KeysMax := (NDXBlockSize - 8) div GroupLen;
  if (KeysMax <= 0) or (KeysMax > NDXMaxKeys) then
    Exit;

  RowCount := GetActualDBFRowCount(P^.F, P^.Header);
  if RowCount <= 0 then
    Exit;

  GetMem(Entries, SizeOf(TNDXEntry) * RowCount);
  EntryCount := 0;
  DBFFileSeekToFirstRow(Dbf);
  for RowIndex := 0 to RowCount - 1 do
  begin
    DBFFileReadRow(Dbf, RowBuf);
    if RowBuf[0] <> Ord('*') then
    begin
      KeyStr := GetFieldStr(RowBuf, P^.Header, FieldIdx);
      KeyStr := TrimString(KeyStr);
      NormalizeKey(KeyStr, KeyLen, FieldType = 'C');
      Entries^[EntryCount].Key := KeyStr;
      Entries^[EntryCount].Recno := RowIndex + 1;
      Inc(EntryCount);
    end;
  end;

  NdxName := MakeNDXFileName(FieldName);
  Assign(F, NdxName);
  Rewrite(F, 1);

  if EntryCount = 0 then
  begin
    FillChar(HeaderBuf, SizeOf(HeaderBuf), 0);
    SetLongIntLE(HeaderBuf, 1, 0);
    SetLongIntLE(HeaderBuf, 5, 1);
    SetWordLE(HeaderBuf, 13, KeyLen);
    SetWordLE(HeaderBuf, 15, KeysMax);
    SetWordLE(HeaderBuf, 19, GroupLen);
    Expr := LowerStr(TrimString(FieldName));
    if Length(Expr) > 0 then
      Move(Expr[1], HeaderBuf[25], Length(Expr));
    HeaderBuf[25 + Length(Expr)] := 0;
    Seek(F, 0);
    BlockWrite(F, HeaderBuf, SizeOf(HeaderBuf));
    Close(F);
    FreeMem(Entries, SizeOf(TNDXEntry) * RowCount);
    Exit;
  end;

  QuickSortNDX(Entries^, 0, EntryCount - 1, KeyLen);

  GetMem(KeysBuf, SizeOf(TNDXEntry) * KeysMax);
  LeafCount := (EntryCount + KeysMax - 1) div KeysMax;
  GetMem(NodeInfos, SizeOf(TNDXNodeInfo) * LeafCount);
  Block := 1;
  NodeCount := 0;
  StartIdx := 0;
  while StartIdx < EntryCount do
  begin
    NumKeys := EntryCount - StartIdx;
    if NumKeys > KeysMax then
      NumKeys := KeysMax;
    for I := 0 to NumKeys - 1 do
      KeysBuf^[I] := Entries^[StartIdx + I];
    FillChar(ChildsBuf, SizeOf(ChildsBuf), 0);
    WriteNDXNode(F, Block, KeyLen, GroupLen, NumKeys, KeysBuf^, ChildsBuf, True, 0);
    NodeInfos^[NodeCount].Block := Block;
    NodeInfos^[NodeCount].MaxKey := KeysBuf^[NumKeys - 1].Key;
    Inc(NodeCount);
    Inc(Block);
    Inc(StartIdx, NumKeys);
  end;

  ChildPerNode := KeysMax + 1;
  while NodeCount > 1 do
  begin
    NextCount := (NodeCount + ChildPerNode - 1) div ChildPerNode;
    GetMem(NextNodeInfos, SizeOf(TNDXNodeInfo) * NextCount);
    ParentIdx := 0;
    ChildIdx := 0;
    while ChildIdx < NodeCount do
    begin
      ChildCount := NodeCount - ChildIdx;
      if ChildCount > ChildPerNode then
        ChildCount := ChildPerNode;
      NumKeys := ChildCount - 1;
      for I := 0 to NumKeys - 1 do
      begin
        KeysBuf^[I].Key := NodeInfos^[ChildIdx + I].MaxKey;
        KeysBuf^[I].Recno := 0;
        ChildsBuf[I] := NodeInfos^[ChildIdx + I].Block;
      end;
      LastChild := NodeInfos^[ChildIdx + NumKeys].Block;
      WriteNDXNode(F, Block, KeyLen, GroupLen, NumKeys, KeysBuf^, ChildsBuf, False, LastChild);
      NextNodeInfos^[ParentIdx].Block := Block;
      NextNodeInfos^[ParentIdx].MaxKey := NodeInfos^[ChildIdx + ChildCount - 1].MaxKey;
      Inc(ParentIdx);
      Inc(Block);
      Inc(ChildIdx, ChildCount);
    end;
    FreeMem(NodeInfos, SizeOf(TNDXNodeInfo) * NodeCount);
    NodeInfos := NextNodeInfos;
    NodeCount := NextCount;
  end;

  RootBlock := NodeInfos^[0].Block;
  EOFBlock := Block;

  FillChar(HeaderBuf, SizeOf(HeaderBuf), 0);
  SetLongIntLE(HeaderBuf, 1, RootBlock);
  SetLongIntLE(HeaderBuf, 5, EOFBlock);
  SetWordLE(HeaderBuf, 13, KeyLen);
  SetWordLE(HeaderBuf, 15, KeysMax);
  SetWordLE(HeaderBuf, 19, GroupLen);
  Expr := LowerStr(TrimString(FieldName));
  if Length(Expr) > 0 then
    Move(Expr[1], HeaderBuf[25], Length(Expr));
  HeaderBuf[25 + Length(Expr)] := 0;
  Seek(F, 0);
  BlockWrite(F, HeaderBuf, SizeOf(HeaderBuf));
  Close(F);

  FreeMem(KeysBuf, SizeOf(TNDXEntry) * KeysMax);
  FreeMem(NodeInfos, SizeOf(TNDXNodeInfo) * NodeCount);
  FreeMem(Entries, SizeOf(TNDXEntry) * RowCount);
end;

procedure ExportDBFToText(FileName: string);
var
  Dbf: PDBFFile;
  P: PInternalDBFFile;
  F: Text;
  Buf: TDBFRow;
  FieldIdx: Integer;
  Line: string;
  RowIndex, RowCount: LongInt;
  DBFFileName, TextFileName: string;
begin
  DBFFileName := FileName + '.DBF';
  TextFileName := FileName + '.TXT';
  Dbf := nil;
  DBFFileOpen(Dbf, DBFFileName);
  P := PInternalDBFFile(Dbf);
  Assign(F, TextFileName);
  Rewrite(F);

  Line := '';
  for FieldIdx := 1 to P^.Header.FieldCount do
  begin
    if FieldIdx > 1 then
      Line := Line + '|';
    Line := Line + P^.Header.Fields[FieldIdx].Name;
  end;
  WriteLn(F, Line);

  Line := '';
  for FieldIdx := 1 to P^.Header.FieldCount do
  begin
    if FieldIdx > 1 then
      Line := Line + '|';
    Line := Line + BuildFieldSpec(P^.Header.Fields[FieldIdx]);
  end;
  WriteLn(F, Line);

  RowCount := GetActualDBFRowCount(P^.F, P^.Header);
  SeekToFirstRow(P^.F, P^.Header);
  for RowIndex := 0 to RowCount - 1 do
  begin
    ReadDBFRow(P^.F, Buf, P^.Header.RecordSize);
    if Buf[0] <> Ord('*') then
    begin
      Line := '';
      for FieldIdx := 1 to P^.Header.FieldCount do
      begin
        if FieldIdx > 1 then
          Line := Line + '|';
        Line := Line + TrimString(GetFieldStr(Buf, P^.Header, FieldIdx));
      end;
      WriteLn(F, Line);
    end;
  end;
  Close(F);
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;

procedure ImportDBFFromText(FileName: string);
var
  F: Text;
  Line1, Line2, Line: string;
  Names, Specs: PStringArray;
  NameCount, SpecCount, ValueCount: Integer;
  Header: TDBFHeader;
  FieldType: Char;
  Len, Dec: Byte;
  I: Integer;
  Dbf: PDBFFile;
  Values: PDBFValues;
  TextFileName, DBFFileName: string;
begin
  TextFileName := FileName + '.TXT';
  DBFFileName := FileName + '.DBF';
  WriteLn('Importing database from ' + TextFileName + ' to ' + DBFFileName);  
  GetMem(Names, SizeOf(TStringArray));
  GetMem(Specs, SizeOf(TStringArray));
  GetMem(Values, SizeOf(TDBFValues));
  Assign(F, TextFileName);
  Reset(F);
  if EOF(F) then
  begin
    Close(F);
    FreeMem(Names, SizeOf(TStringArray));
    FreeMem(Specs, SizeOf(TStringArray));
    FreeMem(Values, SizeOf(TDBFValues));
    Exit;
  end;
  ReadLn(F, Line1);
  if EOF(F) then
  begin
    Close(F);
    FreeMem(Names, SizeOf(TStringArray));
    FreeMem(Specs, SizeOf(TStringArray));
    FreeMem(Values, SizeOf(TDBFValues));
    Exit;
  end;
  ReadLn(F, Line2);

  SplitPipe(Line1, Names^, NameCount);
  SplitPipe(Line2, Specs^, SpecCount);
  if NameCount <> SpecCount then
  begin
    Close(F);
    FreeMem(Names, SizeOf(TStringArray));
    FreeMem(Specs, SizeOf(TStringArray));
    FreeMem(Values, SizeOf(TDBFValues));
    Exit;
  end;

  FillChar(Header, SizeOf(Header), 0);
  Header.FieldCount := NameCount;
  for I := 1 to Header.FieldCount do
  begin
    Header.Fields[I].Name := TrimString(Names^[I]);
    if Length(Header.Fields[I].Name) > 11 then
      Header.Fields[I].Name := Copy(Header.Fields[I].Name, 1, 11);
    FieldType := 'C';
    Len := 1;
    Dec := 0;
    if ParseFieldSpec(Specs^[I], FieldType, Len, Dec) then
    begin
      Header.Fields[I].FieldType := FieldType;
      Header.Fields[I].Length := Len;
      Header.Fields[I].Decimals := Dec;
    end
    else
    begin
      Header.Fields[I].FieldType := 'C';
      Header.Fields[I].Length := 1;
      Header.Fields[I].Decimals := 0;
    end;
  end;

  Dbf := nil;
  DBFFileCreate(Dbf, FileName, Header);
  FreeMem(Names, SizeOf(TStringArray));
  FreeMem(Specs, SizeOf(TStringArray));
  while not EOF(F) do
  begin
    ReadLn(F, Line);
    if TrimString(Line) <> '' then
    begin
    SplitPipeValues(Line, Values^, ValueCount);
    if ValueCount < Header.FieldCount then
      for I := ValueCount + 1 to Header.FieldCount do
        Values^[I] := '';
    DBFFileAppendRow(Dbf, Values^);
    end;
  end;
  Close(F);
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
  FreeMem(Values, SizeOf(TDBFValues));
end;

const
  Base64Table: string[64] = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

type
  TB64EncState = record
    Rem: array[0..2] of Byte;
    RemLen: Byte;
  end;

function Base64Index(C: Byte): Integer;
var
  I: Integer;
begin
  Base64Index := -1;
  for I := 1 to Length(Base64Table) do
    if Ord(Base64Table[I]) = C then
    begin
      Base64Index := I - 1;
      Exit;
    end;
end;

procedure B64EncInit(var State: TB64EncState);
begin
  State.RemLen := 0;
end;

procedure B64EncOut3(B1, B2, B3: Byte; var OutF: Text);
var
  C1, C2, C3, C4: Byte;
begin
  C1 := (B1 shr 2) and $3F;
  C2 := ((B1 shl 4) and $30) or ((B2 shr 4) and $0F);
  C3 := ((B2 shl 2) and $3C) or ((B3 shr 6) and $03);
  C4 := B3 and $3F;
  Write(OutF, Base64Table[C1 + 1], Base64Table[C2 + 1],
               Base64Table[C3 + 1], Base64Table[C4 + 1]);
end;

procedure B64EncUpdate(var State: TB64EncState; var Buf; Len: Word; var OutF: Text);
var
  P: PByteArray;
  I: Word;
  B: Byte;
begin
  P := @Buf;
  I := 0;
  while (State.RemLen < 3) and (I < Len) do
  begin
    State.Rem[State.RemLen] := P^[I];
    Inc(State.RemLen);
    Inc(I);
  end;
  if State.RemLen = 3 then
  begin
    B64EncOut3(State.Rem[0], State.Rem[1], State.Rem[2], OutF);
    State.RemLen := 0;
  end;
  while I + 2 < Len do
  begin
    B64EncOut3(P^[I], P^[I + 1], P^[I + 2], OutF);
    Inc(I, 3);
  end;
  while I < Len do
  begin
    B := P^[I];
    State.Rem[State.RemLen] := B;
    Inc(State.RemLen);
    Inc(I);
  end;
end;

procedure B64EncFinal(var State: TB64EncState; var OutF: Text);
var
  C1, C2, C3: Byte;
begin
  if State.RemLen = 1 then
  begin
    C1 := (State.Rem[0] shr 2) and $3F;
    C2 := (State.Rem[0] shl 4) and $30;
    Write(OutF, Base64Table[C1 + 1], Base64Table[C2 + 1], '=', '=');
  end
  else if State.RemLen = 2 then
  begin
    C1 := (State.Rem[0] shr 2) and $3F;
    C2 := ((State.Rem[0] shl 4) and $30) or ((State.Rem[1] shr 4) and $0F);
    C3 := (State.Rem[1] shl 2) and $3C;
    Write(OutF, Base64Table[C1 + 1], Base64Table[C2 + 1],
                 Base64Table[C3 + 1], '=');
  end;
  State.RemLen := 0;
end;

procedure WriteEscapedText(var OutF: Text; var Buf; Len: Word);
var
  P: PByteArray;
  I: Word;
  C: Byte;
begin
  P := @Buf;
  for I := 0 to Len - 1 do
  begin
    C := P^[I];
    case C of
      10: Write(OutF, '\n');
      13: Write(OutF, '\r');
      9: Write(OutF, '\t');
      Ord('\'): Write(OutF, '\\');
      Ord('|'): Write(OutF, '\|');
    else
      Write(OutF, Chr(C));
    end;
  end;
end;

procedure WriteMemoChunks(MemoFileName: string; MemoBlock, MemoLen: LongInt;
  MemoType: LongInt; var OutF: Text);
var
  Offset: LongInt;
  ReadLen: Word;
  Chunk: array[1..256] of Byte;
  EncState: TB64EncState;
begin
  Offset := 0;
  if MemoType = 2 then
    B64EncInit(EncState);
  while Offset < MemoLen do
  begin
    if DBFMemoReadChunk(MemoFileName, MemoBlock, Offset, Chunk, SizeOf(Chunk), ReadLen) then
    begin
      if ReadLen > 0 then
        if MemoType = 2 then
          B64EncUpdate(EncState, Chunk, ReadLen, OutF)
        else
          WriteEscapedText(OutF, Chunk, ReadLen);
      Inc(Offset, ReadLen);
      if ReadLen = 0 then
        Offset := MemoLen;
    end
    else
      Offset := MemoLen;
  end;
  if MemoType = 2 then
    B64EncFinal(EncState, OutF);
end;

function EscapedDecodedLen(P: PByteArray; Start, Len: LongInt): LongInt;
var
  I: LongInt;
  Count: LongInt;
begin
  Count := 0;
  I := Start;
  while I < Start + Len do
  begin
    if (P^[I] = Ord('\')) and (I + 1 < Start + Len) then
    begin
      Inc(I, 2);
      Inc(Count);
    end
    else
    begin
      Inc(I);
      Inc(Count);
    end;
  end;
  EscapedDecodedLen := Count;
end;

procedure DecodeEscapedToMemo(P: PByteArray; Start, Len: LongInt; var State: TMemoWriteState);
var
  I: LongInt;
  OutBuf: array[1..256] of Byte;
  OutLen: Word;
  C: Byte;
begin
  I := Start;
  OutLen := 0;
  while I < Start + Len do
  begin
    C := P^[I];
    if (C = Ord('\')) and (I + 1 < Start + Len) then
    begin
      Inc(I);
      C := P^[I];
      case C of
        Ord('n'): C := 10;
        Ord('r'): C := 13;
        Ord('t'): C := 9;
        Ord('|'): C := Ord('|');
        Ord('\'): C := Ord('\');
      end;
    end;
    OutBuf[OutLen + 1] := C;
    Inc(OutLen);
    if OutLen = SizeOf(OutBuf) then
    begin
      DBFMemoWriteChunk(State, OutBuf, OutLen);
      OutLen := 0;
    end;
    Inc(I);
  end;
  if OutLen > 0 then
    DBFMemoWriteChunk(State, OutBuf, OutLen);
end;

function Base64DecodedLen(P: PByteArray; Start, Len: LongInt): LongInt;
var
  I: LongInt;
  Count: LongInt;
  Pad: LongInt;
  C: Byte;
begin
  Count := 0;
  Pad := 0;
  for I := Start to Start + Len - 1 do
  begin
    C := P^[I];
    if not ((C = Ord(' ')) or (C = 9)) then
    begin
      if C = Ord('=') then
      begin
        Inc(Pad);
        Inc(Count);
      end
      else if Base64Index(C) >= 0 then
        Inc(Count);
    end;
  end;
  if (Count = 0) or ((Count mod 4) <> 0) then
  begin
    Base64DecodedLen := -1;
    Exit;
  end;
  if Pad > 2 then Pad := 2;
  Base64DecodedLen := (Count div 4) * 3 - Pad;
end;

procedure DecodeBase64ToMemo(P: PByteArray; Start, Len: LongInt; var State: TMemoWriteState);
var
  I: LongInt;
  C: Byte;
  V: Integer;
  Quad: array[0..3] of Integer;
  QLen: Integer;
  OutBuf: array[1..256] of Byte;
  OutLen: Word;
  B1, B2, B3: Byte;
begin
  QLen := 0;
  OutLen := 0;
  for I := Start to Start + Len - 1 do
  begin
    C := P^[I];
    if not ((C = Ord(' ')) or (C = 9)) then
    begin
      if C = Ord('=') then
        V := -2
      else
        V := Base64Index(C);
      if (V >= 0) or (V = -2) then
      begin
        Quad[QLen] := V;
        Inc(QLen);
        if QLen = 4 then
        begin
          B1 := (Quad[0] shl 2) or (Quad[1] shr 4);
          OutBuf[OutLen + 1] := B1;
          Inc(OutLen);
          if Quad[2] <> -2 then
          begin
            B2 := ((Quad[1] and $0F) shl 4) or (Quad[2] shr 2);
            OutBuf[OutLen + 1] := B2;
            Inc(OutLen);
          end;
          if Quad[3] <> -2 then
          begin
            B3 := ((Quad[2] and $03) shl 6) or Quad[3];
            OutBuf[OutLen + 1] := B3;
            Inc(OutLen);
          end;
          if OutLen >= 240 then
          begin
            DBFMemoWriteChunk(State, OutBuf, OutLen);
            OutLen := 0;
          end;
          QLen := 0;
        end;
      end;
    end;
  end;
  if OutLen > 0 then
    DBFMemoWriteChunk(State, OutBuf, OutLen);
end;

procedure ExportDBFMemosToText(FileName: string);
var
  Dbf: PDBFFile;
  P: PInternalDBFFile;
  F: Text;
  Buf: TDBFRow;
  RowIndex, RowCount: LongInt;
  FieldIdx: Integer;
  MemoBlock: LongInt;
  MemoType: LongInt;
  MemoLen: LongInt;
  DBFFileName, MemoFileName, TextFileName : string;
  ExportRowIndex : LongInt;
begin
  DBFFileName := FileName + '.DBF';
  MemoFileName := FileName + '.DBT';
  TextFileName := FileName + '.MEM';

  Dbf := nil;
  DBFFileOpen(Dbf, DBFFileName);
  P := PInternalDBFFile(Dbf);
  Assign(F, TextFileName);
  Rewrite(F);

  RowCount := GetActualDBFRowCount(P^.F, P^.Header);
  SeekToFirstRow(P^.F, P^.Header);
  ExportRowIndex := 0;
  for RowIndex := 0 to RowCount - 1 do
  begin
    ReadDBFRow(P^.F, Buf, P^.Header.RecordSize);
    if Buf[0] <> Ord('*') then
    begin
      for FieldIdx := 1 to P^.Header.FieldCount do
        if UpCase(P^.Header.Fields[FieldIdx].FieldType) = 'M' then
        begin
          MemoBlock := ParseInt(TrimString(GetFieldStr(Buf, P^.Header, FieldIdx)));
          if MemoBlock > 0 then
            if DBFMemoGetInfo(MemoFileName, MemoBlock, MemoType, MemoLen) then
            begin
              Write(F, ExportRowIndex, '|', FieldIdx, '|', MemoType, '|', MemoBlock, '|');
              WriteMemoChunks(MemoFileName, MemoBlock, MemoLen, MemoType, F);
              WriteLn(F);
            end;
        end;
      Inc(ExportRowIndex);
    end;
  end;
  Close(F);
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;

function ParseMemoLine(Buf: PByteArray; BufLen: LongInt; var RowIndex: LongInt;
  var FieldIdx: Integer; var MemoType: LongInt; var BlockNum: LongInt;
  var HasBlock: Boolean; var ContentStart: LongInt; var ContentLen: LongInt): Boolean;
var
  I, PipeCount: Integer;
  PipePos: array[1..4] of LongInt;
  Code: Integer;
  NumBuf: string[20];
  SegStart, SegEnd: LongInt;
  ValOk: Boolean;
begin
  RowIndex := -1;
  FieldIdx := -1;
  MemoType := 1;
  BlockNum := 0;
  HasBlock := False;
  ContentStart := 0;
  ContentLen := 0;
  PipeCount := 0;
  for I := 0 to BufLen - 1 do
    if Buf^[I] = Ord('|') then
    begin
      Inc(PipeCount);
      if PipeCount <= 4 then
        PipePos[PipeCount] := I;
    end;
  if PipeCount < 3 then
  begin
    ParseMemoLine := False;
    Exit;
  end;

  SegStart := 0;
  SegEnd := PipePos[1];
  NumBuf := '';
  for I := SegStart to SegEnd - 1 do
    NumBuf := NumBuf + Chr(Buf^[I]);
  Val(NumBuf, RowIndex, Code);
  if Code <> 0 then
    RowIndex := -1;

  SegStart := PipePos[1] + 1;
  SegEnd := PipePos[2];
  NumBuf := '';
  for I := SegStart to SegEnd - 1 do
    NumBuf := NumBuf + Chr(Buf^[I]);
  Val(NumBuf, FieldIdx, Code);
  if Code <> 0 then
    FieldIdx := -1;

  SegStart := PipePos[2] + 1;
  SegEnd := PipePos[3];
  NumBuf := '';
  for I := SegStart to SegEnd - 1 do
    NumBuf := NumBuf + Chr(Buf^[I]);
  Val(NumBuf, MemoType, Code);
  if Code <> 0 then
    MemoType := 1;

  if PipeCount >= 4 then
  begin
    SegStart := PipePos[3] + 1;
    SegEnd := PipePos[4];
    NumBuf := '';
    for I := SegStart to SegEnd - 1 do
      NumBuf := NumBuf + Chr(Buf^[I]);
    Val(NumBuf, BlockNum, Code);
    ValOk := (Code = 0);
    if ValOk then
      HasBlock := True;
    ContentStart := PipePos[4] + 1;
  end;
  if MemoType <> 2 then
    MemoType := 1;
  if ContentStart = 0 then
    ContentStart := PipePos[3] + 1;
  ContentLen := BufLen - ContentStart;
  if ContentLen < 0 then
    ContentLen := 0;
  ParseMemoLine := (RowIndex >= 0) and (FieldIdx >= 1);
end;

procedure WriteMemoFromBuffer(MemoFileName: string; MemoType: LongInt;
  Buf: PByteArray; ContentStart, ContentLen: LongInt;
  var StartBlock: LongInt);
var
  DecLen: LongInt;
  State: TMemoWriteState;
begin
  if ContentLen = 0 then
  begin
    StartBlock := 0;
    Exit;
  end;
  if MemoType = 2 then
    DecLen := Base64DecodedLen(Buf, ContentStart, ContentLen)
  else
    DecLen := EscapedDecodedLen(Buf, ContentStart, ContentLen);
  if DecLen >= 0 then
  begin
    if DebugMemoImport then
      WriteLn('MEMO DBG: write append type=', MemoType, ' declen=', DecLen);
    DBFMemoWriteBegin(MemoFileName, MemoType, DecLen, StartBlock, State);
    if DebugMemoImport then
      WriteLn('MEMO DBG: append startblock=', StartBlock);
    if MemoType = 1 then
      DecodeEscapedToMemo(Buf, ContentStart, ContentLen, State)
    else if MemoType = 2 then
      DecodeBase64ToMemo(Buf, ContentStart, ContentLen, State);
    DBFMemoWriteEnd(State);
  end
  else
    StartBlock := 0;
end;

procedure WriteMemoFromBufferAtBlock(MemoFileName: string; MemoType: LongInt;
  Buf: PByteArray; ContentStart, ContentLen: LongInt; StartBlock: LongInt);
var
  DecLen: LongInt;
  State: TMemoWriteState;
begin
  if ContentLen = 0 then
    Exit;
  if MemoType = 2 then
    DecLen := Base64DecodedLen(Buf, ContentStart, ContentLen)
  else
    DecLen := EscapedDecodedLen(Buf, ContentStart, ContentLen);
  if DecLen < 0 then
    Exit;
  if DebugMemoImport then
    WriteLn('MEMO DBG: write at block=', StartBlock, ' type=', MemoType, ' declen=', DecLen);
  DBFMemoWriteBeginAtBlock(MemoFileName, MemoType, DecLen, StartBlock, State);
  if MemoType = 1 then
    DecodeEscapedToMemo(Buf, ContentStart, ContentLen, State)
  else if MemoType = 2 then
    DecodeBase64ToMemo(Buf, ContentStart, ContentLen, State);
  DBFMemoWriteEndAtBlock(State);
end;

procedure ImportDBFMemosFromText(FileName: string);
begin
  ImportDBFMemosFromTextEx(FileName, False);
end;

procedure ImportDBFMemosFromTextEx(FileName: string; PreserveBlocks: Boolean);
var
  F: File;
  Buf: PByteArray;
  TempBuf: PByteArray;
  BufLen: LongInt;
  BufCap: LongInt;
  B: Byte;
  ReadCount: Word;
  Dbf: PDBFFile;
  P: PInternalDBFFile;
  RowIndex: LongInt;
  FieldIdx: Integer;
  MemoType: LongInt;
  BlockNum: LongInt;
  HasBlock: Boolean;
  I: Integer;
  ContentStart: LongInt;
  ContentLen: LongInt;
  StartBlock: LongInt;
  RowBuf: TDBFRow;
  Values: TDBFValues;
  BlockStr: string[20];
  DoneLine: Boolean;
  TextFileName, DBFFileName, MemoFileName: string;
begin
  TextFileName := FileName + '.MEM';
  DBFFileName := FileName + '.DBF';
  MemoFileName := FileName + '.DBT';
  
  Assign(F, TextFileName);
  Reset(F, 1);
  Dbf := nil;
  DBFFileOpen(Dbf, DBFFileName);
  P := PInternalDBFFile(Dbf);

  Buf := nil;
  BufCap := 0;
  while not EOF(F) do
  begin
    BufLen := 0;
    DoneLine := False;
    while (not EOF(F)) and (not DoneLine) do
    begin
      BlockRead(F, B, 1, ReadCount);
      if ReadCount = 0 then
        DoneLine := True
      else if (B = 10) or (B = 13) then
      begin
        if B = 13 then
        begin
          BlockRead(F, B, 1, ReadCount);
          if (ReadCount = 1) and (B <> 10) then
            Seek(F, FilePos(F) - 1);
        end;
        DoneLine := True;
      end;
      if (not DoneLine) and (BufLen + 1 > BufCap) then
      begin
        if BufCap = 0 then
          BufCap := 256
        else
          BufCap := BufCap * 2;
        if Buf = nil then
          GetMem(Buf, BufCap)
        else
        begin
          GetMem(TempBuf, BufCap);
          Move(Buf^, TempBuf^, BufLen);
          FreeMem(Buf, BufCap div 2);
          Buf := TempBuf;
        end;
      end;
      if not DoneLine then
      begin
        Buf^[BufLen] := B;
        Inc(BufLen);
      end;
    end;
    if BufLen <> 0 then
    begin
      if ParseMemoLine(Buf, BufLen, RowIndex, FieldIdx, MemoType, BlockNum, HasBlock, ContentStart, ContentLen) and
         (FieldIdx <= P^.Header.FieldCount) and
         (UpCase(P^.Header.Fields[FieldIdx].FieldType) = 'M') then
      begin
        if DebugMemoImport then
          WriteLn('MEMO DBG: row=', RowIndex, ' field=', FieldIdx,
                  ' type=', MemoType, ' block=', BlockNum,
                  ' hasblock=', Ord(HasBlock), ' len=', ContentLen);
        if PreserveBlocks and HasBlock then
        begin
          StartBlock := BlockNum;
          WriteMemoFromBufferAtBlock(MemoFileName, MemoType, Buf, ContentStart, ContentLen, StartBlock);
        end
        else
          WriteMemoFromBuffer(MemoFileName, MemoType, Buf, ContentStart, ContentLen, StartBlock);
        DBFFileSeekToRow(Dbf, RowIndex);
        DBFFileReadRow(Dbf, RowBuf);
        Str(StartBlock, BlockStr);
        DBFFileSetFieldStr(RowBuf, Dbf, FieldIdx, BlockStr);
        if DebugMemoImport then
          WriteLn('MEMO DBG: set row=', RowIndex, ' field=', FieldIdx, ' blockstr=', BlockStr);
        FillChar(Values, SizeOf(Values), 0);
        for I := 1 to P^.Header.FieldCount do
          Values[I] := TrimString(DBFFileGetFieldStr(RowBuf, Dbf, I));
        DBFFileSeekToRow(Dbf, RowIndex);
        DBFFileWriteRow(Dbf, Values);
      end;
    end;
  end;

  if Buf <> nil then
    FreeMem(Buf, BufCap);
  Close(F);
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;

procedure CompactDBF(InFileName, OutFileName : string);
var
  InF, OutF: File;
  Header, OutHeader: TDBFHeader;
  RowIndex, RowCount: LongInt;
  Buf: TDBFRow;
  Values: TDBFValues;
  FieldIdx: Integer;
  MemoBlock: LongInt;
  MemoType: LongInt;
  MemoLen: LongInt;
  Offset: LongInt;
  ReadLen: Word;
  Chunk: array[1..256] of Byte;
  NewBlock: LongInt;
  State: TMemoWriteState;
  BlockStr: string;
begin
  Assign(InF, InFileName + '.DBF');
  Reset(InF, 1);
  ReadDBFHeader(InF, Header);
  OutHeader := Header;
  OutHeader.RecordCount := 0;

  Assign(OutF, OutFileName + '.DBF');
  Rewrite(OutF, 1);
  WriteDBFHeader(OutF, OutHeader);

  if HasMemoField(Header) then
  begin
    Assign(State.F, OutFileName + '.DBT');
    Rewrite(State.F, 1);
    MemoInitFile(State.F);
    Close(State.F);
  end;

  RowCount := GetActualDBFRowCount(InF, Header);
  SeekToFirstRow(InF, Header);
  for RowIndex := 0 to RowCount - 1 do
  begin
    ReadDBFRow(InF, Buf, Header.RecordSize);
    if Buf[0] <> Ord('*') then
    begin
      FillChar(Values, SizeOf(Values), 0);
      for FieldIdx := 1 to Header.FieldCount do
      begin
        if UpCase(Header.Fields[FieldIdx].FieldType) = 'M' then
        begin
          MemoBlock := ParseInt(TrimString(GetFieldStr(Buf, Header, FieldIdx)));
          if (MemoBlock > 0) and
             DBFMemoGetInfo(InFileName + '.DBT', MemoBlock, MemoType, MemoLen) then
          begin
            DBFMemoWriteBegin(OutFileName + '.DBT', MemoType, MemoLen, NewBlock, State);
            Offset := 0;
            while Offset < MemoLen do
            begin
              if DBFMemoReadChunk(InFileName + '.DBT', MemoBlock, Offset, Chunk, SizeOf(Chunk), ReadLen) then
              begin
                if ReadLen > 0 then
                  DBFMemoWriteChunk(State, Chunk, ReadLen);
                Inc(Offset, ReadLen);
                if ReadLen = 0 then
                  Offset := MemoLen;
              end
              else
                Offset := MemoLen;
            end;
            DBFMemoWriteEnd(State);
            Str(NewBlock, BlockStr);
            Values[FieldIdx] := BlockStr;
          end
          else
            Values[FieldIdx] := '0';
        end
        else
          Values[FieldIdx] := TrimString(GetFieldStr(Buf, Header, FieldIdx));
      end;
      AppendDBFRow(OutF, OutHeader, Values);
    end;
  end;

  Close(InF);
  Close(OutF);
end;

end.
