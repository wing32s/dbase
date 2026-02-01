{ TESTMEMO.PAS - Comprehensive DBFMEMO module tests }

program TestMemoProgram;

{$M 32768,0,98304}  { Stack: 32KB, Heap: 96KB }

uses Assert, DBFUTIL, DBF, DBFMEMO;

const
  TestFileName = 'TMEMO';
  MemoFileName = 'TMEMO';

var
  TestDbf: PDBFFile;
  TestHeader: TDBFHeader;
  MemoHandle: PDBFMemo;

procedure SetField(var Header: TDBFHeader; Index: Integer; Name: string;
  FieldType: Char; Len, Dec: Byte);
begin
  Header.Fields[Index].Name := Name;
  Header.Fields[Index].FieldType := FieldType;
  Header.Fields[Index].Length := Len;
  Header.Fields[Index].Decimals := Dec;
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

procedure InitMemoTestHeader(var Header: TDBFHeader);
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.Version := $04;  { dBase IV - will be promoted to $05 by InitDBFHeader }
  Header.TableFlags := 0;
  Header.LanguageDriver := DBFLangUS;
  Header.FieldCount := 3;

  { Field 1: Name field }
  SetField(Header, 1, 'NAME', 'C', 20, 0);

  { Field 2: Memo field }
  SetField(Header, 2, 'NOTES', 'M', 10, 0);

  { Field 3: Second memo field }
  SetField(Header, 3, 'DETAILS', 'M', 10, 0);

  ComputeHeaderSizes(Header);
end;

{ Test 1: Verify dBase IV memo version byte }
procedure TestVersionByte;
var
  ReadHeader: TDBFHeader;
  Result: Boolean;
begin
  BeginTest('Version Byte with Memo');

  MemoryReport('Before version test');

  TestDbf := nil;
  InitMemoTestHeader(TestHeader);
  Result := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(Result, 'DBFFileCreate should succeed');

  Result := DBFFileGetHeader(TestDbf, ReadHeader);
  WriteLn('Version byte: $', ReadHeader.Version);
  AssertEqualsInt($05, ReadHeader.Version,
    'dBase IV with memo should have version $05');

  { Verify memo field type }
  AssertEqualsStr('M', ReadHeader.Fields[2].FieldType,
    'Field 2 should be memo type');
  AssertEqualsStr('M', ReadHeader.Fields[3].FieldType,
    'Field 3 should be memo type');
  AssertEqualsInt(10, ReadHeader.Fields[2].Length,
    'Memo field should have length 10');

  { Verify DBT file was created }
  AssertTrue(FileExists(MemoFileName + '.DBT'),
    'DBT memo file should be created automatically');

  Result := DBFFileClose(TestDbf);
  AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf);
  AssertTrue(Result, 'DBFFileDispose should succeed');
  TestDbf := nil;

  MemoryReport('After version test');
  EndTest;
end;

{ Test 2: DBFMemoWrite and DBFMemoReadSmall }
procedure TestMemoWriteReadSmall;
var
  StartBlock: LongInt;
  MemoType: LongInt;
  ReadText: string;
  Ok: Boolean;
begin
  BeginTest('DBFMemoWrite / DBFMemoReadSmall');

  MemoryReport('Before write/read small');

  { Write a short memo }
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'Hello, memo world!', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('DBFMemoWrite returned StartBlock=', StartBlock);
  AssertTrue(StartBlock > 0, 'StartBlock should be positive');

  { Read it back }
  Ok := DBFMemoReadSmallM(MemoHandle, StartBlock, MemoType, ReadText);
  AssertTrue(Ok, 'DBFMemoReadSmall should succeed');
  AssertEqualsInt(1, MemoType, 'MemoType should be 1 (text)');
  AssertEqualsStr('Hello, memo world!', ReadText,
    'Read text should match written text');

  MemoryReport('Memo read into memory');

  { Write empty memo }
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, '', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('Empty memo StartBlock=', StartBlock);
  AssertTrue(StartBlock > 0, 'Empty memo should still get a block');

  MemoryReport('After write/read small');
  EndTest;
end;

{ Test 3: DBFMemoGetInfo }
procedure TestMemoGetInfo;
var
  StartBlock: LongInt;
  MemoType, MemoLen: LongInt;
  Ok: Boolean;
