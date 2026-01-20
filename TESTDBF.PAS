{ TESTDBF.PAS - DBF unit test checklist }

program TestDBF;

{$M 65520,0,350000}

uses DBF, Assert;

const
  TestFileName = 'TEST';
  ImportFileName = 'IMPORT';
  MemoFileName = 'MEMO';
  CompactFileName = 'COMPACT';

var
  Row1Memo: string;
  Row2Memo: string;
  Row3Memo: string;
  GlobalRow: TDBFRow;
  GlobalValues: TDBFValues;

procedure SetField(var Header: TDBFHeader; Index: Integer; Name: string;
  FieldType: Char; Len, Dec: Byte);
begin
  Header.Fields[Index].Name := Name;
  Header.Fields[Index].FieldType := FieldType;
  Header.Fields[Index].Length := Len;
  Header.Fields[Index].Decimals := Dec;
end;

procedure InitTestHeader(var Header: TDBFHeader);
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.Version := $05;
  Header.TableFlags := 0;
  Header.LanguageDriver := DBFLangUS;
  Header.FieldCount := 6;
  SetField(Header, 1, 'TEXT', 'C', 10, 0);
  SetField(Header, 2, 'NUMBER', 'N', 3, 0);
  SetField(Header, 3, 'DECIMAL', 'N', 4, 1);
  SetField(Header, 4, 'FLAG', 'L', 1, 0);
  SetField(Header, 5, 'DATE', 'D', 8, 0);
  SetField(Header, 6, 'MEMO', 'M', 2, 0);
end;

procedure InitMemoHeader(var Header: TDBFHeader);
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.Version := $05;
  Header.TableFlags := 0;
  Header.LanguageDriver := DBFLangUS;
  Header.FieldCount := 1;
  SetField(Header, 1, 'MEMO', 'M', 2, 0);
end;

procedure ComputeHeaderSizes(var Header: TDBFHeader);
var
  I: Integer;
  Offs: Word;
begin
  Offs := 1;
  for I := 1 to Header.FieldCount do
  begin
    Header.Fields[I].Offset := Offs;
    Inc(Offs, Header.Fields[I].Length);
  end;
  Header.RecordSize := Offs;
  Header.HeaderSize := 32 + (Header.FieldCount * 32) + 1;
end;

procedure CopyTextFile(SrcName, DstName: string);
var
  InF, OutF: Text;
  Line: string;
begin
  Assign(InF, SrcName);
  Reset(InF);
  Assign(OutF, DstName);
  Rewrite(OutF);
  while not Eof(InF) do
  begin
    ReadLn(InF, Line);
    WriteLn(OutF, Line);
  end;
  Close(InF);
  Close(OutF);
end;

procedure CopyBinaryFile(SrcName, DstName: string);
var
  InF, OutF: File;
  Buf: array[1..4096] of Byte;
  ReadLen: Word;
begin
  Assign(InF, SrcName);
  Reset(InF, 1);
  Assign(OutF, DstName);
  Rewrite(OutF, 1);
  repeat
    BlockRead(InF, Buf, SizeOf(Buf), ReadLen);
    if ReadLen > 0 then
      BlockWrite(OutF, Buf, ReadLen);
  until ReadLen = 0;
  Close(InF);
  Close(OutF);
end;

function LineStartsWith(Line, Prefix: string): Boolean;
begin
  if Length(Line) < Length(Prefix) then
    LineStartsWith := False
  else
    LineStartsWith := Copy(Line, 1, Length(Prefix)) = Prefix;
end;

function ParseMemoMetaLine(Line: string; var RowIdx, FieldIdx, MemoType, BlockNum: LongInt): Boolean;
var
  Part: Integer;
  I: Integer;
  S: string[40];
  Code: Integer;
  Vals: array[1..4] of LongInt;
  Done: Boolean;
begin
  Part := 1;
  S := '';
  Done := False;
  for I := 1 to Length(Line) do
  begin
    if Line[I] = '|' then
    begin
      if Part <= 4 then
      begin
        Val(S, Vals[Part], Code);
        if Code <> 0 then
          Vals[Part] := -1;
      end;
      Inc(Part);
      S := '';
      if Part > 4 then
        Done := True;
    end
    else
      S := S + Line[I];
    if Done then
      I := Length(Line);
  end;
  if Part >= 5 then
  begin
    RowIdx := Vals[1];
    FieldIdx := Vals[2];
    MemoType := Vals[3];
    BlockNum := Vals[4];
    ParseMemoMetaLine := (RowIdx >= 0) and (FieldIdx > 0) and (BlockNum >= 0);
  end
  else
    ParseMemoMetaLine := False;
end;

function HeadersMatch(var A, B: TDBFHeader): Boolean;
var
  I: Integer;
  Ok: Boolean;
begin
  Ok := (A.Version = B.Version) and
        (A.Year = B.Year) and
        (A.Month = B.Month) and
        (A.Day = B.Day) and
        (A.RecordCount = B.RecordCount) and
        (A.HeaderSize = B.HeaderSize) and
        (A.RecordSize = B.RecordSize) and
        (A.LanguageDriver = B.LanguageDriver) and
        (A.TableFlags = B.TableFlags) and
        (A.FieldCount = B.FieldCount);
  if Ok then
    for I := 1 to A.FieldCount do
      Ok := Ok and
        (A.Fields[I].Name = B.Fields[I].Name) and
        (A.Fields[I].FieldType = B.Fields[I].FieldType) and
        (A.Fields[I].Length = B.Fields[I].Length) and
        (A.Fields[I].Decimals = B.Fields[I].Decimals) and
        (A.Fields[I].Offset = B.Fields[I].Offset);
  HeadersMatch := Ok;
end;

procedure TestHeaderMatch(var A, B: TDBFHeader);
begin
  BeginTest('Header match Test');
  AssertTrue(HeadersMatch(A, B), 'All fields match');
  EndTest;
end;

