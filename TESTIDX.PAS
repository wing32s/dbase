{ TESTIDX.PAS - simple NDX reader tests }

program TestIdx;

{$M 65520,0,350000}

uses DBF, DBFINDEX;

const
  NDXBlockSize = 512;
  NDXMaxKeys = 64;
  NDXMaxKeyLen = 80;

type
  TNDXBlock = array[1..NDXBlockSize] of Byte;
  TNDXHeader = record
    RootBlock: LongInt;
    EOFBlock: LongInt;
    KeyLen: Integer;
    KeysMax: Integer;
    GroupLen: Integer;
    Expr: string[80];
  end;
  TNDXKeyArray = array[0..NDXMaxKeys - 1] of string[NDXMaxKeyLen];
  TNDXIntArray = array[0..NDXMaxKeys] of LongInt;

function GetWordLE(var Buf: TNDXBlock; Pos: Integer): Word;
begin
  GetWordLE := Buf[Pos] or (Buf[Pos + 1] shl 8);
end;

function GetLongLE(var Buf: TNDXBlock; Pos: Integer): LongInt;
begin
  GetLongLE := Buf[Pos] or (Buf[Pos + 1] shl 8) or
               (Buf[Pos + 2] shl 16) or (Buf[Pos + 3] shl 24);
end;

function ValidLayout(KeyLen, KeysMax, GroupLen: Integer): Boolean;
begin
  if (KeyLen <= 0) or (KeyLen > 255) then
    ValidLayout := False
  else if (KeysMax <= 0) or (KeysMax > 255) then
    ValidLayout := False
  else if GroupLen < KeyLen + 8 then
    ValidLayout := False
  else if (4 + (KeysMax * GroupLen) + 4) > NDXBlockSize then
    ValidLayout := False
  else
    ValidLayout := True;
end;

function ReadNDXHeader(var F: File; var H: TNDXHeader): Boolean;
var
  Buf: TNDXBlock;
  V1KeyLen, V1KeysMax, V1GroupLen: Integer;
  V2KeyLen, V2KeysMax, V2GroupLen: Integer;
  V1Ok, V2Ok: Boolean;
  ExprOff, I: Integer;
  C: Char;
begin
  FillChar(H, SizeOf(H), 0);
  Seek(F, 0);
  BlockRead(F, Buf, SizeOf(Buf));

  V1KeyLen := GetWordLE(Buf, 7);
  V1KeysMax := GetWordLE(Buf, 9);
  V1GroupLen := GetWordLE(Buf, 11);
  V1Ok := ValidLayout(V1KeyLen, V1KeysMax, V1GroupLen);

  V2KeyLen := GetWordLE(Buf, 13);
  V2KeysMax := GetWordLE(Buf, 15);
  V2GroupLen := GetWordLE(Buf, 19);
  V2Ok := ValidLayout(V2KeyLen, V2KeysMax, V2GroupLen);

  if V2Ok and (not V1Ok) then
  begin
    H.RootBlock := GetLongLE(Buf, 1);
    H.EOFBlock := GetLongLE(Buf, 5);
    H.KeyLen := V2KeyLen;
    H.KeysMax := V2KeysMax;
    H.GroupLen := V2GroupLen;
    ExprOff := 25;
  end
  else if V1Ok then
  begin
    H.RootBlock := GetWordLE(Buf, 1);
    H.EOFBlock := GetWordLE(Buf, 5);
    H.KeyLen := V1KeyLen;
    H.KeysMax := V1KeysMax;
    H.GroupLen := V1GroupLen;
    ExprOff := 17;
  end
  else
  begin
    ReadNDXHeader := False;
    Exit;
  end;

  H.Expr := '';
  I := ExprOff;
  while (I <= NDXBlockSize) and (Length(H.Expr) < 80) do
  begin
    C := Chr(Buf[I]);
    if C = #0 then
      I := NDXBlockSize + 1
    else
    begin
      H.Expr := H.Expr + C;
      Inc(I);
    end;
  end;

  ReadNDXHeader := True;
end;

procedure ReadNDXNode(var F: File; Block: LongInt; var H: TNDXHeader;
  var NumKeys: Integer; var Keys: TNDXKeyArray; var Childs, Recnos: TNDXIntArray;
  var LastChild: LongInt);
var
  Buf: TNDXBlock;
  I, J: Integer;
  Offs: Integer;
  S: string[NDXMaxKeyLen];