begin
  BeginTest('DBFMemoGetInfo');

  { Write a memo with known length }
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'Test memo for info', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('Written memo at block ', StartBlock);

  Ok := DBFMemoGetInfoM(MemoHandle, StartBlock, MemoType, MemoLen);
  AssertTrue(Ok, 'DBFMemoGetInfo should succeed');
  AssertEqualsInt(1, MemoType, 'MemoType should be 1');
  AssertEqualsInt(18, MemoLen, 'MemoLen should be 18 (length of text)');

  { Test with invalid block }
  Ok := DBFMemoGetInfoM(MemoHandle, 0, MemoType, MemoLen);
  AssertFalse(Ok, 'DBFMemoGetInfo should fail for block 0');

  Ok := DBFMemoGetInfoM(MemoHandle, -1, MemoType, MemoLen);
  AssertFalse(Ok, 'DBFMemoGetInfo should fail for negative block');

  EndTest;
end;

{ Test 4: DBFMemoWriteBuffer and DBFMemoReadBuffer }
procedure TestMemoWriteReadBuffer;
var
  WriteBuf: array[1..50] of Byte;
  ReadBuf: array[1..100] of Byte;
  StartBlock: LongInt;
  MemoType: LongInt;
  ReadLen: Word;
  Ok: Boolean;
  I: Integer;
begin
  BeginTest('DBFMemoWriteBuffer / DBFMemoReadBuffer');

  MemoryReport('Before buffer write/read');

  { Fill write buffer with pattern }
  for I := 1 to 50 do
    WriteBuf[I] := I;

  AssertTrue(DBFMemoWriteBufferM(MemoHandle, 1, WriteBuf, 50, StartBlock), 'DBFMemoWriteBuffer should succeed');
  WriteLn('Buffer memo written at block ', StartBlock);
  AssertTrue(StartBlock > 0, 'StartBlock should be positive');

  { Read it back }
  FillChar(ReadBuf, SizeOf(ReadBuf), 0);
  Ok := DBFMemoReadBufferM(MemoHandle, StartBlock, MemoType, ReadBuf, 100, ReadLen);
  AssertTrue(Ok, 'DBFMemoReadBuffer should succeed');
  AssertEqualsInt(50, ReadLen, 'ReadLen should be 50');
  AssertEqualsInt(1, MemoType, 'MemoType should be 1');

  MemoryReport('Memo read into memory');

  { Verify buffer contents }
  Ok := True;
  for I := 1 to 50 do
    if ReadBuf[I] <> I then Ok := False;
  AssertTrue(Ok, 'Buffer contents should match written data');

  MemoryReport('After buffer write/read');
  EndTest;
end;

{ Test 5: DBFMemoReadChunk with offset }
procedure TestMemoReadChunk;
var
  StartBlock: LongInt;
  ReadBuf: array[1..20] of Byte;
  ReadLen: Word;
  Ok: Boolean;
  ReadStr: string;
  I: Integer;
begin
  BeginTest('DBFMemoReadChunk');

  { Write a known memo }
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('Chunk test memo at block ', StartBlock);

  { Read first 10 bytes }
  Ok := DBFMemoReadChunkM(MemoHandle, StartBlock, 0, ReadBuf, 10, ReadLen);
  AssertTrue(Ok, 'ReadChunk offset 0 should succeed');
  AssertEqualsInt(10, ReadLen, 'Should read 10 bytes');
  ReadStr := '';
  for I := 1 to ReadLen do
    ReadStr := ReadStr + Chr(ReadBuf[I]);
  AssertEqualsStr('ABCDEFGHIJ', ReadStr, 'First 10 chars should match');

  { Read from offset 10, 10 bytes }
  Ok := DBFMemoReadChunkM(MemoHandle, StartBlock, 10, ReadBuf, 10, ReadLen);
  AssertTrue(Ok, 'ReadChunk offset 10 should succeed');
  AssertEqualsInt(10, ReadLen, 'Should read 10 bytes from offset');
  ReadStr := '';
  for I := 1 to ReadLen do
    ReadStr := ReadStr + Chr(ReadBuf[I]);
  AssertEqualsStr('KLMNOPQRST', ReadStr, 'Offset 10 chars should match');

  { Read from offset 20, remaining 6 bytes }
  Ok := DBFMemoReadChunkM(MemoHandle, StartBlock, 20, ReadBuf, 20, ReadLen);
  AssertTrue(Ok, 'ReadChunk offset 20 should succeed');
  AssertEqualsInt(6, ReadLen, 'Should read remaining 6 bytes');
  ReadStr := '';
  for I := 1 to ReadLen do
    ReadStr := ReadStr + Chr(ReadBuf[I]);
  AssertEqualsStr('UVWXYZ', ReadStr, 'Remaining chars should match');

  { Read past end }
  Ok := DBFMemoReadChunkM(MemoHandle, StartBlock, 26, ReadBuf, 10, ReadLen);
  AssertTrue(Ok, 'ReadChunk past end should return True');
  AssertEqualsInt(0, ReadLen, 'ReadLen past end should be 0');

  EndTest;