type
  TFieldNameBuf = array[1..11] of Char;
  TByteArray = array[0..65520] of Byte;
  PByteArray = ^TByteArray;

function UpcaseString(S: string): string;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    S[I] := UpCase(S[I]);
  UpcaseString := S;
end;

function LongToStrLocal(Value: LongInt): string;
var
  S: string;
begin
  Str(Value, S);
  LongToStrLocal := S;
end;

function WriteMemo(Text: string): string;
var
  StartBlock: LongInt;
begin
  DBFMemoWrite(TestFileName + '.DBT', 1, Text, StartBlock);
  WriteMemo := LongToStrLocal(StartBlock);
end;

procedure AssertMemoTextFile(MemoFileName, BlockStr, Expected, LabelStr: string);
var
  Block: LongInt;
  MemoType: LongInt;
  Text: string;
  Ok: Boolean;
begin
  Block := ParseInt(BlockStr);
  Ok := DBFMemoReadSmall(MemoFileName, Block, MemoType, Text);
  AssertTrue(Ok, LabelStr + ' read');
  if Ok then
    AssertEqualsStr(Expected, Text, LabelStr + ' text');
end;

procedure AssertMemoText(BlockStr, Expected, LabelStr: string);
begin
  AssertMemoTextFile(TestFileName + '.DBT', BlockStr, Expected, LabelStr);
end;

procedure AssertNoMemoFile(MemoFileName, BlockStr, LabelStr: string);
var
  Block: LongInt;
  MemoType: LongInt;
  Text: string;
  Ok: Boolean;
begin
  Block := ParseInt(BlockStr);
  Ok := DBFMemoReadSmall(MemoFileName, Block, MemoType, Text);
  AssertFalse(Ok, LabelStr + ' no memo');
end;

procedure AssertNoMemo(BlockStr, LabelStr: string);
begin
  AssertNoMemoFile(TestFileName + '.DBT', BlockStr, LabelStr);
end;

procedure AssertMemoBinaryFile(MemoFileName, BlockStr: string; var Expected; Len: Word; LabelStr: string);
var
  Block: LongInt;
  MemoType: LongInt;
  MemoLen: LongInt;
  ReadLen: Word;
  ReadBuf: array[1..64] of Byte;
  I: Integer;
  Ok: Boolean;
  P: PByteArray;
  ExpByte: Integer;
begin
  Block := ParseInt(BlockStr);
  Ok := DBFMemoGetInfo(MemoFileName, Block, MemoType, MemoLen);
  AssertTrue(Ok, LabelStr + ' info');
  AssertEqualsInt(2, MemoType, LabelStr + ' type');
  AssertEqualsInt(Len, MemoLen, LabelStr + ' len');
  FillChar(ReadBuf, SizeOf(ReadBuf), 0);
  Ok := DBFMemoReadChunk(MemoFileName, Block, 0, ReadBuf, Len, ReadLen);
  AssertTrue(Ok, LabelStr + ' read');
  AssertEqualsInt(Len, ReadLen, LabelStr + ' read len');
  P := @Expected;
  for I := 1 to Len do
  begin
    ExpByte := P^[I - 1];
    AssertEqualsInt(P^[I - 1], ReadBuf[I], LabelStr + ' byte');
    if ExpByte <> ReadBuf[I] then
      WriteLn('MEMO DBG: block=', Block, ' idx=', I, ' exp=', ExpByte, ' got=', ReadBuf[I]);
  end;
end;

procedure AssertMemoBinary(BlockStr: string; var Expected; Len: Word; LabelStr: string);
begin
  AssertMemoBinaryFile(TestFileName + '.DBT', BlockStr, Expected, Len, LabelStr);
end;

function FieldNameFromBytes(var Buf: TFieldNameBuf): string;
var
  I: Integer;
  S: string;
