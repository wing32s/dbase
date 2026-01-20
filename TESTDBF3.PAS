{ TESTDBF3.PAS - build a small dBase III table for NDX sampling }

program TestDBF3;

{$M 65520,0,350000}

uses DBF, Assert;

const
  TestFileName = 'DB3TEST';

var
  Header: TDBFHeader;
  DbfFile: PDBFFile;
  Values: TDBFValues;
  I: Integer;
  KeyVal: string;

const
  NDXMaxKeyLen = 80;
  NDXMaxKeys = 64;

type
  TNDXBlock = array[1..512] of Byte;
  TNDXEntry = record
    Key: string[80];
    Recno: LongInt;
  end;
  TNDXEntryArray = array[0..0] of TNDXEntry;
  PNDXEntryArray = ^TNDXEntryArray;
  TNDXKeyArray = array[0..NDXMaxKeys - 1] of TNDXEntry;
  TNDXChildArray = array[0..NDXMaxKeys] of LongInt;
  TRecnoArray = array[0..0] of LongInt;
  PRecnoArray = ^TRecnoArray;

procedure InitHeader(var H: TDBFHeader);
begin
  FillChar(H, SizeOf(H), 0);
  H.FieldCount := 1;
  H.Fields[1].Name := 'TEXT';
  H.Fields[1].FieldType := 'C';
  H.Fields[1].Length := 10;
  H.Fields[1].Decimals := 0;
end;

function GetWordLE(var Buf: TNDXBlock; Pos: Integer): Word;
begin
  GetWordLE := Buf[Pos] or (Buf[Pos + 1] shl 8);
end;

function GetLongLE(var Buf: TNDXBlock; Pos: Integer): LongInt;
begin
  GetLongLE := Buf[Pos] or (Buf[Pos + 1] shl 8) or
               (Buf[Pos + 2] shl 16) or (Buf[Pos + 3] shl 24);
end;

function FileExistsLocal(FileName: string): Boolean;
var
  F: File;
  Io: Integer;