end;

{ Test 6: Streaming write with DBFMemoWriteBegin/Chunk/End }
procedure TestStreamingWrite;
var
  State: TMemoWriteState;
  StartBlock: LongInt;
  MemoType, MemoLen: LongInt;
  ReadText: string;
  Chunk1: string;
  Chunk2: string;
  Chunk3: string;
  Ok: Boolean;
begin
  BeginTest('Streaming Write (Begin/Chunk/End)');

  MemoryReport('Before streaming write');

  Chunk1 := 'First part. ';
  Chunk2 := 'Second part. ';
  Chunk3 := 'Third part.';
  { Total = 12 + 13 + 11 = 36 bytes }

  AssertTrue(DBFMemoWriteBeginM(MemoHandle, 1, 36, StartBlock, State), 'DBFMemoWriteBegin should succeed');
  WriteLn('Streaming write started at block ', StartBlock);
  AssertTrue(StartBlock > 0, 'StartBlock should be positive');
  AssertTrue(State.Open, 'State should be open after Begin');

  AssertTrue(DBFMemoWriteChunk(State, Chunk1[1], Length(Chunk1)), 'DBFMemoWriteChunk should succeed');
  AssertTrue(DBFMemoWriteChunk(State, Chunk2[1], Length(Chunk2)), 'DBFMemoWriteChunk should succeed');
  AssertTrue(DBFMemoWriteChunk(State, Chunk3[1], Length(Chunk3)), 'DBFMemoWriteChunk should succeed');
  AssertTrue(DBFMemoWriteEnd(State), 'DBFMemoWriteEnd should succeed');

  AssertFalse(State.Open, 'State should be closed after End');

  { Verify }
  Ok := DBFMemoGetInfoM(MemoHandle, StartBlock, MemoType, MemoLen);
  AssertTrue(Ok, 'GetInfo should succeed after streaming write');
  AssertEqualsInt(36, MemoLen, 'Memo length should be 36');

  Ok := DBFMemoReadSmallM(MemoHandle, StartBlock, MemoType, ReadText);
  AssertTrue(Ok, 'ReadSmall should succeed');
  AssertEqualsStr('First part. Second part. Third part.', ReadText,
    'Streamed memo should contain all parts');

  MemoryReport('After streaming write');
  EndTest;
end;

{ Test 7: Write at specific block with Begin/EndAtBlock }
procedure TestWriteAtBlock;
var
  State: TMemoWriteState;
  StartBlock: LongInt;
  MemoType, MemoLen: LongInt;
  ReadText: string;
  Content: string;
  Ok: Boolean;
begin
  BeginTest('Write At Specific Block (BeginAtBlock/EndAtBlock)');

  { First write to allocate a block }
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'placeholder', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('Initial block allocated: ', StartBlock);

  { Now overwrite at that specific block }
  Content := 'Overwritten content!';
  AssertTrue(DBFMemoWriteBeginAtBlockM(MemoHandle, 1, Length(Content), 
    StartBlock, State), 'DBFMemoWriteBeginAtBlock should succeed');
  AssertTrue(State.Open, 'State should be open after BeginAtBlock');

  AssertTrue(DBFMemoWriteChunk(State, Content[1], Length(Content)), 'DBFMemoWriteChunk should succeed');
  AssertTrue(DBFMemoWriteEndAtBlock(State), 'DBFMemoWriteEndAtBlock should succeed');

  AssertFalse(State.Open, 'State should be closed after EndAtBlock');

  { Verify overwrite }
  Ok := DBFMemoGetInfoM(MemoHandle, StartBlock, MemoType, MemoLen);
  AssertTrue(Ok, 'GetInfo should succeed after overwrite');
  AssertEqualsInt(Length(Content), MemoLen, 'Length should match overwritten content');

  Ok := DBFMemoReadSmallM(MemoHandle, StartBlock, MemoType, ReadText);
  AssertTrue(Ok, 'ReadSmall should succeed after overwrite');
  AssertEqualsStr('Overwritten content!', ReadText,
    'Content should match overwritten text');

  EndTest;