begin
  S := '';
  I := 1;
  while (I <= 11) and (Buf[I] <> #0) do
  begin
    S := S + Buf[I];
    Inc(I);
  end;
  FieldNameFromBytes := S;
end;

procedure CheckFieldDescriptor(FileName: string; FieldCount: Integer;
  FieldName: string; ExpectedType: Char; ExpectFound: Boolean);
var
  F: File;
  I: Integer;
  NameBuf: TFieldNameBuf;
  FieldType: Char;
  Found: Boolean;
  TypeOk: Boolean;
  NameStr: string;
begin
  Found := False;
  TypeOk := False;
  Assign(F, FileName);
  Reset(F, 1);
  for I := 1 to FieldCount do
  begin
    Seek(F, 32 + (I - 1) * 32);
    BlockRead(F, NameBuf, 11);
    BlockRead(F, FieldType, 1);
    NameStr := FieldNameFromBytes(NameBuf);
    if UpcaseString(NameStr) = UpcaseString(FieldName) then
    begin
      Found := True;
      TypeOk := (FieldType = ExpectedType);
    end;
  end;
  Close(F);
  if ExpectFound then
  begin
    AssertTrue(Found, 'Field "' + FieldName + '" found');
    if Found then
      AssertTrue(TypeOk, 'Field "' + FieldName + '" type');
  end
  else
    AssertTrue(not Found, 'Field "' + FieldName + '" not found');
end;

procedure TestFieldDescriptor(Hdr: TDBFHeader);
var
   DBFFileName: string;
begin
  BeginTest('Checking Field Descriptions');
  DBFFileName := TestFileName + '.DBF';
  CheckFieldDescriptor(DBFFileName, Hdr.FieldCount, 'TEXT', 'C', True);
  CheckFieldDescriptor(DBFFileName, Hdr.FieldCount, 'NUMBER', 'N', True);
  CheckFieldDescriptor(DBFFileName, Hdr.FieldCount, 'DECIMAL', 'N', True);
  CheckFieldDescriptor(DBFFileName, Hdr.FieldCount, 'FLAG', 'L', True);
  CheckFieldDescriptor(DBFFileName, Hdr.FieldCount, 'DATE', 'D', True);
  CheckFieldDescriptor(DBFFileName, Hdr.FieldCount, 'MEMO', 'M', True);
  CheckFieldDescriptor(DBFFileName, Hdr.FieldCount, 'UNKNOWN', ' ', False);

  EndTest;
end;

procedure TestRawHeader32(FileName: string; Hdr: TDBFHeader);
var
  F: File; 
  Raw: array[1..32] of Byte;
  Ok: Boolean;
begin
  BeginTest('Header bytes Test');
  { Open file }
  Assign(F, FileName);

  { Verify first 32 bytes match header properties }
  Reset(F, 1);
  BlockRead(F, Raw, 32);
  Close(F);

  Ok := (Raw[1] = Hdr.Version) and
        (Raw[2] = Hdr.Year) and
        (Raw[3] = Hdr.Month) and
        (Raw[4] = Hdr.Day) and
        (Raw[5] = (Hdr.RecordCount and $FF)) and
        (Raw[6] = ((Hdr.RecordCount shr 8) and $FF)) and
        (Raw[7] = ((Hdr.RecordCount shr 16) and $FF)) and
        (Raw[8] = ((Hdr.RecordCount shr 24) and $FF)) and
        (Raw[9] = (Hdr.HeaderSize and $FF)) and
        (Raw[10] = ((Hdr.HeaderSize shr 8) and $FF)) and
        (Raw[11] = (Hdr.RecordSize and $FF)) and
        (Raw[12] = ((Hdr.RecordSize shr 8) and $FF)) and
        (Raw[29] = Hdr.TableFlags) and
        (Raw[30] = Hdr.LanguageDriver);
  AssertTrue(Ok, 'matches header bytes');
  EndTest;
end;

procedure TestHeaderTerminator(FileName: string; Hdr: TDBFHeader);
var
  F: File; 
  HeaderTerm: Byte;
begin
  BeginTest('Header terminator Test');
  Assign(F, FileName);
  Reset(F, 1);
  Seek(F, Hdr.HeaderSize - 1);
  BlockRead(F, HeaderTerm, 1);
  Close(F);

  AssertTrue(HeaderTerm = $0D, 'header terminator byte');
  EndTest;
end;

procedure TestHeaderDate(var DbfFile: PDBFFile; FileName: string);
var
  Y, M, D: Byte;
  F: File;
  Raw: array[1..4] of Byte;
  Ok: Boolean;
begin
  BeginTest('Header date set/get');
  DBFFileSetDate(DbfFile, 24, 1, 15);
  DBFFileGetDate(DbfFile, Y, M, D);
  Ok := (Y = 24) and (M = 1) and (D = 15);
  AssertTrue(Ok, 'date set/get');
  AssertTrue(DBFFileIsDateOlder(DbfFile, 24, 1, 16), 'is older vs next day');
  AssertTrue(not DBFFileIsDateOlder(DbfFile, 24, 1, 14), 'not older vs prev day');

  Assign(F, FileName);
  Reset(F, 1);
  BlockRead(F, Raw, 4);
  Close(F);
  Ok := (Raw[2] = 24) and (Raw[3] = 1) and (Raw[4] = 15);
  AssertTrue(Ok, 'date bytes');
  EndTest;
end;

procedure TestHeaderLanguageDriver(var DbfFile: PDBFFile; FileName: string);
var
  Lang: Byte;
  F: File;
  Raw: array[1..30] of Byte;
  Ok: Boolean;
begin
  BeginTest('Header language driver');
  DBFFileSetLanguageDriver(DbfFile, DBFLangWesternEurope);
  DBFFileGetLanguageDriver(DbfFile, Lang);
  Ok := (Lang = DBFLangWesternEurope);
  AssertTrue(Ok, 'language set/get');

  Assign(F, FileName);
  Reset(F, 1);
  BlockRead(F, Raw, 30);
  Close(F);
  Ok := (Raw[30] = DBFLangWesternEurope);
  AssertTrue(Ok, 'language byte');
  EndTest;
end;

procedure TestParseHelpers;
begin
  BeginTest('Parse/trim helpers');
  AssertEqualsStr('hi', TrimString('  hi  '), 'trim');
  AssertEqualsStr('hi  ', PadString('hi', 4), 'pad');
  AssertEqualsStr('hi', PadString('hi', 2), 'pad equal');
  AssertEqualsStr('hi', PadString('hi   ', 2), 'pad trim');
  AssertEqualsInt(42, ParseInt(' 42 '), 'parse int');
  AssertEqualsInt(7, ParseWord(' 7 '), 'parse word');
  AssertEqualsInt(255, ParseByte('255'), 'parse byte');
  AssertTrue(ParseBool('T'), 'parse bool T');
  AssertTrue(ParseBool('y'), 'parse bool y');
  AssertTrue(ParseBool('1'), 'parse bool 1');
  AssertFalse(ParseBool('f'), 'parse bool f');
  EndTest;
end;

procedure SetRowValues(var Values: TDBFValues; Text, Num, Dec, Flag, DateStr, MemoStr: string);
begin
  FillChar(Values, SizeOf(Values), 0);
  Values[1] := Text;
  Values[2] := Num;
  Values[3] := Dec;
  Values[4] := Flag;
  Values[5] := DateStr;
  Values[6] := MemoStr;
end;

procedure AssertRowValues(var DbfFile: PDBFFile; var Buf: TDBFRow;
  Text, Num, Dec, Flag, DateStr, MemoStr: string);
begin
  AssertEqualsStr(Text, TrimString(DBFFileGetFieldStr(Buf, DbfFile, 1)), 'row text');
  AssertEqualsStr(Num, TrimString(DBFFileGetFieldStr(Buf, DbfFile, 2)), 'row number');
  AssertEqualsStr(Dec, TrimString(DBFFileGetFieldStr(Buf, DbfFile, 3)), 'row decimal');
  AssertEqualsStr(Flag, TrimString(DBFFileGetFieldStr(Buf, DbfFile, 4)), 'row flag');
  AssertEqualsStr(DateStr, TrimString(DBFFileGetFieldStr(Buf, DbfFile, 5)), 'row date');
  AssertEqualsStr(MemoStr, TrimString(DBFFileGetFieldStr(Buf, DbfFile, 6)), 'row memo');
end;

procedure TestRowAppendOne(var DbfFile : PDBFFile);
begin
  BeginTest('Append One');

  Row1Memo := WriteMemo('Memo alpha');
  AssertTrue(ParseInt(Row1Memo) > 0, 'memo alpha');
  SetRowValues(GlobalValues, 'ALPHA', '1', '2.2', 'T', '20240115', Row1Memo);
  DBFFileAppendRow(DbfFile, GlobalValues);
  DBFFileSeekToRow(DbfFile, 0);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertRowValues(DbfFile, GlobalRow, 'ALPHA', '1', '2.2', 'T', '20240115', Row1Memo);
  AssertMemoText(Row1Memo, 'Memo alpha', 'memo alpha');

  EndTest;
end;

procedure TestRowAppend(var DbfFile: PDBFFile);
var
  RowCount: LongInt;
  Hdr: TDBFHeader;
  Ok: Boolean;
begin
  BeginTest('Append');

  Ok := DBFFileGetHeader(DbfFile, Hdr);
  AssertTrue(Ok, 'append header');
  if Ok then
  begin
    AssertEqualsInt(10, Hdr.Fields[1].Length, 'len text');
    AssertEqualsInt(3, Hdr.Fields[2].Length, 'len number');
    AssertEqualsInt(4, Hdr.Fields[3].Length, 'len decimal');
    AssertEqualsInt(1, Hdr.Fields[4].Length, 'len flag');
    AssertEqualsInt(8, Hdr.Fields[5].Length, 'len date');
    AssertEqualsInt(2, Hdr.Fields[6].Length, 'len memo');
    AssertEqualsInt(1, Hdr.Fields[1].Offset, 'offset text');
    AssertEqualsInt(11, Hdr.Fields[2].Offset, 'offset number');
    AssertEqualsInt(14, Hdr.Fields[3].Offset, 'offset decimal');
    AssertEqualsInt(18, Hdr.Fields[4].Offset, 'offset flag');
    AssertEqualsInt(19, Hdr.Fields[5].Offset, 'offset date');
    AssertEqualsInt(27, Hdr.Fields[6].Offset, 'offset memo');
    AssertEqualsInt(29, Hdr.RecordSize, 'record size');
  end;

  Row2Memo := WriteMemo('Memo bravo');
  AssertTrue(ParseInt(Row2Memo) > 0, 'memo bravo');
  SetRowValues(GlobalValues, 'BRAVO', '33', '4.4', 'F', '20240216', Row2Memo);
  DBFFileAppendRow(DbfFile, GlobalValues);
  DBFFileSeekToRow(DbfFile, 1);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertRowValues(DbfFile, GlobalRow, 'BRAVO', '33', '4.4', 'F', '20240216', Row2Memo);
  AssertMemoText(Row2Memo, 'Memo bravo', 'memo bravo');

  Row3Memo := WriteMemo('Memo charlie');
  AssertTrue(ParseInt(Row3Memo) > 0, 'memo charlie');
  SetRowValues(GlobalValues, 'CHARLIE', '555', '16.6', 'T', '20240317', Row3Memo);
  DBFFileAppendRow(DbfFile, GlobalValues);
  DBFFileSeekToRow(DbfFile, 2);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertRowValues(DbfFile, GlobalRow, 'CHARLIE', '555', '16.6', 'T', '20240317', Row3Memo);
  AssertMemoText(Row3Memo, 'Memo charlie', 'memo charlie');

  SetRowValues(GlobalValues, 'DELTA', '7', '0.7', 'F', '20240418', '0');
  DBFFileAppendRow(DbfFile, GlobalValues);
  DBFFileSeekToRow(DbfFile, 3);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertRowValues(DbfFile, GlobalRow, 'DELTA', '7', '0.7', 'F', '20240418', '0');
  AssertNoMemo('0', 'memo delta');

  EndTest;
end;

procedure TestRowSeek(var DbfFile : PDBFFile);
var
  RowCount: LongInt;
begin
  BeginTest('Seek');

  DBFFileSeekToFirstRow(DbfFile);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertRowValues(DbfFile, GlobalRow, 'ALPHA', '1', '2.2', 'T', '20240115', Row1Memo);
  AssertMemoText(Row1Memo, 'Memo alpha', 'memo alpha');
  RowCount := DBFFileGetActualRowCount(DbfFile);
  AssertTrue(RowCount > 0, 'row count > 0');
  if RowCount > 0 then
  begin
    DBFFileSeekToRow(DbfFile, RowCount - 1);
    DBFFileReadRow(DbfFile, GlobalRow);
    AssertRowValues(DbfFile, GlobalRow, 'DELTA', '7', '0.7', 'F', '20240418', '0');
    AssertNoMemo('0', 'memo delta');
  end;

  EndTest;
end;

procedure TestRowDelete(var DbfFile: PDBFFile);
var
  RowCount: LongInt;
begin
  BeginTest('Delete');

  DBFFileSetRowDeleted(DbfFile, 1, True);
  DBFFileSeekToRow(DbfFile, 1);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertEqualsInt(Ord('*'), GlobalRow[0], 'row deleted');

  DBFFileSetRowDeleted(DbfFile, 1, False);
  DBFFileSeekToRow(DbfFile, 1);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertEqualsInt(Ord(' '), GlobalRow[0], 'row undeleted');

  RowCount := DBFFileGetActualRowCount(DbfFile);
  AssertEqualsInt(4, RowCount, 'row count');

  EndTest;
end;

procedure TestRowUpdate(var DbfFile: PDBFFile);
var
  RowCount: LongInt;
begin
  BeginTest('Update');

  DBFFileSeekToRow(DbfFile, 2);
  Row3Memo := WriteMemo('Memo lambda');
  AssertTrue(ParseInt(Row3Memo) > 0, 'memo lambda');
  SetRowValues(GlobalValues, 'LAMBDA', '909', '28.8', 'F', '20200103', Row3Memo);
  DBFFileWriteRow(DbfFile, GlobalValues);
  DBFFileSeekToRow(DbfFile, 2);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertRowValues(DbfFile, GlobalRow, 'LAMBDA', '909', '28.8', 'F', '20200103', Row3Memo);
  AssertMemoText(Row3Memo, 'Memo lambda', 'memo lambda');

  EndTest;
end;

procedure TestRowUpdateByField(var DbfFile: PDBFFile);
var
  I: Integer;
begin
  BeginTest('Update by field');

  DBFFileSeekToRow(DbfFile, 1);
  DBFFileReadRow(DbfFile, GlobalRow);
  DBFFileSetFieldStr(GlobalRow, DbfFile, 1, 'BRAVO2');
  DBFFileSetFieldStr(GlobalRow, DbfFile, 3, '7.7');
  DBFFileSetFieldStr(GlobalRow, DbfFile, 4, 'T');
  Row2Memo := WriteMemo('Memo bravo updated');
  AssertTrue(ParseInt(Row2Memo) > 0, 'memo bravo updated');
  DBFFileSetFieldStr(GlobalRow, DbfFile, 6, Row2Memo);

  FillChar(GlobalValues, SizeOf(GlobalValues), 0);
  for I := 1 to 6 do
    GlobalValues[I] := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, I));

  DBFFileSeekToRow(DbfFile, 1);
  DBFFileWriteRow(DbfFile, GlobalValues);
  DBFFileSeekToRow(DbfFile, 1);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertRowValues(DbfFile, GlobalRow, 'BRAVO2', '33', '7.7', 'T', '20240216', Row2Memo);
  AssertMemoText(Row2Memo, 'Memo bravo updated', 'memo bravo updated');

  EndTest;
