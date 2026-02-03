unit DBF;

{ string IDX files, multi-field index (trucated string) }

interface

uses DBFUTIL;

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
  DBFDebug = False;

  DBFLangUS = $01;
  DBFLangWesternEurope = $02;
  DBFLangJapan = $7B;

type
  PByte = ^Byte;
  PString = ^string;
  PLongInt = ^LongInt;
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

  { Field-by-field management - allocate only what we need }
  TFieldInfo = record
    Name: string[11];      { DBF field name max 11 chars }
    FieldType: Char;       { C, N, d, L, M }
    Length: Byte;          { Field length }
    Decimals: Byte;        { Decimal places }
    Offset: Word;          { Offset in record }
  end;

  
  { Dynamic field array - allocate based on actual field count }
  PFieldArray = ^TFieldArray;
  TFieldArray = array[0..0] of TFieldInfo;
  
  PDBFFile = Pointer;
  
  function AllocateSmartValueArray(Header: TDBFHeader): Pointer;
  function FreeSmartValueArray(Values: Pointer): Boolean;
  function DBFFieldGetSmartStr(SmartArray: Pointer; Header: TDBFHeader; 
     FieldIndex: Integer): string;
  function DBFFieldSetStr(SmartArray: Pointer; Header: TDBFHeader; 
     FieldIndex: Integer; Value: string): Boolean;
  function DBFFieldGetStr(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer): string;
  function GetSmartFieldValue(SmartArray: Pointer; Header: TDBFHeader; 
     FieldIndex: Integer): string;
  function SetSmartFieldValue(SmartArray: Pointer; Header: TDBFHeader; 
     FieldIndex: Integer; Value: string): Boolean;
  function DBFFileGetFieldStrFromBuf(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer): string;
  function GetFieldStr(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer): string;
  procedure SetFieldStr(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer; Value: string);

{ DBF File Operations }
function DBFFileCreate(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader): Boolean;
function DBFFileCreateDBase3(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader): Boolean;
function DBFFileOpen(var Dbf: PDBFFile; FileName: string): Boolean;
function DBFFileClose(var Dbf: PDBFFile): Boolean;
function DBFFileDispose(var Dbf: PDBFFile): Boolean;
function DBFFileGetHeader(var Dbf: PDBFFile; var Header: TDBFHeader): Boolean;

function DBFFileReadRow(var Dbf: PDBFFile; var Buf: Pointer; BufSize: Integer): Boolean;
function DBFFileWriteRow(var Dbf: PDBFFile; var Values: Pointer; FieldCount: Integer): Boolean;
function DBFFileAppendRow(var Dbf: PDBFFile; var Values: Pointer; FieldCount: Integer): Boolean;
function DBFFileSetRowDeleted(var Dbf: PDBFFile; Deleted: Boolean): Boolean;

function DBFFileSeekToRow(var Dbf: PDBFFile; RowIndex: LongInt): Boolean;
function DBFFileSeekToFirstRow(var Dbf: PDBFFile): Boolean;
function DBFFileSeekToEnd(var Dbf: PDBFFile): Boolean;
function DBFFileGetCurrentRow(var Dbf: PDBFFile; var RowIndex: LongInt): Boolean;

function DBFFileGetDate(var Dbf: PDBFFile; var Year, Month, Day: Byte): Boolean;
function DBFFileSetDate(var Dbf: PDBFFile; Year, Month, Day: Byte): Boolean;
function DBFFileIsDateOlder(var Dbf: PDBFFile; Year, Month, Day: Byte): Boolean;
function DBFFileGetLanguageDriver(var Dbf: PDBFFile; var Lang: Byte): Boolean;
function DBFFileSetLanguageDriver(var Dbf: PDBFFile; Lang: Byte): Boolean;

function DBFCompact(InFileName, OutFileName: string): Boolean;
function DBFFileClearMemoFields(var Dbf: PDBFFile): Boolean;
function DBFFileGetActualRowCount(var Dbf: PDBFFile): LongInt;

implementation

function DatabasePath(BaseName: string; var OutPath: string): Boolean;
var
  DotPos: Integer;
  NamePart, ExtPart: string;
  SepPos: Integer;
  PathPart, FilePart: string;