end;

{ Test 9: WriteMemoFromBuffer }
procedure TestWriteMemoFromBuffer;
var
  Buf: array[0..255] of Byte;
  Content: string;
  I: Integer;
  StartBlock: LongInt;
  MemoType: LongInt;
  ReadText: string;
  Ok: Boolean;
begin
  BeginTest('WriteMemoFromBuffer');

  MemoryReport('Before WriteMemoFromBuffer');

  { Build a raw byte buffer with known content }
  Content := 'Hello from buffer';
  for I := 1 to Length(Content) do
    Buf[I - 1] := Ord(Content[I]);

  { Write memo directly from buffer at offset 0 }
  AssertTrue(WriteMemoFromBufferM(MemoHandle, 1, @Buf,
    0, Length(Content), StartBlock), 'WriteMemoFromBuffer should succeed');
  WriteLn('WriteMemoFromBuffer block=', StartBlock);
  AssertTrue(StartBlock > 0, 'StartBlock should be positive');

  { Verify }
  Ok := DBFMemoReadSmallM(MemoHandle, StartBlock, MemoType, ReadText);
  AssertTrue(Ok, 'ReadSmall should succeed');
  AssertEqualsStr('Hello from buffer', ReadText,
    'Content should match buffer text');

  { Test with non-zero content start offset }
  Content := 'PREFIX:Actual content';
  for I := 1 to Length(Content) do
    Buf[I - 1] := Ord(Content[I]);
  { Content starts after 'PREFIX:' = 7 bytes, length = 14 }
  AssertTrue(WriteMemoFromBufferM(MemoHandle, 1, @Buf,
    7, 14, StartBlock), 'WriteMemoFromBuffer should succeed');
  WriteLn('WriteMemoFromBuffer offset block=', StartBlock);

  Ok := DBFMemoReadSmallM(MemoHandle, StartBlock, MemoType, ReadText);
  AssertTrue(Ok, 'ReadSmall with offset should succeed');
  AssertEqualsStr('Actual content', ReadText,
    'Content from offset should match');

  MemoryReport('After WriteMemoFromBuffer');
  EndTest;
end;

{ Test 10: WriteMemoFromBufferAtBlock }
procedure TestWriteMemoFromBufferAtBlock;
var
  Buf: array[0..255] of Byte;
  Content: string;
  I: Integer;
  StartBlock: LongInt;
  MemoType: LongInt;
  ReadText: string;
  Ok: Boolean;
begin
  BeginTest('WriteMemoFromBufferAtBlock');

  { First allocate a block }
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'temp placeholder', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('Placeholder at block ', StartBlock);

  { Build raw byte buffer for overwrite }
  Content := 'Overwrite via buffer';
  for I := 1 to Length(Content) do
    Buf[I - 1] := Ord(Content[I]);

  { Overwrite at specific block }
  AssertTrue(WriteMemoFromBufferAtBlockM(MemoHandle, 1, @Buf,
    0, Length(Content), StartBlock), 'WriteMemoFromBufferAtBlock should succeed');

  { Verify }
  Ok := DBFMemoReadSmallM(MemoHandle, StartBlock, MemoType, ReadText);
  AssertTrue(Ok, 'ReadSmall should succeed after overwrite');
  AssertEqualsStr('Overwrite via buffer', ReadText,
    'Content should match overwritten text');

  EndTest;
end;

{ Test 11: WriteMemoChunks (export to text file) }
procedure TestWriteMemoChunksExport;
var
  StartBlock: LongInt;
  MemoType, MemoLen: LongInt;
  OutF: Text;
  Ok: Boolean;