end;

procedure TestFileTerminator(FileName: string);
var
  F: File; 
  EndByte: Byte;
begin
  BeginTest('Terminator byte Test');
  Assign(F, FileName);
  Reset(F, 1);
  Seek(F, FileSize(F) - 1);
  BlockRead(F, EndByte, 1);
  Close(F);

  AssertTrue(EndByte = $1A, 'file terminator byte');
  EndTest;
end;

procedure TestDbfOnDisk(FileName: string; Hdr: TDBFHeader);
begin
  WriteLn('Testing DBF file on disk: ' + FileName);
  TestRawHeader32(FileName, Hdr);
  TestHeaderTerminator(FileName, Hdr);
  TestFileTerminator(FileName);
end;

procedure TestCreateDBF(FileName: string; Header: TDBFHeader);
var
  DbfFile: PDBFFile;
begin
  DbfFile := nil;
  DBFFileCreate(DbfFile, FileName, Header);
  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
end;

procedure TestExportEmptyTable;
var
  F: Text;
  Line: string;
  LineCount: Integer;
  DBFFileName: string;
begin
  DBFFileName := TestFileName + '.DBF';

  BeginTest('Export empty table using ' + DBFFileName);
  ExportDBFToText(TestFileName);
  LineCount := 0;
  Assign(F, TestFileName + '.TXT');
  Reset(F);

  WriteLn('Starting empty export assertions...');
  ReadLn(F, Line);
  LineCount := LineCount + 1;
  AssertEqualsStr('TEXT|NUMBER|DECIMAL|FLAG|DATE|MEMO', Line, 'Line 1 matches');

  ReadLn(F, Line);
  LineCount := LineCount + 1;
  AssertEqualsStr('C(10)|N(3)|N(4,1)|L(1)|D(8)|M(2)', Line, 'Line 2 matches');

  AssertTrue(Eof(F), 'At end of file');
  Close(F);
  AssertEqualsInt(2, LineCount, 'export line count');
  EndTest;
  WriteLn('Completed empty export assertions...');