begin
  SepPos := Length(BaseName);
  while (SepPos >= 1) and (BaseName[SepPos] <> '\') and (BaseName[SepPos] <> '/') do
    Dec(SepPos);
  if (SepPos >= 1) and ((BaseName[SepPos] = '\') or (BaseName[SepPos] = '/')) then
  begin
    PathPart := Copy(BaseName, 1, SepPos);
    FilePart := Copy(BaseName, SepPos + 1, 255);
  end
  else
  begin
    PathPart := '';
    FilePart := BaseName;
  end;

  if Length(FilePart) = 0 then
  begin
    DatabasePath := False;
    OutPath := '';
    Exit;
  end;

  DotPos := Length(FilePart);
  while (DotPos >= 1) and (FilePart[DotPos] <> '.') do
    Dec(DotPos);
  if (DotPos >= 1) and (FilePart[DotPos] = '.') then
  begin
    NamePart := Copy(FilePart, 1, DotPos - 1);
    ExtPart := Copy(FilePart, DotPos + 1, 255);
  end
  else
  begin
    NamePart := FilePart;
    ExtPart := '';
  end;
  if (Length(NamePart) = 0) or (Length(NamePart) > 8) then
  begin
    DatabasePath := False;
    OutPath := '';
    Exit;
  end;
  if (Length(ExtPart) > 3) then
  begin
    DatabasePath := False;
    OutPath := '';
    Exit;
  end;
  if (Length(ExtPart) = 0) then
    OutPath := PathPart + NamePart + '.DBF'
  else
    OutPath := PathPart + NamePart + '.' + ExtPart;
  DatabasePath := True;
end;

type
  TDBFFile = record
    F: File;
    Header: TDBFHeader;
    IsOpen: Boolean;
  end;
  PInternalDBFFile = ^TDBFFile;

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
  Year, Month, Day: Word;
begin
  HasMemo := HasMemoField(Header);
  Header.TableFlags := 0;
  Header.LanguageDriver := DBFLangUS;
  
  { Auto-fill date if not specified by user }
  if Header.Year = 0 then
  begin
    GetDate(Year, Month, Day);
    Header.Year := Year - 1900;
    Header.Month := Month;
    Header.Day := Day;
  end;
  
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

procedure WriteDBFRow(var F: File; Header: TDBFHeader; var Values: Pointer; FieldCount: Integer);
var
  I, J, FieldLen: Integer;
  Buf: Pointer;
  S: string[255];
begin
  GetMem(Buf, Header.RecordSize);
  FillChar(Buf^, Header.RecordSize, Ord(' '));
  PByteArray(Buf)^[0] := Ord(' '); { delete flag }
  
  { Validate field count }
  if (FieldCount < 0) or (FieldCount > Header.FieldCount) then
    FieldCount := Header.FieldCount;
  
  for I := 0 to FieldCount - 1 do
  begin
    FieldLen := Header.Fields[I + 1].Length;
    S := DBFFieldGetSmartStr(Values, Header, I + 1);
    if Length(S) > FieldLen then
      S := Copy(S, 1, FieldLen);
    while Length(S) < FieldLen do
      S := S + ' ';
    for J := 1 to FieldLen do
      PByteArray(Buf)^[Header.Fields[I + 1].Offset + J - 1] := Ord(S[J]);
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

procedure ReadDBFRow(var F: File; Buf: Pointer; RecordSize: Integer);
begin
  BlockRead(F, Buf^, RecordSize);
end;

function DBFFieldGetStr(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer): string;
var
  Offs, Len, I: Integer;
  S: string[255];
begin
  Offs := Header.Fields[FieldIdx].Offset;
  Len := Header.Fields[FieldIdx].Length;
  S := '';
  for I := 1 to Len do
    S := S + Chr(PByteArray(Buf)^[Offs + I - 1]);
  DBFFieldGetStr := S;
end;

function DBFFileGetFieldStrFromBuf(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer): string;
begin
  DBFFileGetFieldStrFromBuf := DBFFieldGetStr(Buf, Header, FieldIdx);
end;

function GetFieldStr(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer): string;
begin
  GetFieldStr := DBFFieldGetStr(Buf, Header, FieldIdx);
end;

procedure SetFieldStr(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer; Value: string);
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
    PByteArray(Buf)^[Offs + I - 1] := Ord(S[I]);
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

procedure AppendDBFRow(var F: File; var Header: TDBFHeader; var Values: Pointer; FieldCount: Integer);
var
  Terminator: Byte;
begin
  SeekToEnd(F, Header);
  WriteDBFRow(F, Header, Values, FieldCount);
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

function DBFFileOpen(var Dbf: PDBFFile; FileName: string): Boolean;
var
  P: PInternalDBFFile;
  IoCode: Integer;
begin
  DBFFileOpen := False;
  DBFFileAlloc(Dbf);
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  if not DatabasePath(FileName, FileName) then
    Exit;
  Assign(P^.F, FileName);
  {$I-}
  Reset(P^.F, 1);
  IoCode := IOResult;
  {$I+}
  if IoCode <> 0 then
    Exit;
  ReadDBFHeader(P^.F, P^.Header);
  P^.IsOpen := True;
  DBFFileOpen := True;
end;

procedure DBFMemoCreate(FileName: string);
const
  MemoBlockSize = 512;
var
  F: File;
  Buf: array[1..MemoBlockSize] of Byte;
  NextFree: LongInt;
  IoCode: Integer;
begin
  Assign(F, FileName + '.DBT');
  {$I-}
  Rewrite(F, 1);
  IoCode := IOResult;
  {$I+}
  if IoCode <> 0 then
    Exit;
  FillChar(Buf, SizeOf(Buf), 0);
  NextFree := 1;
  Buf[1] := NextFree and $FF;
  Buf[2] := (NextFree shr 8) and $FF;
  Buf[3] := (NextFree shr 16) and $FF;
  Buf[4] := (NextFree shr 24) and $FF;
  Buf[5] := MemoBlockSize and $FF;
  Buf[6] := (MemoBlockSize shr 8) and $FF;
  {$I-}
  BlockWrite(F, Buf, MemoBlockSize);
  IoCode := IOResult;
  {$I+}
  Close(F);
end;

function DBFFileCreate(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader): Boolean;
var
  P: PInternalDBFFile;
  IoCode: Integer;
begin
  DBFFileCreate := False;
  if DBFDebug then
    WriteLn('DBFFileCreate: start ', FileName);
  DBFFileAlloc(Dbf);
  if Dbf = nil then
    Exit;
  P := PInternalDBFFile(Dbf);
  if not DatabasePath(FileName, FileName) then
    Exit;
  Assign(P^.F, FileName);
  if DBFDebug then
    WriteLn('DBFFileCreate: Rewrite ', FileName);
  {$I-}
  Rewrite(P^.F, 1);
  IoCode := IOResult;
  {$I+}
  if IoCode <> 0 then
    Exit;
  if DBFDebug then
    WriteLn('DBFFileCreate: InitDBFHeader');
  InitDBFHeader(Header);
  if DBFDebug then
    WriteLn('DBFFileCreate: WriteDBFHeader');
  WriteDBFHeader(P^.F, Header);
  P^.Header := Header;
  P^.IsOpen := True;

  if P^.Header.Version = $05 then
  begin
    if DBFDebug then
      WriteLn('DBFFileCreate: DBFMemoCreate');
    DBFMemoCreate(FileName);
  end;
  DBFFileCreate := True;
  if DBFDebug then
    WriteLn('DBFFileCreate: done');
end;

function DBFFileCreateDBase3(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader): Boolean;
begin
  Header.Version := $03;
  Header.TableFlags := 0;
  Header.LanguageDriver := 0;
  DBFFileCreateDBase3 := DBFFileCreate(Dbf, FileName, Header);
end;

function DBFFileClose(var Dbf: PDBFFile): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileClose := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  if P^.IsOpen then
    Close(P^.F);
  P^.IsOpen := False;
  DBFFileClose := True;
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

function DBFFileDispose(var Dbf: PDBFFile): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileDispose := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  if P^.IsOpen then
    Close(P^.F);
  Dispose(P);
  Dbf := nil;
  DBFFileDispose := True;
end;

function DBFFileReadRow(var Dbf: PDBFFile; var Buf: Pointer; BufSize: Integer): Boolean;
var
  P: PInternalDBFFile;
  IoCode: Integer;
  BytesRead: Word;
begin
  if Dbf = nil then
  begin
    DBFFileReadRow := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  
  { Validate buffer size against record size }
  if BufSize < P^.Header.RecordSize then
  begin
    DBFFileReadRow := False;
    Exit;
  end;
    
  { Read directly into provided buffer }
  {$I-}
  BlockRead(P^.F, Buf^, P^.Header.RecordSize, BytesRead);
  IoCode := IOResult;
  {$I+}
  if (IoCode <> 0) or (BytesRead <> P^.Header.RecordSize) then
  begin
    DBFFileReadRow := False;
    Exit;
  end;
  DBFFileReadRow := True;
end;

function DBFFileWriteRow(var Dbf: PDBFFile; var Values: Pointer; FieldCount: Integer): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileWriteRow := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  
  { Validate field count }
  if (FieldCount < 0) or (FieldCount > P^.Header.FieldCount) then
  begin
    DBFFileWriteRow := False;
    Exit;
  end;
    
  { Write row directly with PValueArray }
  WriteDBFRow(P^.F, P^.Header, Values, FieldCount);
  DBFFileWriteRow := True;
end;

function DBFFileSeekToRow(var Dbf: PDBFFile; RowIndex: LongInt): Boolean;
var
  P: PInternalDBFFile;
  DiskRecordCount: LongInt;
  RecordCount: LongInt;
begin
  if Dbf = nil then
  begin
    DBFFileSeekToRow := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  DiskRecordCount := GetActualDBFRowCount(P^.F, P^.Header);
  RecordCount := P^.Header.RecordCount;
  if DiskRecordCount <> RecordCount then
  begin
    RecordCount := DiskRecordCount;
    UpdateDBFRecordCount(P^.F, RecordCount);
  end;
  if (RecordCount <= 0) or (RowIndex < 0) or (RowIndex > RecordCount - 1) then
  begin
    DBFFileSeekToRow := False;
    Exit;
  end;
  SeekToRow(P^.F, P^.Header, RowIndex);
  DBFFileSeekToRow := True;
end;

function DBFFileSeekToFirstRow(var Dbf: PDBFFile): Boolean;
var
  P: PInternalDBFFile;
  RecordCount: LongInt;
begin
  if Dbf = nil then
  begin
    DBFFileSeekToFirstRow := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  RecordCount := GetActualDBFRowCount(P^.F, P^.Header);
  if RecordCount <= 0 then
  begin
    DBFFileSeekToFirstRow := False;
    Exit;
  end;
  SeekToFirstRow(P^.F, P^.Header);
  DBFFileSeekToFirstRow := True;
end;

function DBFFileSeekToEnd(var Dbf: PDBFFile): Boolean;
var
  P: PInternalDBFFile;
  RecordCount: LongInt;
begin
  if Dbf = nil then
  begin
    DBFFileSeekToEnd := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  RecordCount := GetActualDBFRowCount(P^.F, P^.Header);
  if RecordCount <= 0 then
  begin
    SeekToFirstRow(P^.F, P^.Header);
    DBFFileSeekToEnd := True;
    Exit;
  end;
  SeekToRow(P^.F, P^.Header, RecordCount - 1);
  DBFFileSeekToEnd := True;
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

function DBFFileGetCurrentRow(var Dbf: PDBFFile; var RowIndex: LongInt): Boolean;
var
  P: PInternalDBFFile;
  Pos: LongInt;
  RecordCount: LongInt;
begin
  if Dbf = nil then
  begin
    RowIndex := -1;
    DBFFileGetCurrentRow := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  Pos := FilePos(P^.F);
  if (P^.Header.RecordSize <= 0) or (Pos < P^.Header.HeaderSize) then
  begin
    RowIndex := -1;
    DBFFileGetCurrentRow := False;
    Exit;
  end;
  RecordCount := GetActualDBFRowCount(P^.F, P^.Header);
  if RecordCount <= 0 then
  begin
    RowIndex := -1;
    DBFFileGetCurrentRow := False;
    Exit;
  end;
  RowIndex := (Pos - P^.Header.HeaderSize) div P^.Header.RecordSize;
  if RowIndex >= RecordCount then
  begin
    if Pos = P^.Header.HeaderSize + (RecordCount * P^.Header.RecordSize) then
    begin
      RowIndex := RecordCount - 1;
      DBFFileGetCurrentRow := True;
    end
    else
    begin
      RowIndex := -1;
      DBFFileGetCurrentRow := False;
    end;
    Exit;
  end;
  DBFFileGetCurrentRow := True;
end;

function DBFFileGetDate(var Dbf: PDBFFile; var Year, Month, Day: Byte): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    Year := 0;
    Month := 0;
    Day := 0;
    DBFFileGetDate := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  Year := P^.Header.Year;
  Month := P^.Header.Month;
  Day := P^.Header.Day;
  DBFFileGetDate := True;
end;

function DBFFileSetDate(var Dbf: PDBFFile; Year, Month, Day: Byte): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileSetDate := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  P^.Header.Year := Year;
  P^.Header.Month := Month;
  P^.Header.Day := Day;
  UpdateDBFHeaderDate(P^.F, Year, Month, Day);
  DBFFileSetDate := True;
end;

function DBFFileGetLanguageDriver(var Dbf: PDBFFile; var Lang: Byte): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    Lang := 0;
    DBFFileGetLanguageDriver := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  Lang := P^.Header.LanguageDriver;
  DBFFileGetLanguageDriver := True;
end;

function DBFFileSetLanguageDriver(var Dbf: PDBFFile; Lang: Byte): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileSetLanguageDriver := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  P^.Header.LanguageDriver := Lang;
  UpdateDBFLanguageDriver(P^.F, Lang);
  DBFFileSetLanguageDriver := True;
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

function DBFFileAppendRow(var Dbf: PDBFFile; var Values: Pointer; FieldCount: Integer): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileAppendRow := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  
  { Validate field count }
  if (FieldCount < 0) or (FieldCount > P^.Header.FieldCount) then
  begin
    DBFFileAppendRow := False;
    Exit;
  end;
    
  { Append row directly with PValueArray }
  AppendDBFRow(P^.F, P^.Header, Values, FieldCount);
  DBFFileAppendRow := True;
end;

function DBFFileSetRowDeleted(var Dbf: PDBFFile; Deleted: Boolean): Boolean;
var
  P: PInternalDBFFile;
begin
  if Dbf = nil then
  begin
    DBFFileSetRowDeleted := False;
    Exit;
  end;
  P := PInternalDBFFile(Dbf);
  
  { Operate on current row position }
  SetDBFRowDeleted(P^.F, Deleted);
  DBFFileSetRowDeleted := True;
end;

{ Allocate field array }
function AllocateFieldArray(FieldCount: Integer): PFieldArray;
var
  TempPtr: PFieldArray;
begin
  GetMem(TempPtr, FieldCount * SizeOf(TFieldInfo));
  AllocateFieldArray := TempPtr;
end;

{ Free field array }
procedure FreeFieldArray(Fields: PFieldArray; FieldCount: Integer);
begin
  if Fields <> nil then
    FreeMem(Fields, FieldCount * SizeOf(TFieldInfo));
end;

{ Smart value array allocation - uses exact DBF field sizes }
function AllocateSmartValueArray(Header: TDBFHeader): Pointer;
var
  TotalSize: LongInt;
  I: Integer;
  TempPtr: Pointer;
  SizePtr: PLongInt;
begin
  TempPtr := nil;  { Initialize temporary pointer }
  TotalSize := 0;
  for I := 1 to Header.FieldCount do
  begin
    case Header.Fields[I].FieldType of
      'C': Inc(TotalSize, Header.Fields[I].Length + 1);  { +1 for length byte }
      'N': Inc(TotalSize, Header.Fields[I].Length + 1);  { +1 for length byte }
      'D': Inc(TotalSize, 8);                           { Fixed 8 bytes for YYYYMMDD }
      'L': Inc(TotalSize, 1);                           { Fixed 1 byte }
      'M': Inc(TotalSize, 4);                           { 4 bytes - memo block number }
    end;
  end;
  
  { Allocate extra space to store the size }
  GetMem(TempPtr, TotalSize + SizeOf(LongInt));
  
  { Store the size at the beginning for later cleanup }
  SizePtr := PLongInt(TempPtr);
  SizePtr^ := TotalSize;
  
  { Return pointer after the size field }
  AllocateSmartValueArray := PByte(LongInt(TempPtr) + SizeOf(LongInt));
end;

{ Free smart value array }
function FreeSmartValueArray(Values: Pointer): Boolean;
var
  SizePtr: PLongInt;
  ActualPtr: Pointer;
  TotalSize: LongInt;
begin
  if Values = nil then
  begin
    FreeSmartValueArray := False;
    Exit;
  end;
  { Get the actual pointer and size from the stored information }
  SizePtr := PLongInt(LongInt(Values) - SizeOf(LongInt));
  TotalSize := SizePtr^;
  ActualPtr := PByte(LongInt(Values) - SizeOf(LongInt));
  
  { Free the entire allocated block }
  FreeMem(ActualPtr, TotalSize + SizeOf(LongInt));
  FreeSmartValueArray := True;
end;

{ Smart value accessor functions }
function DBFFieldGetSmartStr(SmartArray: Pointer; Header: TDBFHeader; 
  FieldIndex: Integer): string;
var
  Offset: LongInt;
  I: Integer;
  P: PByte;
  Result: string;
begin
  Result := '';
  if (SmartArray = nil) or (FieldIndex < 1) or (FieldIndex > Header.FieldCount) then
    Exit;
    
  { Calculate offset to this field's data }
  Offset := 0;
  for I := 1 to FieldIndex - 1 do
  begin
    case Header.Fields[I].FieldType of
      'C': Inc(Offset, Header.Fields[I].Length + 1);
      'N': Inc(Offset, Header.Fields[I].Length + 1);
      'D': Inc(Offset, 8);
      'L': Inc(Offset, 1);
      'M': Inc(Offset, 4);  { 4 bytes - memo block number }
    end;
  end;
  
  { Extract value based on field type }
  P := PByte(LongInt(SmartArray) + Offset);
  case Header.Fields[FieldIndex].FieldType of
    'C', 'N': Result := PString(P)^;
    'D': Result := JDNToDate(PLongInt(P)^);
    'L': 
      begin
        if PByte(P)^ = 1 then
          Result := 'T'
        else
          Result := 'F';
      end;
    'M': Result := IntToStrLocal(PLongInt(P)^);  { Return block number as string }
  end;

  DBFFieldGetSmartStr := Result;
end;

function GetSmartFieldValue(SmartArray: Pointer; Header: TDBFHeader; 
  FieldIndex: Integer): string;
begin
  GetSmartFieldValue := DBFFieldGetSmartStr(SmartArray, Header, FieldIndex);
end;

function SetSmartFieldValue(SmartArray: Pointer; Header: TDBFHeader; 
  FieldIndex: Integer; Value: string): Boolean;
var
  Offset: LongInt;
  I: Integer;
  P: PByte;
  Code: Integer;
  TempInt: LongInt;
begin
  if (SmartArray = nil) or (FieldIndex < 1) or (FieldIndex > Header.FieldCount) then
  begin
    SetSmartFieldValue := False;
    Exit;
  end;
    
  { Calculate offset to this field's data }
  Offset := 0;
  for I := 1 to FieldIndex - 1 do
  begin
    case Header.Fields[I].FieldType of
      'C': Inc(Offset, Header.Fields[I].Length + 1);
      'N': Inc(Offset, Header.Fields[I].Length + 1);
      'D': Inc(Offset, 8);
      'L': Inc(Offset, 1);
      'M': Inc(Offset, 4);  { 4 bytes - memo block number }
    end;
  end;
  
  { Set value based on field type }
  P := PByte(LongInt(SmartArray) + Offset);
  case Header.Fields[FieldIndex].FieldType of
    'C', 'N':
      begin
        PString(P)^ := Value;
        SetSmartFieldValue := True;
      end;
    'D': 
      begin
        TempInt := DateToJDN(Value);  { Convert date string to JDN internally }
        PLongInt(P)^ := TempInt;
        SetSmartFieldValue := True;
      end;
    'L': 
      begin
        if (Value = 'T') or (Value = 't') then
          PByte(P)^ := 1
        else
          PByte(P)^ := 0;
        SetSmartFieldValue := True;
      end;
    'M': 
      begin
        Val(Value, TempInt, Code);
        if Code = 0 then
        begin
          PLongInt(P)^ := TempInt;  { Store block number }
          SetSmartFieldValue := True;
        end
        else
          SetSmartFieldValue := False;
      end;
    else
      SetSmartFieldValue := False;
  end;
end;

function DBFFieldSetStr(SmartArray: Pointer; Header: TDBFHeader; 
  FieldIndex: Integer; Value: string): Boolean;
begin
  DBFFieldSetStr := SetSmartFieldValue(SmartArray, Header, FieldIndex, Value);
end;

{ Convert field type to ruthlessly optimized packed storage type }
function GetPackedType(FieldType: Char; Length: Byte): Byte;
begin
  case FieldType of
    'C': begin
           if Length <= 127 then GetPackedType := 7  { Short string }
           else GetPackedType := 8;  { Long string (255 bytes) }
         end;
    'N': begin
           if Length <= 2 then GetPackedType := 2  { Byte }
           else if Length <= 4 then GetPackedType := 3  { Word }
           else if Length <= 6 then GetPackedType := 4  { SmallInt }
           else if Length <= 9 then GetPackedType := 5  { LongInt }
           else GetPackedType := 6;  { Scaled integer for decimals }
         end;
    'L': GetPackedType := 1;  { Boolean }
    'D': begin
           { Use compact date for 1900-2079 range, JDN for others }
           GetPackedType := 11;  { Compact date }
         end;
    'M': GetPackedType := 10;  { Memo pointer }
    else GetPackedType := 8;  { Default to long string }
  end;
end;

{ Compact date encoding (1900-2079 range) - 2 bytes }
function DateToCompact(DateStr: string): Word;
var
  Year, Month, Day: Integer;
  Code: Integer;
begin
  if Length(DateStr) = 8 then
  begin
    Val(Copy(DateStr, 1, 4), Year, Code);
    Val(Copy(DateStr, 5, 2), Month, Code);
    Val(Copy(DateStr, 7, 2), Day, Code);
    
    if (Code = 0) and (Year >= 1900) and (Year <= 2079) then
    begin
      { Encode: YYYYYYYMMMMDDDDD (7+4+5 = 16 bits) }
      DateToCompact := ((Year - 1900) shl 9) or (Month shl 5) or Day;
      Exit;
    end;
  end;
  DateToCompact := 0;  { Invalid date }
end;

function CompactToDate(CompactDate: Word): string;
var
  Year, Month, Day: Integer;
begin
  if CompactDate = 0 then
  begin
    CompactToDate := '';
    Exit;
  end;
  
  Year := (CompactDate shr 9) + 1900;
  Month := (CompactDate shr 5) and $0F;
  Day := CompactDate and $1F;
  
  if (Month >= 1) and (Month <= 12) and (Day >= 1) and (Day <= 31) then
    CompactToDate := FormatDate(Year, Month, Day)
  else
    CompactToDate := '';
end;

{ Compact time encoding (HHMMSS) - 2 bytes }
function TimeToCompact(TimeStr: string): Word;
var
  Hour, Minute, Second: Integer;
  Code: Integer;
begin
  if Length(TimeStr) = 6 then
  begin
    Val(Copy(TimeStr, 1, 2), Hour, Code);
    Val(Copy(TimeStr, 3, 2), Minute, Code);
    Val(Copy(TimeStr, 5, 2), Second, Code);
    
    if (Code = 0) and (Hour <= 23) and (Minute <= 59) and (Second <= 59) then
    begin
      { Encode: HHHHHMMMMMMSSSSS (5+6+5 = 16 bits) }
      TimeToCompact := (Hour shl 11) or (Minute shl 5) or (Second div 2);
      Exit;
    end;
  end;
  TimeToCompact := 0;  { Invalid time }
end;

function CompactToTime(CompactTime: Word): string;
var
  Hour, Minute, Second: Integer;
begin
  if CompactTime = 0 then
  begin
    CompactToTime := '';
    Exit;
  end;
  
  Hour := CompactTime shr 11;
  Minute := (CompactTime shr 5) and $3F;
  Second := (CompactTime and $1F) * 2;
  
  if (Hour <= 23) and (Minute <= 59) and (Second <= 59) then
    CompactToTime := FormatTime(Hour, Minute, Second)
  else
    CompactToTime := '';
end;

{ Convert DBF header to dynamic field array }
function HeaderToFieldArray(var Header: TDBFHeader): PFieldArray;
var
  I: Integer;
  Fields: PFieldArray;
begin
  Fields := AllocateFieldArray(Header.FieldCount);
  for I := 0 to Header.FieldCount - 1 do
  begin
    Fields^[I].Name := Header.Fields[I + 1].Name;
    Fields^[I].FieldType := Header.Fields[I + 1].FieldType;
    Fields^[I].Length := Header.Fields[I + 1].Length;
    Fields^[I].Decimals := Header.Fields[I + 1].Decimals;
    Fields^[I].Offset := Header.Fields[I + 1].Offset;
  end;
  HeaderToFieldArray := Fields;
end;

{ Packed buffer memory management functions }
procedure DeleteTempFile(TempFileName: string);
var
  F: File;
begin
  Assign(F, TempFileName);
  {$I-}
  Erase(F);
  {$I+}
end;

function DBFCompact(InFileName, OutFileName : string): Boolean;
var
  InF, OutF: File;
  Header, OutHeader: TDBFHeader;
  RowIndex, RowCount: LongInt;
  Buf: Pointer;
  Values: Pointer;
  FieldIdx: Integer;
begin
  DBFCompact := False;
  if not DatabasePath(InFileName, InFileName) then
    Exit;
  Assign(InF, InFileName);
  Reset(InF, 1);
  ReadDBFHeader(InF, Header);
  OutHeader := Header;
  OutHeader.RecordCount := 0;

  if not DatabasePath(OutFileName, OutFileName) then
  begin
    Close(InF);
    Exit;
  end;
  Assign(OutF, OutFileName);
  Rewrite(OutF, 1);
  WriteDBFHeader(OutF, OutHeader);

  { Allocate memory for row buffer and smart values }
  GetMem(Buf, Header.RecordSize);
  Values := AllocateSmartValueArray(Header);
  
  RowCount := GetActualDBFRowCount(InF, Header);
  SeekToFirstRow(InF, Header);
  for RowIndex := 0 to RowCount - 1 do
  begin
    ReadDBFRow(InF, Buf, Header.RecordSize);
    if PByteArray(Buf)^[0] <> Ord('*') then
    begin
      { Initialize smart values array }
      for FieldIdx := 1 to Header.FieldCount do
        if not DBFFieldSetStr(Values, Header, FieldIdx, '') then ;
        
      { Extract all field values including memo block numbers }
      for FieldIdx := 1 to Header.FieldCount do
        if not DBFFieldSetStr(Values, Header, FieldIdx, TrimString(DBFFieldGetStr(Buf, Header, FieldIdx))) then ;
        
      AppendDBFRow(OutF, OutHeader, Values, Header.FieldCount);
    end;
  end;

  { Clean up allocated memory }
  if Buf <> nil then
    FreeMem(Buf, Header.RecordSize);
  if Values <> nil then
    if not FreeSmartValueArray(Values) then ;

  Close(InF);
  Close(OutF);
  DBFCompact := True;
end;

function DBFFileClearMemoFields(var Dbf: PDBFFile): Boolean;
var
  Header: TDBFHeader;
  RowIndex, RowCount: LongInt;
  FieldIdx, MemoCount, MemoIdx: Integer;
  MemoFields: array[1..DBFMaxFields] of Integer;
  Values: Pointer;
  Buf: Pointer;
begin
  if Dbf = nil then
  begin
    DBFFileClearMemoFields := False;
    Exit;
  end;
    
  if not DBFFileGetHeader(Dbf, Header) then
  begin
    DBFFileClearMemoFields := False;
    Exit;
  end;
    
  MemoCount := 0;
  for FieldIdx := 1 to Header.FieldCount do
    if UpCase(Header.Fields[FieldIdx].FieldType) = 'M' then
    begin
      Inc(MemoCount);
      MemoFields[MemoCount] := FieldIdx;
    end;
    
  if MemoCount = 0 then
  begin
    DBFFileClearMemoFields := True;
    Exit;
  end;
    
  RowCount := DBFFileGetActualRowCount(Dbf);
  Values := AllocateSmartValueArray(Header);
  GetMem(Buf, Header.RecordSize);
  
    for RowIndex := 0 to RowCount - 1 do
    begin
      if not DBFFileSeekToRow(Dbf, RowIndex) then ;
      if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then ;
    
    { Initialize smart values array }
    for FieldIdx := 1 to Header.FieldCount do
      if not DBFFieldSetStr(Values, Header, FieldIdx, '') then ;
      
    { Get all field values }
    for FieldIdx := 1 to Header.FieldCount do
      if not DBFFieldSetStr(Values, Header, FieldIdx, DBFFieldGetStr(Buf, Header, FieldIdx)) then ;
      
    { Clear memo fields }
      for MemoIdx := 1 to MemoCount do
        if not DBFFieldSetStr(Values, Header, MemoFields[MemoIdx], '0') then ;
        
      { Re-seek to current row before writing, since DBFFileReadRow advances the file position }
      if not DBFFileSeekToRow(Dbf, RowIndex) then ;
      if not DBFFileWriteRow(Dbf, Values, Header.FieldCount) then ;
    end;

  { Clean up allocated memory }
  if Values <> nil then
    if not FreeSmartValueArray(Values) then ;
  if Buf <> nil then
    FreeMem(Buf, Header.RecordSize);
  DBFFileClearMemoFields := True;
end;

end.