begin
  BeginTest('WriteMemoChunks Export');

  { Write a memo to export }
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'Export test content', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('Export memo at block ', StartBlock);

  Ok := DBFMemoGetInfoM(MemoHandle, StartBlock, MemoType, MemoLen);
  AssertTrue(Ok, 'GetInfo should succeed');

  { Export to text file }
  Assign(OutF, 'MEMOEXP.TXT');
  Rewrite(OutF);
  AssertTrue(WriteMemoChunksM(MemoHandle, StartBlock, MemoLen, MemoType, OutF),
    'WriteMemoChunks should succeed');
  Close(OutF);

  AssertTrue(FileExists('MEMOEXP.TXT'), 'Export file should exist');

  { Clean up }
  Ok := DeleteFile('MEMOEXP.TXT');
  AssertTrue(Ok, 'Export file cleanup should succeed');

  EndTest;
end;

{ Helper: get memo temp filename for cleanup }
function GetMemoTempFileName(MemoPtr: LongInt): string;
var
  TempStr: string;
begin
  Str(MemoPtr, TempStr);
  GetMemoTempFileName := 'MEMO_' + TempStr + '.TMP';
end;

{ Test 12: Memo chunk operations (CreateMemoPointer, Get/Write/Append) }
procedure TestMemoChunkOperations;
var
  MemoPtr: LongInt;
  ChunkCount: Integer;
  ChunkText: string;
  NewPtr: LongInt;
  Result: Boolean;
begin
  BeginTest('Memo Chunk Operations');

  MemoryReport('Before chunk operations');

  { Create a memo pointer with initial text }
  MemoPtr := CreateMemoPointer('Initial chunk text');
  WriteLn('Created memo pointer: ', MemoPtr);
  AssertTrue(MemoPtr <> 0, 'Memo pointer should be non-zero');

  { Get chunk count }
  ChunkCount := GetMemoChunkCount(MemoPtr);
  WriteLn('Chunk count: ', ChunkCount);
  AssertTrue(ChunkCount >= 1, 'Should have at least 1 chunk');

  { Read first chunk }
  ChunkText := GetMemoChunk(MemoPtr, 0);
  WriteLn('Chunk 0 text: ', ChunkText);
  AssertEqualsStr('Initial chunk text', ChunkText,
    'First chunk should contain initial text');

  { Overwrite first chunk }
  AssertTrue(WriteMemoChunk(MemoPtr, 0, 'Modified chunk'), 'WriteMemoChunk should succeed');
  ChunkText := GetMemoChunk(MemoPtr, 0);
  AssertEqualsStr('Modified chunk', ChunkText,
    'Chunk should be overwritten');

  { Append a chunk }
  AssertTrue(AppendMemoChunk(MemoPtr, 'Appended chunk'), 'AppendMemoChunk should succeed');
  ChunkCount := GetMemoChunkCount(MemoPtr);
  WriteLn('Chunk count after append: ', ChunkCount);
  AssertTrue(ChunkCount >= 2, 'Should have at least 2 chunks after append');

  { Read appended chunk }
  ChunkText := GetMemoChunk(MemoPtr, ChunkCount - 1);
  WriteLn('Appended chunk text: ', ChunkText);
  AssertEqualsStr('Appended chunk', ChunkText,
    'Appended chunk should be readable');

  { Update memo pointer }
  NewPtr := CreateMemoPointer('New memo content');
  WriteLn('New pointer: ', NewPtr);
  AssertTrue(UpdateMemoPointer(MemoPtr, NewPtr), 'UpdateMemoPointer should succeed');
  AssertEqualsInt(NewPtr, MemoPtr,
    'MemoPtr should be updated to new pointer');

  { Verify new content }
  ChunkText := GetMemoChunk(MemoPtr, 0);
  AssertEqualsStr('New memo content', ChunkText,
    'Updated pointer should have new content');

  MemoryReport('After chunk operations');

  { Clean up chunk temp files }
  Result := DeleteFile(GetMemoTempFileName(MemoPtr));

  EndTest;
end;

{ Test 13: Integration - DBF with memo fields end-to-end }
procedure TestDBFMemoIntegration;
var
  SmartValues: Pointer;
  RowBuffer: Pointer;
  Block1, Block2: LongInt;
  MemoType, MemoLen: LongInt;
  ReadText, FieldStr: string;
  Ok: Boolean;