end;

procedure TestImportEmptyTable(ExpectedHdr: TDBFHeader);
var
  ImportDbf: PDBFFile;
  ImportHeader: TDBFHeader;
  Ok: Boolean;
  RowCount: LongInt;
  DBFImportFileName : string;
begin
  DBFImportFileName := ImportFileName + '.DBF'; 
  ImportDbf := nil;
  WriteLn('Starting import of empty table to ' + DBFImportFileName);
  ImportDBFFromText(ImportFileName);
  WriteLn('Testing imported DBF on disk ' + DBFImportFileName);
  TestDbfOnDisk(DBFImportFileName, ExpectedHdr);

  BeginTest('Import empty table');
  DBFFileOpen(ImportDbf, DBFImportFileName);
  Ok := DBFFileGetHeader(ImportDbf, ImportHeader);
  AssertTrue(Ok, 'import header read');
  if Ok then
    AssertTrue(HeadersMatch(ExpectedHdr, ImportHeader), 'import header match');
  RowCount := DBFFileGetActualRowCount(ImportDbf);
  AssertEqualsInt(0, RowCount, 'import row count');
  DBFFileClose(ImportDbf);
  DBFFileDispose(ImportDbf);
  EndTest;
end;

procedure TestMemoReadWrite(FileName: string);
var
  StartBlock: LongInt;
  MemoType: LongInt;
  MemoText: string;
  ReadType: LongInt;
  ReadText: string;
  MemoLen: LongInt;
  Buf: array[1..64] of Byte;
  Offset: LongInt;
  ReadLen: Word;
  I: Integer;
  Ok: Boolean;