begin
  Seek(F, Block * NDXBlockSize);
  BlockRead(F, Buf, SizeOf(Buf));
  NumKeys := GetWordLE(Buf, 1);
  if NumKeys > H.KeysMax then
    NumKeys := H.KeysMax;
  for I := 0 to NumKeys - 1 do
  begin
    Offs := 5 + (I * H.GroupLen);
    Childs[I] := GetLongLE(Buf, Offs);
    Recnos[I] := GetLongLE(Buf, Offs + 4);
    S := '';
    for J := 0 to H.KeyLen - 1 do
      S := S + Chr(Buf[Offs + 8 + J]);
    Keys[I] := S;
  end;
  Offs := 5 + (NumKeys * H.GroupLen);
  LastChild := GetLongLE(Buf, Offs);
end;

function IsLeafNode(NumKeys: Integer; var Childs: TNDXIntArray): Boolean;
var
  I: Integer;
  IsLeaf: Boolean;
begin
  IsLeaf := True;
  I := 0;
  while IsLeaf and (I < NumKeys) do
  begin
    if Childs[I] <> 0 then
      IsLeaf := False;
    Inc(I);
  end;
  IsLeafNode := IsLeaf;
end;

function CleanKey(S: string): string;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if S[I] = #0 then
      S[I] := ' ';
  CleanKey := TrimString(S);
end;

procedure DumpFirstEntries(var F: File; var H: TNDXHeader; Count: Integer);
var
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
  Block: LongInt;
  I: Integer;
begin
  Block := H.RootBlock;
  if Block <= 0 then
    Exit;
  ReadNDXNode(F, Block, H, NumKeys, Keys, Childs, Recnos, LastChild);
  while (Block > 0) and (not IsLeafNode(NumKeys, Childs)) do
  begin
    Block := Childs[0];
    ReadNDXNode(F, Block, H, NumKeys, Keys, Childs, Recnos, LastChild);
  end;
  I := 0;
  while (I < NumKeys) and (I < Count) do
  begin
    WriteLn(I + 1, ' ', Recnos[I], ' ', CleanKey(Keys[I]));
    Inc(I);
  end;
end;

procedure TestExactMatch(FileName, SearchKey: string);
var
  RowIds: TDBFRowIdArray;
  Count, I: Integer;
  Ok: Boolean;
begin
  Ok := FindCharacterExact(FileName, SearchKey, RowIds, 100, Count);
  WriteLn('Exact match search: ', SearchKey);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  Write('Exact recnos: [');
  I := 0;
  while (I < Count) and (I < 10) do
  begin
    if I > 0 then
      Write(', ');
    Write(RowIds[I]);
    Inc(I);
  end;
  WriteLn('] count= ', Count);
end;

procedure TestPrefixMatch(FileName, Prefix: string);
var
  RowIds: TDBFRowIdArray;
  Count, I: Integer;
  Ok: Boolean;
begin
  Ok := FindCharacterBegins(FileName, Prefix, RowIds, 200, Count);
  WriteLn('Prefix match search: ', Prefix);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  Write('Prefix recnos: [');
  I := 0;
  while (I < Count) and (I < 10) do
  begin
    if I > 0 then
      Write(', ');
    Write(RowIds[I]);
    Inc(I);
  end;
  WriteLn('] count= ', Count);
end;

procedure TestNumberExact(FileName: string; Value: LongInt);
var
  RowIds: TDBFRowIdArray;
  Count, I: Integer;
  Ok: Boolean;
begin
  Ok := FindNumberExact(FileName, Value, RowIds, 200, Count);
  WriteLn('Exact number search: ', Value);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  Write('Exact recnos: [');
  I := 0;
  while (I < Count) and (I < 10) do
  begin
    if I > 0 then
      Write(', ');
    Write(RowIds[I]);
    Inc(I);
  end;
  WriteLn('] count= ', Count);
end;

procedure TestNumberExactCount(FileName: string; Value: LongInt);
var
  Count: LongInt;
  Ok: Boolean;
begin
  Ok := CountNumberExact(FileName, Value, Count);
  WriteLn('Exact number count: ', Value);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  WriteLn('Count= ', Count);
end;

procedure TestNumberRange(FileName: string; MinValue, MaxValue: LongInt);
var
  RowIds: TDBFRowIdArray;
  Count, I: Integer;
  Ok: Boolean;