begin
  BeginTest('DBF + Memo Integration');

  MemoryReport('Before integration test');

  { Create DBF with memo fields }
  TestDbf := nil;
  SmartValues := nil;
  RowBuffer := nil;

  InitMemoTestHeader(TestHeader);
  Ok := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(Ok, 'DBFFileCreate should succeed');
  Ok := DBFFileGetHeader(TestDbf, TestHeader);

  { Write memos to DBT file }
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'Notes for record one', Block1), 'DBFMemoWrite should succeed');
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'Details for record one', Block2), 'DBFMemoWrite should succeed');
  WriteLn('Memo blocks: notes=', Block1, ' details=', Block2);

  { Create record linking to memos via block numbers }
  SmartValues := AllocateSmartValueArray(TestHeader);

  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Record One'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, IntToStrLocal(Block1)), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, IntToStrLocal(Block2)), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 3), 'DBFFileAppendRow should succeed');

  MemoryReport('After appending record with memo refs');

  { Read back the record and verify memo block numbers }
  GetMem(RowBuffer, TestHeader.RecordSize);
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, RowBuffer, TestHeader.RecordSize), 'DBFFileReadRow should succeed');

  FieldStr := TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 1));
  AssertEqualsStr('Record One', FieldStr, 'Name field should match');

  FieldStr := TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 2));
  WriteLn('NOTES field value: [', FieldStr, ']');
  AssertEqualsStr(IntToStrLocal(Block1), FieldStr,
    'NOTES field should contain memo block number');

  { Now read the actual memo using the block number }
  Ok := DBFMemoReadSmallM(MemoHandle, Block1, MemoType, ReadText);
  AssertTrue(Ok, 'Should read memo via block number from DBF field');
  AssertEqualsStr('Notes for record one', ReadText,
    'Memo content should match via block ref');

  Ok := DBFMemoReadSmallM(MemoHandle, Block2, MemoType, ReadText);
  AssertTrue(Ok, 'Should read second memo');
  AssertEqualsStr('Details for record one', ReadText,
    'Second memo content should match');

  MemoryReport('After reading memos from DBF');

  { Clear memo fields and verify memo refs are removed }
  Ok := DBFFileClearMemoFields(TestDbf);
  AssertTrue(Ok, 'DBFFileClearMemoFields should succeed');
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, RowBuffer, TestHeader.RecordSize), 'DBFFileReadRow should succeed');
  FieldStr := TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 2));
  AssertEqualsStr('0', FieldStr, 'NOTES field should be cleared');
  FieldStr := TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 3));
  AssertEqualsStr('0', FieldStr, 'DETAILS field should be cleared');

  { Clean up }
  if RowBuffer <> nil then
    FreeMem(RowBuffer, TestHeader.RecordSize);
  if SmartValues <> nil then
    Ok := FreeSmartValueArray(SmartValues); AssertTrue(Ok, 'FreeSmartValueArray should succeed');
  if TestDbf <> nil then
  begin
    Ok := DBFFileClose(TestDbf);
    AssertTrue(Ok, 'DBFFileClose should succeed');
    Ok := DBFFileDispose(TestDbf);
    AssertTrue(Ok, 'DBFFileDispose should succeed');
    TestDbf := nil;
  end;

  MemoryReport('After integration cleanup');
  EndTest;
end;

{ Test 14: Memo file compaction }
procedure TestMemoCompaction;
type
  PBlockArray = ^TBlockArray;
  TBlockArray = array[0..2] of LongInt;
var
  MemoName: string;
  MemoPath: string;
  MemoHandleC: PDBFMemo;
  Block1, Block2: LongInt;
  UsedBlocks: PLongIntArray;
  Mapping: PLongIntArray;
  MemoType, MemoLen: LongInt;
  ReadText: string;
  Ok: Boolean;