begin
  BeginTest('Memo write/read');
  MemoType := 1;
  MemoText := 'Sample memo text';
  DBFMemoWrite(FileName, MemoType, MemoText, StartBlock);
  AssertTrue(StartBlock > 0, 'memo start block');
  Ok := DBFMemoGetInfo(FileName, StartBlock, ReadType, MemoLen);
  AssertTrue(Ok, 'memo info');
  AssertEqualsInt(MemoType, ReadType, 'memo type');
  ReadText := '';
  Offset := 0;
  while (Offset < MemoLen) and Ok do
  begin
    Ok := DBFMemoReadChunk(FileName, StartBlock, Offset, Buf, SizeOf(Buf), ReadLen);
    AssertTrue(Ok, 'memo read chunk');
    for I := 1 to ReadLen do
      ReadText := ReadText + Chr(Buf[I]);
    Inc(Offset, ReadLen);
    if ReadLen = 0 then
      Offset := MemoLen;
  end;
  AssertEqualsStr(MemoText, ReadText, 'memo text');
  EndTest;
end;

procedure TestMemoReadSmall(FileName : string);
var
  StartBlock: LongInt;
  MemoType: LongInt;
  MemoText: string;
  ReadType: LongInt;
  ReadText: string;
  Ok: Boolean;
begin
  BeginTest('Memo read small');
  MemoType := 1;
  MemoText := 'Short memo text';
  DBFMemoWrite(FileName, MemoType, MemoText, StartBlock);
  Ok := DBFMemoReadSmall(FileName, StartBlock, ReadType, ReadText);
  AssertTrue(Ok, 'memo read small');
  AssertEqualsInt(MemoType, ReadType, 'memo type');
  AssertEqualsStr(MemoText, ReadText, 'memo text');
  EndTest;
end;

procedure TestMemoReadBuffer(FileName: string);
var
  StartBlock: LongInt;
  MemoType: LongInt;
  MemoText: string;
  ReadType: LongInt;
  Buf: array[1..64] of Byte;
  ReadLen: Word;
  ReadText: string;
  I: Integer;
  Ok: Boolean;
begin
  BeginTest('Memo read buffer');
  MemoType := 1;
  MemoText := 'Medium memo text';
  DBFMemoWrite(FileName, MemoType, MemoText, StartBlock);
  Ok := DBFMemoReadBuffer(FileName, StartBlock, ReadType, Buf, SizeOf(Buf), ReadLen);
  AssertTrue(Ok, 'memo read buffer');
  AssertEqualsInt(MemoType, ReadType, 'memo type');
  ReadText := '';
  for I := 1 to ReadLen do
    ReadText := ReadText + Chr(Buf[I]);
  AssertEqualsStr(MemoText, ReadText, 'memo text');
  EndTest;
end;

procedure TestMemoBinary(FileName: string);
var
  StartBlock: LongInt;
  MemoType: LongInt;
  ReadType: LongInt;
  MemoLen: LongInt;
  Buf: array[1..8] of Byte;
  ReadBuf: array[1..8] of Byte;
  ReadLen: Word;
  I: Integer;
  Ok: Boolean;
begin
  BeginTest('Memo binary');
  MemoType := 2;
  Buf[1] := $00;
  Buf[2] := $01;
  Buf[3] := $7F;
  Buf[4] := $80;
  Buf[5] := $FF;
  Buf[6] := $10;
  Buf[7] := $20;
  Buf[8] := $30;
  DBFMemoWriteBuffer(FileName, MemoType, Buf, SizeOf(Buf), StartBlock);
  Ok := DBFMemoGetInfo(FileName, StartBlock, ReadType, MemoLen);
  AssertTrue(Ok, 'memo info');
  AssertEqualsInt(MemoType, ReadType, 'memo type');
  AssertEqualsInt(SizeOf(Buf), MemoLen, 'memo len');
  FillChar(ReadBuf, SizeOf(ReadBuf), 0);
  Ok := DBFMemoReadChunk(FileName, StartBlock, 0, ReadBuf, SizeOf(ReadBuf), ReadLen);
  AssertTrue(Ok, 'memo read chunk');
  AssertEqualsInt(SizeOf(Buf), ReadLen, 'memo read len');
  for I := 1 to 8 do
    AssertEqualsInt(Buf[I], ReadBuf[I], 'memo byte');
  EndTest;
end;

procedure PrepTestDatabaseForExport(FileName: string);
var
  DbfFile: PDBFFile;
  BinBuf: array[1..8] of Byte;
  BinBlock: LongInt;
  I: Integer;
begin
  DbfFile := nil;
  DBFFileOpen(DbfFile, FileName + '.DBF');

  { Add a new memo entry for row 2 }
  BinBuf[1] := $00;
  BinBuf[2] := $01;
  BinBuf[3] := $7F;
  BinBuf[4] := $80;
  BinBuf[5] := $FF;
  BinBuf[6] := $10;
  BinBuf[7] := $20;
  BinBuf[8] := $30;
  DBFMemoWriteBuffer(FileName + '.DBT', 2, BinBuf, SizeOf(BinBuf), BinBlock);

  { Update the memo block number in row 2 }
  DBFFileSeekToRow(DbfFile, 2);
  DBFFileReadRow(DbfFile, GlobalRow);
  DBFFileSetFieldStr(GlobalRow, DbfFile, 6, LongToStrLocal(BinBlock));
  FillChar(GlobalValues, SizeOf(GlobalValues), 0);
  for I := 1 to 6 do
    GlobalValues[I] := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, I));
  DBFFileSeekToRow(DbfFile, 2);
  DBFFileWriteRow(DbfFile, GlobalValues);
  
  { Delete row 0 }
  DBFFileSetRowDeleted(DbfFile, 0, True);
  
  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
end;

procedure TestMemoExportImport;
var
  DbfFile: PDBFFile;
  MemoField: string;
  BinBuf: array[1..8] of Byte;
  RowCount: LongInt;
  DBFFileName: string;
  DBTFileName: string;