begin
  Ok := FindNumberRange(FileName, MinValue, MaxValue, RowIds, 200, Count);
  WriteLn('Exact range number search: ', MinValue, '-', MaxValue);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  Write('Range recnos: [');
  I := 0;
  while (I < Count) and (I < 10) do
  begin
    if I > 0 then
      Write(', ');
    Write(RowIds[I]);
    Inc(I);
  end;
  WriteLn('] count= ', Count);
end;

procedure TestNumberRangeCount(FileName: string; MinValue, MaxValue: LongInt);
var
  Count: LongInt;
  Ok: Boolean;
begin
  Ok := CountNumberRange(FileName, MinValue, MaxValue, Count);
  WriteLn('Exact range number count: ', MinValue, '-', MaxValue);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  WriteLn('Count= ', Count);
end;

procedure TestDateExact(FileName, DateStr: string);
var
  RowIds: TDBFRowIdArray;
  Count, I: Integer;
  Ok: Boolean;
begin
  Ok := FindDateExact(FileName, DateStr, RowIds, 20, Count);
  WriteLn('Exact date search: ', DateStr);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  Write('Exact recnos: [');
  I := 0;
  while (I < Count) and (I < 10) do
  begin
    if I > 0 then
      Write(', ');
    Write(RowIds[I]);
    Inc(I);
  end;
  WriteLn('] count= ', Count);
end;

procedure TestDateExactCount(FileName, DateStr: string);
var
  Count: LongInt;
  Ok: Boolean;
begin
  Ok := CountDateExact(FileName, DateStr, Count);
  WriteLn('Exact date count: ', DateStr);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  WriteLn('Count= ', Count);
end;

procedure TestDateRange(FileName, StartDateStr, EndDateStr: string);
var
  RowIds: TDBFRowIdArray;
  Count, I: Integer;
  Ok: Boolean;
begin
  Ok := FindDateRange(FileName, StartDateStr, EndDateStr, RowIds, 200, Count);
  WriteLn('Date range search: ', StartDateStr, ' to ', EndDateStr);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  WriteLn('Count= ', Count);
  Write('Range recnos: [');
  I := 0;
  while (I < Count) and (I < 20) do
  begin
    if I > 0 then
      Write(', ');
    Write(RowIds[I]);
    Inc(I);
  end;
  WriteLn(']');
end;

procedure TestDateRangeCount(FileName, StartDateStr, EndDateStr: string);
var
  Count: LongInt;
  Ok: Boolean;
begin
  Ok := CountDateRange(FileName, StartDateStr, EndDateStr, Count);
  WriteLn('Date range count: ', StartDateStr, ' to ', EndDateStr);
  if not Ok then
  begin
    WriteLn('Failed to read NDX.');
    Exit;
  end;
  WriteLn('Count= ', Count);
end;

var
  F: File;
  H: TNDXHeader;
begin
  Assign(F, 'DEVNAME3.NDX');
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then
  begin
    WriteLn('Unable to open DEVNAME3.NDX');
    Halt(1);
  end;

  if not ReadNDXHeader(F, H) then
  begin
    WriteLn('Invalid NDX header.');
    Close(F);
    Halt(1);
  end;

  WriteLn('Expression: ', H.Expr);
  WriteLn('Key length: ', H.KeyLen);
  DumpFirstEntries(F, H, 10);
  Close(F);

  TestExactMatch('DEVNAME3.NDX', 'Quicksilver Software, Inc.');
  TestPrefixMatch('DEVNAME3.NDX', 'Cosmi');
  TestPrefixMatch('TITLE3.NDX', 'King');
  TestPrefixMatch('DEVNAMEU.NDX', 'SIE');
  TestNumberExact('YEAR3.NDX', 1981);
  WriteLn('1981 counts');
  TestNumberExactCount('YEAR3.NDX', 1981);
  WriteLn('1982 counts');
  TestNumberExactCount('YEAR3.NDX', 1982);
  WriteLn('1983 counts');
  TestNumberExactCount('YEAR3.NDX', 1983);
  WriteLn('1984 counts');
  TestNumberExactCount('YEAR3.NDX', 1984);
  TestNumberRange('YEAR3.NDX', 1982, 1984);
  TestNumberRangeCount('YEAR3.NDX', 1982, 1984);
  TestDateExact('DATEADD3.NDX', '2022-08-25');
  TestDateExactCount('DATEADD3.NDX', '2022-08-25');
  TestDateRange('DATEADD3.NDX', '2022-08-01', '2022-08-30');
  TestDateRangeCount('DATEADD3.NDX', '2022-08-01', '2022-08-30');
end.