begin
  BeginTest('Memo Compaction');

  MemoName := 'TMEMOC';
  MemoPath := MemoName + '.DBT';
  Ok := DeleteFile(MemoPath);

    MemoHandleC := nil;
    Ok := DBFMemoCreate(MemoHandleC, MemoName);
    AssertTrue(Ok, 'DBFMemoCreate should succeed');
    Ok := DBFMemoClose(MemoHandleC);
    AssertTrue(Ok, 'DBFMemoClose should succeed');

    MemoHandleC := nil;
    Ok := DBFMemoOpen(MemoHandleC, MemoName);
    AssertTrue(Ok, 'DBFMemoOpen should succeed');

  AssertTrue(DBFMemoWriteM(MemoHandleC, 1, 'First memo', Block1), 'DBFMemoWrite should succeed');
  AssertTrue(DBFMemoWriteM(MemoHandleC, 1, 'Second memo', Block2), 'DBFMemoWrite should succeed');

  Ok := DBFMemoClose(MemoHandleC);
  AssertTrue(Ok, 'DBFMemoClose should succeed');

  GetMem(UsedBlocks, 3 * SizeOf(LongInt));
  PBlockArray(UsedBlocks)^[0] := Block1;
  PBlockArray(UsedBlocks)^[1] := Block2;
  PBlockArray(UsedBlocks)^[2] := 0;

  Mapping := CompactMemoFile(MemoName, UsedBlocks);
  AssertTrue(Mapping <> nil, 'CompactMemoFile should return mapping');

  Ok := DBFMemoOpen(MemoHandleC, MemoName);
  AssertTrue(Ok, 'DBFMemoOpen should succeed');

  Ok := DBFMemoReadSmallM(MemoHandleC, PBlockArray(Mapping)^[0], MemoType, ReadText);
  AssertTrue(Ok, 'Should read first memo after compaction');
  AssertEqualsStr('First memo', ReadText, 'First memo content should match');

  Ok := DBFMemoReadSmallM(MemoHandleC, PBlockArray(Mapping)^[1], MemoType, ReadText);
  AssertTrue(Ok, 'Should read second memo after compaction');
  AssertEqualsStr('Second memo', ReadText, 'Second memo content should match');

  if UsedBlocks <> nil then
    FreeMem(UsedBlocks, 3 * SizeOf(LongInt));
  if Mapping <> nil then
    FreeMem(Mapping, 2 * SizeOf(LongInt));
    if MemoHandleC <> nil then
    begin
      Ok := DBFMemoClose(MemoHandleC);
      AssertTrue(Ok, 'DBFMemoClose should succeed');
      Ok := DBFMemoDispose(MemoHandleC);
      AssertTrue(Ok, 'DBFMemoDispose should succeed');
      MemoHandleC := nil;
    end;
  Ok := DeleteFile(MemoPath);

  EndTest;
end;

{ Test 14: Multiple memos and large-ish content }
procedure TestMultipleMemos;
var
  Blocks: array[1..5] of LongInt;
  MemoType, MemoLen: LongInt;
  ReadText: string;
  Ok: Boolean;
  I: Integer;
  LargeText: string;
begin
  BeginTest('Multiple Memos');

  MemoryReport('Before multiple memos');

  { Write 5 memos }
  for I := 1 to 5 do
  begin
    AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'Memo number ' + IntToStrLocal(I), Blocks[I]), 'DBFMemoWrite should succeed');
    WriteLn('Memo ', I, ' at block ', Blocks[I]);
  end;

  { Read them all back }
  for I := 1 to 5 do
  begin
    Ok := DBFMemoReadSmallM(MemoHandle, Blocks[I], MemoType, ReadText);
    AssertTrue(Ok, 'ReadSmall should succeed for memo ' + IntToStrLocal(I));
    AssertEqualsStr('Memo number ' + IntToStrLocal(I), ReadText,
      'Memo ' + IntToStrLocal(I) + ' content should match');
  end;

  { Write a larger memo (200+ bytes) }
  LargeText := '';
  for I := 1 to 20 do
    LargeText := LargeText + 'Line ' + IntToStrLocal(I) + ' of text. ';

  AssertTrue(DBFMemoWriteM(MemoHandle, 1, LargeText, Blocks[1]), 'DBFMemoWrite should succeed');
  WriteLn('Large memo at block ', Blocks[1], ' len=', Length(LargeText));

  Ok := DBFMemoGetInfoM(MemoHandle, Blocks[1], MemoType, MemoLen);
  AssertTrue(Ok, 'GetInfo for large memo should succeed');
  AssertEqualsInt(Length(LargeText), MemoLen,
    'Large memo length should match');

  { Read it back }
  Ok := DBFMemoReadSmallM(MemoHandle, Blocks[1], MemoType, ReadText);
  AssertTrue(Ok, 'ReadSmall for large memo should succeed');
  { Note: ReadSmall truncates to 255 chars }
  AssertTrue(Length(ReadText) > 0, 'Large memo should have content');

  MemoryReport('After multiple memos');
  EndTest;
end;

{ Test 15: DBFMemoReadBuffer with exact and undersized buffers }
procedure TestReadBufferSizes;
var
  StartBlock: LongInt;
  SmallBuf: array[1..5] of Byte;
  ExactBuf: array[1..13] of Byte;
  MemoType: LongInt;
  ReadLen: Word;
  Ok: Boolean;
  ReadStr: string;
  I: Integer;