begin
  BeginTest('Memo export/import');
  DBFFileName := TestFileName + '.DBF';
  DBTFileName := TestFileName + '.DBT';

  ExportDBFToText(TestFileName);
  CopyTextFile(TestFileName + '.TXT', ImportFileName + '.TXT');
  ImportDBFFromText(ImportFileName);

  ExportDBFMemosToText(TestFileName);
  CopyTextFile(TestFileName + '.MEM', ImportFileName + '.MEM');

  WriteLn('Clearing memo fields...');
  DbfFile := nil;
  DBFFileOpen(DbfFile, ImportFileName + '.DBF');
  RowCount := DBFFileGetActualRowCount(DbfFile);
  AssertEqualsInt(3, RowCount, 'import row count');

  DBFFileClearMemoFields(DbfFile);
  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);

  ImportDBFMemosFromText(ImportFileName);

  DbfFile := nil;
  DBFFileOpen(DbfFile, ImportFileName + '.DBF');
  DBFFileSeekToRow(DbfFile, 0);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertEqualsStr('BRAVO2', TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 1)), 'import row 0 name');
  MemoField := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6));
  AssertTrue(ParseInt(MemoField) > 0, 'memo bravo block');
  AssertMemoTextFile(ImportFileName + '.DBT', MemoField, 'Memo bravo updated', 'memo bravo import');

  DBFFileSeekToRow(DbfFile, 1);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertEqualsStr('LAMBDA', TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 1)), 'import row 1 name');
  MemoField := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6));
  AssertTrue(ParseInt(MemoField) > 0, 'memo binary block');
  BinBuf[1] := $00;
  BinBuf[2] := $01;
  BinBuf[3] := $7F;
  BinBuf[4] := $80;
  BinBuf[5] := $FF;
  BinBuf[6] := $10;
  BinBuf[7] := $20;
  BinBuf[8] := $30;
  AssertMemoBinaryFile(ImportFileName + '.DBT', MemoField, BinBuf, SizeOf(BinBuf), 'memo binary import');

  DBFFileSeekToRow(DbfFile, 2);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertEqualsStr('DELTA', TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 1)), 'import row 2 name');
  MemoField := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6));
  AssertEqualsStr('0', MemoField, 'memo delta block');
  AssertNoMemoFile(ImportFileName + '.DBT', MemoField, 'memo delta import');

  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
  EndTest;
end;

procedure TestMemoExportImportPreserve;
var
  F: Text;
  Line: string;
  RowIdx, FieldIdx, MemoType, BlockNum: LongInt;
  BlockByRow: array[0..2] of LongInt;
  HasBlock: array[0..2] of Boolean;
  DbfFile: PDBFFile;
begin
  BeginTest('Memo export/import preserve');
  ExportDBFToText(TestFileName);
  CopyTextFile(TestFileName + '.TXT', ImportFileName + '.TXT');
  ImportDBFFromText(ImportFileName);

  ExportDBFMemosToText(TestFileName);
  Assign(F, TestFileName + '.MEM');
  Reset(F);
  FillChar(HasBlock, SizeOf(HasBlock), 0);
  while not Eof(F) do
  begin
    ReadLn(F, Line);
    if ParseMemoMetaLine(Line, RowIdx, FieldIdx, MemoType, BlockNum) then
      if (RowIdx >= 0) and (RowIdx <= 2) and (FieldIdx = 6) then
      begin
        BlockByRow[RowIdx] := BlockNum;
        HasBlock[RowIdx] := True;
      end;
  end;
  Close(F);

  CopyTextFile(TestFileName + '.MEM', ImportFileName + '.MEM');
  ImportDBFMemosFromTextEx(ImportFileName, True);

  DbfFile := nil;
  DBFFileOpen(DbfFile, ImportFileName + '.DBF');
  if HasBlock[0] then
  begin
    DBFFileSeekToRow(DbfFile, 0);
    DBFFileReadRow(DbfFile, GlobalRow);
    AssertEqualsStr(LongToStrLocal(BlockByRow[0]),
      TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6)), 'preserve memo row 0');
  end;
  if HasBlock[1] then
  begin
    DBFFileSeekToRow(DbfFile, 1);
    DBFFileReadRow(DbfFile, GlobalRow);
    AssertEqualsStr(LongToStrLocal(BlockByRow[1]),
      TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6)), 'preserve memo row 1');
  end;
  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
  EndTest;
end;

procedure TestClearMemoFields;
var
  DbfFile: PDBFFile;
  MemoField: string;
  RowCount: LongInt;
  I: Integer;
  FoundMemo: Boolean;
begin
  BeginTest('Clear memo fields');
  CopyBinaryFile(TestFileName + '.DBF', ImportFileName + '.DBF');
  CopyBinaryFile(TestFileName + '.DBT', ImportFileName + '.DBT');

  DbfFile := nil;
  DBFFileOpen(DbfFile, ImportFileName + '.DBF');
  RowCount := DBFFileGetActualRowCount(DbfFile);
  AssertTrue(RowCount > 0, 'clear memo row count');

  FoundMemo := False;
  for I := 0 to RowCount - 1 do
  begin
    DBFFileSeekToRow(DbfFile, I);
    DBFFileReadRow(DbfFile, GlobalRow);
    MemoField := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6));
    if ParseInt(MemoField) > 0 then
      FoundMemo := True;
  end;
  AssertTrue(FoundMemo, 'memo set before clear');

  DBFFileClearMemoFields(DbfFile);
  for I := 0 to RowCount - 1 do
  begin
    DBFFileSeekToRow(DbfFile, I);
    DBFFileReadRow(DbfFile, GlobalRow);
    MemoField := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6));
    AssertEqualsStr('0', MemoField, 'memo cleared');
  end;

  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
  EndTest;
end;

procedure TestMemoExportSkipsDeleted;
var
  F: Text;
  Line: string;
  LineCount: Integer;
  HasRow0: Boolean;
  HasRow1: Boolean;