begin
  Assign(F, FileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  Io := IOResult;
  if Io = 0 then
    Close(F);
  FileExistsLocal := Io = 0;
end;

function LongToStrLocal(Value: LongInt): string;
var
  S: string;
begin
  Str(Value, S);
  LongToStrLocal := S;
end;

function NormalizeKeyLocal(S: string; KeyLen: Integer; DoUpcase: Boolean): string;
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
  NormalizeKeyLocal := S;
end;

function NormalizeKeyValue(S: string): string;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if S[I] = #0 then
      S[I] := ' ';
  I := Length(S);
  while (I > 0) and (S[I] = ' ') do
    Dec(I);
  if I < Length(S) then
    S := Copy(S, 1, I);
  for I := 1 to Length(S) do
    S[I] := UpCase(S[I]);
  NormalizeKeyValue := S;
end;

procedure ReadNDXHeader(FileName: string; var RootBlock, EOFBlock: LongInt;
  var BlockCount: LongInt; var Ok: Boolean);
var
  F: File;
  Buf: TNDXBlock;
  SizeBytes: LongInt;
  Io: Integer;
begin
  Ok := False;
  RootBlock := 0;
  EOFBlock := 0;
  BlockCount := 0;
  Assign(F, FileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  Io := IOResult;
  if Io = 0 then
  begin
    SizeBytes := FileSize(F);
    BlockCount := SizeBytes div 512;
    if (SizeBytes mod 512) = 0 then
    begin
      Seek(F, 0);
      BlockRead(F, Buf, SizeOf(Buf));
      RootBlock := GetLongLE(Buf, 1);
      EOFBlock := GetLongLE(Buf, 5);
      Ok := BlockCount > 0;
    end;
    Close(F);
  end;
end;

procedure ReadNDXHeaderInfo(FileName: string; var RootBlock, EOFBlock: LongInt;
  var KeyLen, GroupLen, KeysMax: Integer; var Ok: Boolean);
var
  F: File;
  Buf: TNDXBlock;
  Io: Integer;
begin
  Ok := False;
  RootBlock := 0;
  EOFBlock := 0;
  KeyLen := 0;
  GroupLen := 0;
  KeysMax := 0;
  Assign(F, FileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  Io := IOResult;
  if Io <> 0 then
    Exit;
  BlockRead(F, Buf, SizeOf(Buf));
  Close(F);
  RootBlock := GetLongLE(Buf, 1);
  EOFBlock := GetLongLE(Buf, 5);
  KeyLen := GetWordLE(Buf, 13);
  KeysMax := GetWordLE(Buf, 15);
  GroupLen := GetWordLE(Buf, 19);
  if (KeyLen > 0) and (GroupLen > 0) then
    Ok := True;
end;

procedure ReadNDXNode(var F: File; Block: LongInt; KeyLen, GroupLen,
  KeysMax: Integer; var NumKeys: Integer; var Keys: TNDXKeyArray;
  var Childs: TNDXChildArray; var LastChild: LongInt);
var
  Buf: TNDXBlock;
  I, J: Integer;
  Offs: Integer;
  S: string;
begin
  Seek(F, Block * 512);
  BlockRead(F, Buf, SizeOf(Buf));
  NumKeys := GetWordLE(Buf, 1);
  if NumKeys > KeysMax then
    NumKeys := KeysMax;
  for I := 0 to NumKeys - 1 do
  begin
    Offs := 5 + (I * GroupLen);
    Childs[I] := GetLongLE(Buf, Offs);
    Keys[I].Recno := GetLongLE(Buf, Offs + 4);
    S := '';
    for J := 0 to KeyLen - 1 do
      S := S + Chr(Buf[Offs + 8 + J]);
    Keys[I].Key := S;
  end;
  Offs := 5 + (NumKeys * GroupLen);
  LastChild := GetLongLE(Buf, Offs);
end;

procedure CountLeafEntries(var F: File; Block: LongInt; KeyLen, GroupLen,
  KeysMax: Integer; var Count: LongInt);
var
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs: TNDXChildArray;
  LastChild: LongInt;
  I: Integer;
  IsLeaf: Boolean;
begin
  ReadNDXNode(F, Block, KeyLen, GroupLen, KeysMax, NumKeys, Keys, Childs, LastChild);
  IsLeaf := True;
  I := 0;
  while IsLeaf and (I < NumKeys) do
  begin
    if Childs[I] <> 0 then
      IsLeaf := False;
    Inc(I);
  end;
  if IsLeaf then
  begin
    Count := Count + NumKeys;
    Exit;
  end;
  for I := 0 to NumKeys - 1 do
    if Childs[I] > 0 then
      CountLeafEntries(F, Childs[I], KeyLen, GroupLen, KeysMax, Count);
  if LastChild > 0 then
    CountLeafEntries(F, LastChild, KeyLen, GroupLen, KeysMax, Count);
end;

procedure FillLeafEntries(var F: File; Block: LongInt; KeyLen, GroupLen,
  KeysMax: Integer; var Entries: TNDXEntryArray; var Index: LongInt);
var
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs: TNDXChildArray;
  LastChild: LongInt;
  I: Integer;
  IsLeaf: Boolean;
begin
  ReadNDXNode(F, Block, KeyLen, GroupLen, KeysMax, NumKeys, Keys, Childs, LastChild);
  IsLeaf := True;
  I := 0;
  while IsLeaf and (I < NumKeys) do
  begin
    if Childs[I] <> 0 then
      IsLeaf := False;
    Inc(I);
  end;
  if IsLeaf then
  begin
    for I := 0 to NumKeys - 1 do
    begin
      Entries[Index] := Keys[I];
      Inc(Index);
    end;
    Exit;
  end;
  for I := 0 to NumKeys - 1 do
    if Childs[I] > 0 then
      FillLeafEntries(F, Childs[I], KeyLen, GroupLen, KeysMax, Entries, Index);
  if LastChild > 0 then
    FillLeafEntries(F, LastChild, KeyLen, GroupLen, KeysMax, Entries, Index);
end;

procedure CompareNDXLeaves(FileA, FileB: string);
var
  RootA, EOFA: LongInt;
  RootB, EOFB: LongInt;
  KeyLenA, GroupLenA, KeysMaxA: Integer;
  KeyLenB, GroupLenB, KeysMaxB: Integer;
  OkA, OkB: Boolean;
  CountA, CountB: LongInt;
  EntriesA: PNDXEntryArray;
  EntriesB: PNDXEntryArray;
  IndexA, IndexB: LongInt;
  F: File;
  I: LongInt;
begin
  BeginTest('NDX leaf compare ' + FileA + ' vs ' + FileB);
  ReadNDXHeaderInfo(FileA, RootA, EOFA, KeyLenA, GroupLenA, KeysMaxA, OkA);
  ReadNDXHeaderInfo(FileB, RootB, EOFB, KeyLenB, GroupLenB, KeysMaxB, OkB);
  AssertTrue(OkA, 'read header A');
  AssertTrue(OkB, 'read header B');
  if OkA and OkB then
  begin
    AssertEqualsInt(KeyLenA, KeyLenB, 'key len');
    AssertEqualsInt(GroupLenA, GroupLenB, 'group len');
    if (KeyLenA > 0) and (KeyLenA <= NDXMaxKeyLen) and
       (GroupLenA > 0) and (KeysMaxA > 0) and (KeysMaxA <= NDXMaxKeys) then
    begin
      CountA := 0;
      Assign(F, FileA);
      Reset(F, 1);
      CountLeafEntries(F, RootA, KeyLenA, GroupLenA, KeysMaxA, CountA);
      Close(F);
      CountB := 0;
      Assign(F, FileB);
      Reset(F, 1);
      CountLeafEntries(F, RootB, KeyLenB, GroupLenB, KeysMaxB, CountB);
      Close(F);
      AssertEqualsInt(CountA, CountB, 'leaf count');
      if CountA = CountB then
      begin
        GetMem(EntriesA, SizeOf(TNDXEntry) * CountA);
        GetMem(EntriesB, SizeOf(TNDXEntry) * CountB);
        IndexA := 0;
        Assign(F, FileA);
        Reset(F, 1);
        FillLeafEntries(F, RootA, KeyLenA, GroupLenA, KeysMaxA, EntriesA^, IndexA);
        Close(F);
        IndexB := 0;
        Assign(F, FileB);
        Reset(F, 1);
        FillLeafEntries(F, RootB, KeyLenB, GroupLenB, KeysMaxB, EntriesB^, IndexB);
        Close(F);
        I := 0;
        while I < CountA do
        begin
          if (EntriesA^[I].Key <> EntriesB^[I].Key) or
             (EntriesA^[I].Recno <> EntriesB^[I].Recno) then
          begin
            AssertTrue(False, 'leaf entry mismatch at ' + LongToStrLocal(I + 1));
            I := CountA;
          end
          else
            Inc(I);
        end;
        FreeMem(EntriesA, SizeOf(TNDXEntry) * CountA);
        FreeMem(EntriesB, SizeOf(TNDXEntry) * CountB);
      end;
    end
    else
      AssertTrue(False, 'header limits');
  end;
  EndTest;
end;

procedure CollectRecnosForKey(FileName, SearchKey: string;
  StartsWith: Boolean; var Recnos: PRecnoArray; var RecnoCount: LongInt;
  var Ok: Boolean);
var
  RootA, EOFA: LongInt;
  KeyLenA, GroupLenA, KeysMaxA: Integer;
  CountA: LongInt;
  EntriesA: PNDXEntryArray;
  IndexA: LongInt;
  F: File;
  I: LongInt;
  MatchKey: string;
begin
  Ok := False;
  RecnoCount := 0;
  Recnos := nil;
  ReadNDXHeaderInfo(FileName, RootA, EOFA, KeyLenA, GroupLenA, KeysMaxA, Ok);
  if not Ok then
    Exit;
  if (KeyLenA <= 0) or (KeyLenA > NDXMaxKeyLen) then
    Exit;
  CountA := 0;
  Assign(F, FileName);
  Reset(F, 1);
  CountLeafEntries(F, RootA, KeyLenA, GroupLenA, KeysMaxA, CountA);
  Close(F);
  if CountA = 0 then
  begin
    Ok := True;
    Exit;
  end;
  GetMem(EntriesA, SizeOf(TNDXEntry) * CountA);
  IndexA := 0;
  Assign(F, FileName);
  Reset(F, 1);
  FillLeafEntries(F, RootA, KeyLenA, GroupLenA, KeysMaxA, EntriesA^, IndexA);
  Close(F);
  GetMem(Recnos, SizeOf(LongInt) * CountA);
  MatchKey := NormalizeKeyValue(SearchKey);
  for I := 0 to CountA - 1 do
    if StartsWith then
    begin
      if Copy(NormalizeKeyValue(EntriesA^[I].Key), 1, Length(MatchKey)) = MatchKey then
      begin
        Recnos^[RecnoCount] := EntriesA^[I].Recno;
        Inc(RecnoCount);
      end;
    end
    else if NormalizeKeyValue(EntriesA^[I].Key) = MatchKey then
    begin
      Recnos^[RecnoCount] := EntriesA^[I].Recno;
      Inc(RecnoCount);
    end;
  FreeMem(EntriesA, SizeOf(TNDXEntry) * CountA);
  Ok := True;
end;

procedure CompareNDXKeyMatches(FileA, FileB, SearchKey: string; StartsWith: Boolean);
var
  RecnosA: PRecnoArray;
  RecnosB: PRecnoArray;
  CountA, CountB: LongInt;
  OkA, OkB: Boolean;
  I: LongInt;
begin
  if StartsWith then
    BeginTest('NDX key compare prefix ' + SearchKey)
  else
    BeginTest('NDX key compare ' + SearchKey);
  CollectRecnosForKey(FileA, SearchKey, StartsWith, RecnosA, CountA, OkA);
  CollectRecnosForKey(FileB, SearchKey, StartsWith, RecnosB, CountB, OkB);
  AssertTrue(OkA, 'read A');
  AssertTrue(OkB, 'read B');
  if OkA and OkB then
  begin
    WriteLn('NDX key compare count A=', CountA, ' B=', CountB);
    AssertEqualsInt(CountA, CountB, 'match count');
    if CountA = CountB then
    begin
      I := 0;
      while (I < CountA) and (I < 5) do
      begin
        WriteLn('NDX key compare recno ', I + 1, ' A=', RecnosA^[I], ' B=', RecnosB^[I]);
        Inc(I);
      end;
      I := 0;
      while I < CountA do
      begin
        if RecnosA^[I] <> RecnosB^[I] then
        begin
          AssertTrue(False, 'recno mismatch at ' + LongToStrLocal(I + 1));
          I := CountA;
        end
        else
          Inc(I);
      end;
    end;
  end;
  if RecnosA <> nil then
    FreeMem(RecnosA, SizeOf(LongInt) * CountA);
  if RecnosB <> nil then
    FreeMem(RecnosB, SizeOf(LongInt) * CountB);
  EndTest;
end;

procedure CountDBFMatches(FileName, FieldName, SearchKey: string; StartsWith: Boolean);
var
  DbfFile: PDBFFile;
  Header: TDBFHeader;
  Ok: Boolean;
  FieldIdx: Integer;
  RowCount: LongInt;
  RowIndex: LongInt;
  RowBuf: TDBFRow;
  Value: string;
  MatchKey: string;
  Count: LongInt;
begin
  DbfFile := nil;
  DBFFileOpen(DbfFile, FileName);
  Ok := DBFFileGetHeader(DbfFile, Header);
  if not Ok then
  begin
    if DbfFile <> nil then
      DBFFileDispose(DbfFile);
    Exit;
  end;
  FieldIdx := 0;
  for RowIndex := 1 to Header.FieldCount do
    if NormalizeKeyValue(Header.Fields[RowIndex].Name) = NormalizeKeyValue(FieldName) then
      FieldIdx := RowIndex;
  if FieldIdx = 0 then
  begin
    DBFFileClose(DbfFile);
    DBFFileDispose(DbfFile);
    Exit;
  end;
  MatchKey := NormalizeKeyValue(SearchKey);
  Count := 0;
  RowCount := DBFFileGetActualRowCount(DbfFile);
  DBFFileSeekToFirstRow(DbfFile);
  for RowIndex := 0 to RowCount - 1 do
  begin
    DBFFileReadRow(DbfFile, RowBuf);
    if RowBuf[0] <> Ord('*') then
    begin
      Value := NormalizeKeyValue(DBFFileGetFieldStr(RowBuf, DbfFile, FieldIdx));
      if StartsWith then
      begin
        if Copy(Value, 1, Length(MatchKey)) = MatchKey then
          Inc(Count);
      end
      else if Value = MatchKey then
        Inc(Count);
    end;
  end;
  WriteLn('DBF match count ', FieldName, ' ', SearchKey, ' = ', Count);
  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
end;

procedure VerifyNDXAgainstDBF(NdxFile, DbfFileName, FieldName: string; MaxMismatches: Integer);
var
  RootBlock, EOFBlock: LongInt;
  KeyLen, GroupLen, KeysMax: Integer;
  Ok: Boolean;
  Count: LongInt;
  Entries: PNDXEntryArray;
  Index: LongInt;
  F: File;
  DbfFile: PDBFFile;
  Header: TDBFHeader;
  FieldIdx: Integer;
  RowBuf: TDBFRow;
  RowIndex: LongInt;
  KeyA, KeyB: string;
  MismatchCount: Integer;
  RowCount: LongInt;
begin
  ReadNDXHeaderInfo(NdxFile, RootBlock, EOFBlock, KeyLen, GroupLen, KeysMax, Ok);
  if not Ok then
  begin
    WriteLn('NDX verify failed header: ', NdxFile);
    Exit;
  end;
  WriteLn('NDX header ', NdxFile, ' root=', RootBlock, ' eof=', EOFBlock,
    ' keylen=', KeyLen, ' grouplen=', GroupLen, ' keysmax=', KeysMax);
  if GroupLen < (KeyLen + 8) then
  begin
    WriteLn('NDX verify invalid group len: ', GroupLen);
    Exit;
  end;
  Count := 0;
  Assign(F, NdxFile);
  Reset(F, 1);
  CountLeafEntries(F, RootBlock, KeyLen, GroupLen, KeysMax, Count);
  Close(F);
  if Count = 0 then
  begin
    WriteLn('NDX verify no entries: ', NdxFile);
    Exit;
  end;
  GetMem(Entries, SizeOf(TNDXEntry) * Count);
  Index := 0;
  Assign(F, NdxFile);
  Reset(F, 1);
  FillLeafEntries(F, RootBlock, KeyLen, GroupLen, KeysMax, Entries^, Index);
  Close(F);

  DbfFile := nil;
  DBFFileOpen(DbfFile, DbfFileName);
  if not DBFFileGetHeader(DbfFile, Header) then
  begin
    WriteLn('NDX verify failed DBF header: ', DbfFileName);
    DBFFileDispose(DbfFile);
    FreeMem(Entries, SizeOf(TNDXEntry) * Count);
    Exit;
  end;
  RowCount := DBFFileGetActualRowCount(DbfFile);
  WriteLn('DBF row count ', DbfFileName, ' = ', RowCount);
  FieldIdx := 0;
  for RowIndex := 1 to Header.FieldCount do
    if NormalizeKeyValue(Header.Fields[RowIndex].Name) = NormalizeKeyValue(FieldName) then
      FieldIdx := RowIndex;
  if FieldIdx = 0 then
  begin
    WriteLn('NDX verify field not found: ', FieldName);
    DBFFileClose(DbfFile);
    DBFFileDispose(DbfFile);
    FreeMem(Entries, SizeOf(TNDXEntry) * Count);
    Exit;
  end;

  MismatchCount := 0;
  Index := 0;
  while (Index < Count) and (MismatchCount < MaxMismatches) do
  begin
    RowIndex := Entries^[Index].Recno - 1;
    if (RowIndex >= 0) and (RowIndex < RowCount) then
    begin
      DBFFileSeekToRow(DbfFile, RowIndex);
      DBFFileReadRow(DbfFile, RowBuf);
      KeyA := NormalizeKeyValue(Entries^[Index].Key);
      KeyB := NormalizeKeyValue(DBFFileGetFieldStr(RowBuf, DbfFile, FieldIdx));
      if KeyA <> KeyB then
      begin
        Inc(MismatchCount);
        WriteLn('NDX verify mismatch recno ', Entries^[Index].Recno,
          ' key=', KeyA, ' dbf=', KeyB);
      end;
    end;
    if (RowIndex < 0) or (RowIndex >= RowCount) then
    begin
      Inc(MismatchCount);
      WriteLn('NDX verify invalid recno ', Entries^[Index].Recno);
    end;
    Inc(Index);
  end;

  if MismatchCount = 0 then
    WriteLn('NDX verify ok: ', NdxFile);

  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);
  FreeMem(Entries, SizeOf(TNDXEntry) * Count);
end;

procedure TestNDXFile(FileName: string);
var
  RootBlock, EOFBlock: LongInt;
  BlockCount: LongInt;
  Ok: Boolean;
begin
  BeginTest('NDX header ' + FileName);
  ReadNDXHeader(FileName, RootBlock, EOFBlock, BlockCount, Ok);
  AssertTrue(Ok, 'header read');
  if Ok then
  begin
    AssertEqualsInt(BlockCount, EOFBlock, 'eof matches blocks');
    AssertTrue((RootBlock > 0) and (RootBlock < EOFBlock), 'root within range');
  end;
  EndTest;
end;

begin
  InitHeader(Header);
  DbfFile := nil;
  DBFFileCreateDBase3(DbfFile, TestFileName, Header);

  FillChar(Values, SizeOf(Values), 0);
  for I := 1 to 100 do
  begin
    case I mod 5 of
      0: KeyVal := 'ALPHA';
      1: KeyVal := 'BRAVO';
      2: KeyVal := 'CHARLIE';
      3: KeyVal := 'DELTA';
    else
      KeyVal := 'ECHO';
    end;
    Values[1] := KeyVal;
    DBFFileAppendRow(DbfFile, Values);
  end;
  
  DBFFileBuildNDX(DbfFile, 'TEXT');

  DBFFileClose(DbfFile);
  DBFFileDispose(DbfFile);

  ResetAsserts;
  if FileExistsLocal('TITLE3.NDX') then
    TestNDXFile('TITLE3.NDX');
  if FileExistsLocal('DEVNAME3.NDX') then
    TestNDXFile('DEVNAME3.NDX');
  if FileExistsLocal('PUBNAME3.NDX') then
    TestNDXFile('PUBNAME3.NDX');
  if FileExistsLocal('TEXT3.NDX') then
    TestNDXFile('TEXT3.NDX');
  if FileExistsLocal('TEXT.NDX') then
    TestNDXFile('TEXT.NDX');
  if FileExistsLocal('TEXT.NDX') and FileExistsLocal('TEXT3.NDX') then
    CompareNDXLeaves('TEXT.NDX', 'TEXT3.NDX');

  if FileExistsLocal('GAMES3.DBF') then
  begin
    CountDBFMatches('GAMES3.DBF', 'DEVNAME', 'Quicksilver Software, Inc.', False);
    CountDBFMatches('GAMES3.DBF', 'DEVNAME', 'Cosmi', True);

  end;
  if FileExistsLocal('GAMES3.DBF') then
  begin
    DbfFile := nil;
    DBFFileOpen(DbfFile, 'GAMES3.DBF');
    WriteLn('Building DEVNAME index...');
    DBFFileBuildNDX(DbfFile, 'DEVNAME');
    { DBFFileBuildNDX(DbfFile, 'TITLE'); }
    DBFFileClose(DbfFile);
    DBFFileDispose(DbfFile);
  end;

  if FileExistsLocal('DEVNAME.NDX') and FileExistsLocal('DEVNAME3.NDX') then
  begin
    CompareNDXKeyMatches('DEVNAME.NDX', 'DEVNAME3.NDX',
      'Quicksilver Software, Inc.', False);
    CompareNDXKeyMatches('DEVNAME.NDX', 'DEVNAME3.NDX',
      'Cosmi', True);
  end;
  
    if FileExistsLocal('DEVNAME.NDX') then
      VerifyNDXAgainstDBF('DEVNAME.NDX', 'GAMES3.DBF', 'DEVNAME', 5);
    if FileExistsLocal('DEVNAME3.NDX') then
      VerifyNDXAgainstDBF('DEVNAME3.NDX', 'GAMES3.DBF', 'DEVNAME', 5);

  PrintSummary;
end.