begin
  BeginTest('ReadBuffer Size Handling');

  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 'Exactly 13 ch', StartBlock), 'DBFMemoWrite should succeed');

  { Read with exact-size buffer }
  FillChar(ExactBuf, SizeOf(ExactBuf), 0);
  Ok := DBFMemoReadBufferM(MemoHandle, StartBlock, MemoType, ExactBuf, 13, ReadLen);
  AssertTrue(Ok, 'ReadBuffer with exact size should succeed');
  AssertEqualsInt(13, ReadLen, 'ReadLen should be 13 for exact buffer');

  { Read with undersized buffer }
  FillChar(SmallBuf, SizeOf(SmallBuf), 0);
  Ok := DBFMemoReadBufferM(MemoHandle, StartBlock, MemoType, SmallBuf, 5, ReadLen);
  AssertTrue(Ok, 'ReadBuffer with small buffer should succeed');
  AssertEqualsInt(5, ReadLen, 'ReadLen should be 5 for small buffer');

  ReadStr := '';
  for I := 1 to 5 do
    ReadStr := ReadStr + Chr(SmallBuf[I]);
  AssertEqualsStr('Exact', ReadStr, 'Small buffer should get first 5 chars');

  EndTest;
end;

{ Main test runner }
var
  Result: Boolean;
begin
  WriteLn('=== DBFMEMO Module Tests ===');
  WriteLn;

  MemoryReport('Initial Memory State');

  { Clean slate }
  Result := DeleteFile('TMEMO.DBF');
  Result := DeleteFile('TMEMO.DBT');
  Result := DeleteFile('MEMOEXP.TXT');

  MemoHandle := nil;
  Result := DBFMemoCreate(MemoHandle, MemoFileName);
  AssertTrue(Result, 'DBFMemoCreate should succeed');
  Result := DBFMemoClose(MemoHandle);
  AssertTrue(Result, 'DBFMemoClose should succeed');

  { Create the initial DBF+DBT for tests that need it }
  TestVersionByte;

  MemoryReport('After Version Byte Test');

  MemoHandle := nil;
  Result := DBFMemoOpen(MemoHandle, MemoFileName);
  AssertTrue(Result, 'DBFMemoOpen should succeed');

  TestMemoWriteReadSmall;

  MemoryReport('After Write/Read Small Test');

  TestMemoGetInfo;

  MemoryReport('After GetInfo Test');

  TestMemoWriteReadBuffer;

  MemoryReport('After Buffer Write/Read Test');

  TestMemoReadChunk;

  MemoryReport('After ReadChunk Test');

  TestStreamingWrite;

  MemoryReport('After Streaming Write Test');

  TestWriteAtBlock;

  MemoryReport('After WriteAtBlock Test');

  TestWriteMemoFromBuffer;

  MemoryReport('After WriteMemoFromBuffer Test');

  TestWriteMemoFromBufferAtBlock;

  MemoryReport('After WriteMemoFromBufferAtBlock Test');

  TestWriteMemoChunksExport;

  MemoryReport('After WriteMemoChunks Export Test');

  TestMemoChunkOperations;

  MemoryReport('After Chunk Operations Test');

  TestDBFMemoIntegration;

  MemoryReport('After Integration Test');

  TestMemoCompaction;

  MemoryReport('After Memo Compaction Test');

  TestMultipleMemos;

  MemoryReport('After Multiple Memos Test');

  TestReadBufferSizes;

  MemoryReport('Final Memory State');

  WriteLn;
  PrintSummary;

  { Clean up test files }
  WriteLn('Cleaning up test files...');
  if MemoHandle <> nil then
  begin
    Result := DBFMemoDispose(MemoHandle);
    AssertTrue(Result, 'DBFMemoDispose should succeed');
    MemoHandle := nil;
  end;
  if DeleteFile('TMEMO.DBF') then
    WriteLn('Deleted TMEMO.DBF');
  if DeleteFile('TMEMO.DBT') then
    WriteLn('Deleted TMEMO.DBT');
  if DeleteFile('MEMOEXP.TXT') then
    WriteLn('Deleted MEMOEXP.TXT');
  WriteLn('Cleanup complete');
end.