begin
  BeginTest('Memo export skips deleted');
  ExportDBFMemosToText(TestFileName);
  Assign(F, TestFileName + '.MEM');
  Reset(F);
  LineCount := 0;
  HasRow0 := False;
  HasRow1 := False;
  while not Eof(F) do
  begin
    ReadLn(F, Line);
    if LineStartsWith(Line, '0|6|') then
      HasRow0 := True;
    if LineStartsWith(Line, '1|6|') then
      HasRow1 := True;
    Inc(LineCount);
  end;
  Close(F);
  AssertEqualsInt(2, LineCount, 'memo export line count');
  AssertTrue(HasRow0, 'memo export includes row 0');
  AssertTrue(HasRow1, 'memo export includes row 1');
  EndTest;
end;

procedure TestCompactDBF;
var
  DbfFile: PDBFFile;
  MemoField: string;
  BinBuf: array[1..8] of Byte;
  RowCount: LongInt;
begin
  BeginTest('Compact DBF');
  CompactDBF(TestFileName, CompactFileName);

  DbfFile := nil;
  DBFFileOpen(DbfFile, CompactFileName + '.DBF');
  RowCount := DBFFileGetActualRowCount(DbfFile);
  AssertEqualsInt(3, RowCount, 'compact row count');

  DBFFileSeekToRow(DbfFile, 0);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertEqualsStr('BRAVO2', TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 1)), 'compact row 0 name');
  MemoField := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6));
  AssertTrue(ParseInt(MemoField) > 0, 'compact memo bravo block');
  AssertMemoTextFile(CompactFileName + '.DBT', MemoField, 'Memo bravo updated', 'compact memo bravo');

  DBFFileSeekToRow(DbfFile, 1);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertEqualsStr('LAMBDA', TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 1)), 'compact row 1 name');
  MemoField := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6));
  AssertTrue(ParseInt(MemoField) > 0, 'compact memo binary block');
  BinBuf[1] := $00;
  BinBuf[2] := $01;
  BinBuf[3] := $7F;
  BinBuf[4] := $80;
  BinBuf[5] := $FF;
  BinBuf[6] := $10;
  BinBuf[7] := $20;
  BinBuf[8] := $30;
  AssertMemoBinaryFile(CompactFileName + '.DBT', MemoField, BinBuf, SizeOf(BinBuf), 'compact memo binary');

  DBFFileSeekToRow(DbfFile, 2);
  DBFFileReadRow(DbfFile, GlobalRow);
  AssertEqualsStr('DELTA', TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 1)), 'compact row 2 name');
  MemoField := TrimString(DBFFileGetFieldStr(GlobalRow, DbfFile, 6));
  AssertEqualsStr('0', MemoField, 'compact memo delta block');
  AssertNoMemoFile(CompactFileName + '.DBT', MemoField, 'compact memo delta');

  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
  EndTest;
end;

{ Start Program }
var
  Header, MemoHeader: TDBFHeader;
  DbfFile: PDBFFile;
  Hdr, ReadHeader: TDBFHeader;
  Ok: Boolean;
  DBFFileName, DBTFileName : string;

begin
  ResetAsserts;
  WriteLn('Starting tests...');

  DBFFileName := TestFileName + '.DBF';
  DBTFileName := TestFileName + '.DBT';

  { Test helper methods }
  TestParseHelpers;

  WriteLn('Testing header initialization...');
  InitTestHeader(Header);
  Hdr := Header;
  ComputeHeaderSizes(Hdr);

  { Create the initial file}
  WriteLn('Creating test database...');
  TestCreateDBF(TestFileName, Header);
  TestDbfOnDisk(DBFFileName, Hdr);

  { Test open the file }    
  DbfFile := nil;
  DBFFileOpen(DbfFile, DBFFileName);

  { Test Headers match }
  BeginTest('DBFFileGetHeader');
  Ok := DBFFileGetHeader(DbfFile, ReadHeader);
  AssertTrue(Ok, 'returns True');
  EndTest;
  if Ok then
  begin
    TestHeaderMatch(Hdr, ReadHeader);
  end;

  { Test setting header date }
  TestHeaderDate(DbfFile, DBFFileName);

  { Test setting language driver }
  TestHeaderLanguageDriver(DbfFile, DBFFileName);

  { Close file }
  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
 
  { Test Field descriptions in header }
  TestFieldDescriptor(Hdr);

  { Test writing empty table from export }
  TestExportEmptyTable;

  { Test reading empty table from import }
  CopyTextFile(TestFileName + '.TXT', ImportFileName + '.TXT');
  TestImportEmptyTable(Hdr);

  { Test memo write/read }
  WriteLn('Starting memo tests...');
  InitMemoHeader(MemoHeader);
  TestCreateDBF(MemoFileName, MemoHeader);
  TestMemoReadWrite(MemoFileName + '.DBT');
  TestMemoReadSmall(MemoFileName + '.DBT');
  TestMemoReadBuffer(MemoFileName + '.DBT');
  TestMemoBinary(MemoFileName + '.DBT');

  { Open the file for record changes }    
  DbfFile := nil;
  DBFFileOpen(DbfFile, DBFFileName);

  { Test append/seek/delete/update row operations }
  TestRowAppendOne(DbfFile);
  TestRowAppend(DbfFile);
  TestRowSeek(DbfFile);
  TestRowDelete(DbfFile);
  TestRowUpdate(DbfFile);
  TestRowUpdateByField(DbfFile);

  { Close file }
  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);

  PrepTestDatabaseForExport(TestFileName);
  TestMemoExportSkipsDeleted;
  TestClearMemoFields;
  TestMemoExportImportPreserve;
  TestMemoExportImport;
  TestCompactDBF;

  PrintSummary;
end.

{ TODO: Use DBFFileGetFieldStr/SetFieldStr on a buffer. }
{ TODO: Use ExportDBFToText and ImportDBFFromText (round-trip). }
{ TODO: Clean deleted data out of main and memo table }
