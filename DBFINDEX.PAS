unit DBFINDEX;

{$N+}

interface

uses DBFUTIL;

type
  PRowIdArray = ^TRowIdArray;
  TRowIdArray = array[0..0] of LongInt;  { Open array for pointer math }

function FindCharacterExact(NdxFileName, Key: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
function FindCharacterBegins(NdxFileName, Prefix: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
function FindNumberExact(NdxFileName: string; Value: LongInt;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
function FindNumberRange(NdxFileName: string; MinValue, MaxValue: LongInt;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
function CountNumberExact(NdxFileName: string; Value: LongInt;
  var Count: LongInt): Boolean;
function CountNumberRange(NdxFileName: string; MinValue, MaxValue: LongInt;
  var Count: LongInt): Boolean;
function FindDateExact(NdxFileName, DateStr: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
function FindDateRange(NdxFileName, StartDateStr, EndDateStr: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
function CountDateExact(NdxFileName, DateStr: string; var Count: LongInt): Boolean;
function CountDateRange(NdxFileName, StartDateStr, EndDateStr: string;
  var Count: LongInt): Boolean;

implementation

const
  NDXBlockSize = 512;
  NDXMaxKeys = 64;
  NDXMaxKeyLen = 80;
  NDXMaxDepth = 32;
  DebugNDX = False;

type
  TNDXBlockStack = array[0..NDXMaxDepth - 1] of LongInt;
  TNDXIdxStack = array[0..NDXMaxDepth - 1] of Integer;
  TNDXKeyArray = array[0..NDXMaxKeys - 1] of string[NDXMaxKeyLen];
  TNDXIntArray = array[0..NDXMaxKeys] of LongInt;
  TKey8 = array[1..8] of Byte;

  TNDXBlock = array[1..NDXBlockSize] of Byte;
  TNDXHeader = record
    RootBlock: LongInt;
    EOFBlock: LongInt;
    KeyLen: Integer;
    KeysMax: Integer;
    GroupLen: Integer;
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
  end
  else if V1Ok then
  begin
    H.RootBlock := GetWordLE(Buf, 1);
    H.EOFBlock := GetWordLE(Buf, 5);
    H.KeyLen := V1KeyLen;
    H.KeysMax := V1KeysMax;
    H.GroupLen := V1GroupLen;
  end;

  ReadNDXHeader := (H.KeyLen > 0) and (H.KeysMax > 0) and (H.GroupLen > 0);
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

procedure NormalizeKey(var S: string; KeyLen: Integer);
var
  I: Integer;
begin
  if Length(S) > KeyLen then
    S := Copy(S, 1, KeyLen);
  for I := 1 to Length(S) do
    if S[I] = #0 then
      S[I] := ' ';
  while Length(S) < KeyLen do
    S := S + ' ';
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

function NormalizePrefix(S: string; KeyLen: Integer): string;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    if S[I] = #0 then
      S[I] := ' ';
  if Length(S) > KeyLen then
    S := Copy(S, 1, KeyLen);
  NormalizePrefix := S;
end;

procedure KeyStrToKey8(KeyStr: string; var K: TKey8);
var
  I: Integer;
begin
  FillChar(K, SizeOf(K), 0);
  for I := 1 to 8 do
    if I <= Length(KeyStr) then
      K[I] := Ord(KeyStr[I]);
end;

procedure MakeKey8FromLongInt(Value: LongInt; var K: TKey8);
var
  D: Double;
begin
  D := Value;
  Move(D, K, SizeOf(K));
end;

function CompareKey8(var A, B: TKey8): Integer;
var
  I: Integer;
begin
  for I := 8 downto 1 do
  begin
    if A[I] < B[I] then
    begin
      CompareKey8 := -1;
      Exit;
    end
    else if A[I] > B[I] then
    begin
      CompareKey8 := 1;
      Exit;
    end;
  end;
  CompareKey8 := 0;
end;

function StartsWithKey(KeyStr, Prefix: string): Boolean;
var
  I: Integer;
begin
  if Length(Prefix) = 0 then
  begin
    StartsWithKey := False;
    Exit;
  end;
  if Length(KeyStr) < Length(Prefix) then
  begin
    StartsWithKey := False;
    Exit;
  end;
  for I := 1 to Length(Prefix) do
    if KeyStr[I] <> Prefix[I] then
    begin
      StartsWithKey := False;
      Exit;
    end;
  StartsWithKey := True;
end;

function CompareKeys(A, B: string; KeyLen: Integer): Integer;
var
  I: Integer;
begin
  NormalizeKey(A, KeyLen);
  NormalizeKey(B, KeyLen);
  for I := 1 to KeyLen do
  begin
    if A[I] < B[I] then
    begin
      CompareKeys := -1;
      Exit;
    end
    else if A[I] > B[I] then
    begin
      CompareKeys := 1;
      Exit;
    end;
  end;
  CompareKeys := 0;
end;

procedure DescendLeftmost(var F: File; var H: TNDXHeader; StartBlock: LongInt;
  var Stack: TNDXBlockStack; var StackIdx: TNDXIdxStack; var Depth: Integer);
var
  Block: LongInt;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
begin
  Block := StartBlock;
  while (Block > 0) and (Depth < NDXMaxDepth) do
  begin
    ReadNDXNode(F, Block, H, NumKeys, Keys, Childs, Recnos, LastChild);
    Stack[Depth] := Block;
    StackIdx[Depth] := 0;
    Inc(Depth);
    if IsLeafNode(NumKeys, Childs) then
      Exit;
    if NumKeys > 0 then
      Block := Childs[0]
    else
      Block := LastChild;
  end;
end;

procedure DescendToFirstGE(var F: File; var H: TNDXHeader; KeyNorm: string;
  var Stack: TNDXBlockStack; var StackIdx: TNDXIdxStack; var Depth: Integer);
var
  Block: LongInt;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
  I: Integer;
  NextBlock: LongInt;
begin
  Depth := 0;
  Block := H.RootBlock;
  while (Block > 0) and (Depth < NDXMaxDepth) do
  begin
    ReadNDXNode(F, Block, H, NumKeys, Keys, Childs, Recnos, LastChild);
    if IsLeafNode(NumKeys, Childs) then
    begin
      Stack[Depth] := Block;
      I := 0;
      while (I < NumKeys) and (CompareKeys(Keys[I], KeyNorm, H.KeyLen) < 0) do
        Inc(I);
      StackIdx[Depth] := I;
      Inc(Depth);
      Exit;
    end;
    NextBlock := LastChild;
    I := 0;
    while I < NumKeys do
    begin
      if CompareKeys(KeyNorm, Keys[I], H.KeyLen) <= 0 then
      begin
        NextBlock := Childs[I];
        StackIdx[Depth] := I;
        I := NumKeys;
      end
      else
        Inc(I);
    end;
    Stack[Depth] := Block;
    Inc(Depth);
    Block := NextBlock;
  end;
end;

procedure AdvanceToSuccessor(var F: File; var H: TNDXHeader;
  var Stack: TNDXBlockStack; var StackIdx: TNDXIdxStack; var Depth: Integer);
var
  ChildPos: Integer;
  NextChildPos: Integer;
  NextBlock: LongInt;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
begin
  while Depth > 0 do
  begin
    ChildPos := StackIdx[Depth - 1];
    ReadNDXNode(F, Stack[Depth - 1], H, NumKeys, Keys, Childs, Recnos, LastChild);
    if ChildPos < NumKeys then
    begin
      NextChildPos := ChildPos + 1;
      if NextChildPos < NumKeys then
        NextBlock := Childs[NextChildPos]
      else
        NextBlock := LastChild;
      StackIdx[Depth - 1] := NextChildPos;
      DescendLeftmost(F, H, NextBlock, Stack, StackIdx, Depth);
      Exit;
    end;
    Dec(Depth);
  end;
end;

function NextEntry(var F: File; var H: TNDXHeader;
  var Stack: TNDXBlockStack; var StackIdx: TNDXIdxStack; var Depth: Integer;
  var KeyOut: string; var RecnoOut: LongInt): Boolean;
var
  Idx: Integer;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
begin
  NextEntry := False;
  while Depth > 0 do
  begin
    Idx := StackIdx[Depth - 1];
    ReadNDXNode(F, Stack[Depth - 1], H, NumKeys, Keys, Childs, Recnos, LastChild);
    if IsLeafNode(NumKeys, Childs) then
    begin
      if DebugNDX and (Idx = 0) and (NumKeys > 0) then
        WriteLn('NDX DBG: leaf ', Stack[Depth - 1], ' firstkey=',
          CleanKey(Keys[0]));
      if Idx < NumKeys then
      begin
        KeyOut := Keys[Idx];
        RecnoOut := Recnos[Idx];
        StackIdx[Depth - 1] := Idx + 1;
        NextEntry := True;
        Exit;
      end
      else
      begin
        if DebugNDX and (NumKeys > 0) then
          WriteLn('NDX DBG: leaf ', Stack[Depth - 1], ' exhausted lastkey=',
            CleanKey(Keys[NumKeys - 1]));
        Dec(Depth);
        AdvanceToSuccessor(F, H, Stack, StackIdx, Depth);
        if DebugNDX and (Depth > 0) then
        begin
          ReadNDXNode(F, Stack[Depth - 1], H, NumKeys, Keys, Childs, Recnos, LastChild);
          if IsLeafNode(NumKeys, Childs) and (NumKeys > 0) then
            WriteLn('NDX DBG: next leaf ', Stack[Depth - 1], ' firstkey=',
              CleanKey(Keys[0]));
        end;
      end;
    end
    else
    begin
      Dec(Depth);
      AdvanceToSuccessor(F, H, Stack, StackIdx, Depth);
    end;
  end;
end;

function FindCharacterExact(NdxFileName, Key: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
var
  F: File;
  H: TNDXHeader;
  KeyNorm: string;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
  Stack: TNDXBlockStack;
  StackIdx: TNDXIdxStack;
  Depth: Integer;
  KeyOut: string;
  RecnoOut: LongInt;
  Cmp: Integer;
begin
  Count := 0;
  if RowIds = nil then
  begin
    FindCharacterExact := False;
    Exit;
  end;
  if MaxCount <= 0 then
  begin
    FindCharacterExact := False;
    Exit;
  end;

  Assign(F, NdxFileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then
  begin
    FindCharacterExact := False;
    Exit;
  end;

  if not ReadNDXHeader(F, H) then
  begin
    Close(F);
    FindCharacterExact := False;
    Exit;
  end;

  KeyNorm := Key;
  NormalizeKey(KeyNorm, H.KeyLen);

  DescendToFirstGE(F, H, KeyNorm, Stack, StackIdx, Depth);
  while (Count < MaxCount) and NextEntry(F, H, Stack, StackIdx, Depth, KeyOut, RecnoOut) do
  begin
    Cmp := CompareKeys(KeyOut, KeyNorm, H.KeyLen);
    if Cmp <> 0 then
      Depth := 0
    else
    begin
      if RecnoOut <> 0 then
      begin
        RowIds^[Count] := RecnoOut;
        Inc(Count);
      end;
    end;
  end;

  Close(F);
  FindCharacterExact := True;
end;

procedure DescendToFirstGE_Number(var F: File; var H: TNDXHeader; Target: TKey8;
  var Stack: TNDXBlockStack; var StackIdx: TNDXIdxStack; var Depth: Integer);
var
  Block: LongInt;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
  I: Integer;
  NextBlock: LongInt;
  KeyVal: TKey8;
begin
  Depth := 0;
  Block := H.RootBlock;
  while (Block > 0) and (Depth < NDXMaxDepth) do
  begin
    ReadNDXNode(F, Block, H, NumKeys, Keys, Childs, Recnos, LastChild);
    if IsLeafNode(NumKeys, Childs) then
    begin
      Stack[Depth] := Block;
      I := 0;
      StackIdx[Depth] := NumKeys;
      while I < NumKeys do
      begin
        KeyStrToKey8(Keys[I], KeyVal);
        if CompareKey8(KeyVal, Target) >= 0 then
        begin
          StackIdx[Depth] := I;
          I := NumKeys;
        end
        else
          Inc(I);
      end;
      Inc(Depth);
      Exit;
    end;
    NextBlock := LastChild;
    I := 0;
    while I < NumKeys do
    begin
      KeyStrToKey8(Keys[I], KeyVal);
      if CompareKey8(Target, KeyVal) <= 0 then
      begin
        NextBlock := Childs[I];
        StackIdx[Depth] := I;
        I := NumKeys;
      end
      else
        Inc(I);
    end;
    Stack[Depth] := Block;
    Inc(Depth);
    Block := NextBlock;
  end;
end;

function FindCharacterBegins(NdxFileName, Prefix: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
var
  F: File;
  H: TNDXHeader;
  PrefixNorm: string;
  KeyNorm: string;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
  Stack: TNDXBlockStack;
  StackIdx: TNDXIdxStack;
  Depth: Integer;
  KeyOut: string;
  RecnoOut: LongInt;
begin
  Count := 0;
  if RowIds = nil then
  begin
    FindCharacterBegins := False;
    Exit;
  end;
  if MaxCount <= 0 then
  begin
    FindCharacterBegins := False;
    Exit;
  end;

  Assign(F, NdxFileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then
  begin
    FindCharacterBegins := False;
    Exit;
  end;

  if not ReadNDXHeader(F, H) then
  begin
    Close(F);
    FindCharacterBegins := False;
    Exit;
  end;

  PrefixNorm := NormalizePrefix(Prefix, H.KeyLen);
  KeyNorm := PrefixNorm;
  NormalizeKey(KeyNorm, H.KeyLen);

  DescendToFirstGE(F, H, KeyNorm, Stack, StackIdx, Depth);
  if DebugNDX and (Depth > 0) then
  begin
    ReadNDXNode(F, Stack[Depth - 1], H, NumKeys, Keys, Childs, Recnos, LastChild);
    if IsLeafNode(NumKeys, Childs) and (NumKeys > 0) then
      WriteLn('NDX DBG: start leaf ', Stack[Depth - 1], ' firstkey=',
        CleanKey(Keys[0]));
    if IsLeafNode(NumKeys, Childs) and (StackIdx[Depth - 1] < NumKeys) then
      WriteLn('NDX DBG: start leaf idx=', StackIdx[Depth - 1], ' key=',
        CleanKey(Keys[StackIdx[Depth - 1]]));
  end;
  while (Count < MaxCount) and NextEntry(F, H, Stack, StackIdx, Depth, KeyOut, RecnoOut) do
  begin
    KeyOut := NormalizePrefix(KeyOut, H.KeyLen);
    if not StartsWithKey(KeyOut, PrefixNorm) then
      Depth := 0
    else
    begin
      if RecnoOut <> 0 then
      begin
        RowIds^[Count] := RecnoOut;
        Inc(Count);
      end;
    end;
  end;

  Close(F);
  FindCharacterBegins := True;
end;

function FindNumberExact(NdxFileName: string; Value: LongInt;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
var
  F: File;
  H: TNDXHeader;
  Target: TKey8;
  Stack: TNDXBlockStack;
  StackIdx: TNDXIdxStack;
  Depth: Integer;
  KeyOut: string;
  RecnoOut: LongInt;
  KeyVal: TKey8;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
begin
  Count := 0;
  if RowIds = nil then
  begin
    FindNumberExact := False;
    Exit;
  end;
  if MaxCount <= 0 then
  begin
    FindNumberExact := False;
    Exit;
  end;

  Assign(F, NdxFileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then
  begin
    FindNumberExact := False;
    Exit;
  end;

  if not ReadNDXHeader(F, H) then
  begin
    Close(F);
    FindNumberExact := False;
    Exit;
  end;

  if H.KeyLen < 8 then
  begin
    Close(F);
    FindNumberExact := False;
    Exit;
  end;

  MakeKey8FromLongInt(Value, Target);
  DescendToFirstGE_Number(F, H, Target, Stack, StackIdx, Depth);
  if DebugNDX and (Depth > 0) then
  begin
    ReadNDXNode(F, Stack[Depth - 1], H, NumKeys, Keys, Childs, Recnos, LastChild);
    if IsLeafNode(NumKeys, Childs) and (NumKeys > 0) then
      WriteLn('NDX DBG: start leaf ', Stack[Depth - 1], ' firstkey=',
        CleanKey(Keys[0]));
  end;
  while (Count < MaxCount) and NextEntry(F, H, Stack, StackIdx, Depth, KeyOut, RecnoOut) do
  begin
    KeyStrToKey8(KeyOut, KeyVal);
    if CompareKey8(KeyVal, Target) <> 0 then
      Depth := 0
    else
    begin
      if RecnoOut <> 0 then
      begin
        RowIds^[Count] := RecnoOut;
        Inc(Count);
      end;
    end;
  end;

  Close(F);
  FindNumberExact := True;
end;

function FindNumberRange(NdxFileName: string; MinValue, MaxValue: LongInt;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
var
  F: File;
  H: TNDXHeader;
  MinKey, MaxKey: TKey8;
  Stack: TNDXBlockStack;
  StackIdx: TNDXIdxStack;
  Depth: Integer;
  KeyOut: string;
  RecnoOut: LongInt;
  KeyVal: TKey8;
  NumKeys: Integer;
  Keys: TNDXKeyArray;
  Childs, Recnos: TNDXIntArray;
  LastChild: LongInt;
begin
  Count := 0;
  if RowIds = nil then
  begin
    FindNumberRange := False;
    Exit;
  end;
  if MaxCount <= 0 then
  begin
    FindNumberRange := False;
    Exit;
  end;

  if MinValue > MaxValue then
  begin
    FindNumberRange := False;
    Exit;
  end;

  Assign(F, NdxFileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then
  begin
    FindNumberRange := False;
    Exit;
  end;

  if not ReadNDXHeader(F, H) then
  begin
    Close(F);
    FindNumberRange := False;
    Exit;
  end;

  if H.KeyLen < 8 then
  begin
    Close(F);
    FindNumberRange := False;
    Exit;
  end;

  MakeKey8FromLongInt(MinValue, MinKey);
  MakeKey8FromLongInt(MaxValue, MaxKey);
  DescendToFirstGE_Number(F, H, MinKey, Stack, StackIdx, Depth);
  if DebugNDX and (Depth > 0) then
  begin
    ReadNDXNode(F, Stack[Depth - 1], H, NumKeys, Keys, Childs, Recnos, LastChild);
    if IsLeafNode(NumKeys, Childs) and (NumKeys > 0) then
      WriteLn('NDX DBG: start leaf ', Stack[Depth - 1], ' firstkey=',
        CleanKey(Keys[0]));
  end;
  while (Count < MaxCount) and NextEntry(F, H, Stack, StackIdx, Depth, KeyOut, RecnoOut) do
  begin
    KeyStrToKey8(KeyOut, KeyVal);
    if CompareKey8(KeyVal, MinKey) < 0 then
    begin
      { Skip keys below the lower bound }
    end
    else if CompareKey8(KeyVal, MaxKey) > 0 then
      Depth := 0
    else
    begin
      if RecnoOut <> 0 then
      begin
        RowIds^[Count] := RecnoOut;
        Inc(Count);
      end;
    end;
  end;

  Close(F);
  FindNumberRange := True;
end;

function CountNumberExact(NdxFileName: string; Value: LongInt;
  var Count: LongInt): Boolean;
var
  F: File;
  H: TNDXHeader;
  Target: TKey8;
  Stack: TNDXBlockStack;
  StackIdx: TNDXIdxStack;
  Depth: Integer;
  KeyOut: string;
  RecnoOut: LongInt;
  KeyVal: TKey8;
begin
  Count := 0;
  Assign(F, NdxFileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then
  begin
    CountNumberExact := False;
    Exit;
  end;

  if not ReadNDXHeader(F, H) then
  begin
    Close(F);
    CountNumberExact := False;
    Exit;
  end;

  if H.KeyLen < 8 then
  begin
    Close(F);
    CountNumberExact := False;
    Exit;
  end;

  MakeKey8FromLongInt(Value, Target);
  DescendToFirstGE_Number(F, H, Target, Stack, StackIdx, Depth);
  while NextEntry(F, H, Stack, StackIdx, Depth, KeyOut, RecnoOut) do
  begin
    KeyStrToKey8(KeyOut, KeyVal);
    if CompareKey8(KeyVal, Target) <> 0 then
      Depth := 0
    else if RecnoOut <> 0 then
      Inc(Count);
  end;

  Close(F);
  CountNumberExact := True;
end;

function CountNumberRange(NdxFileName: string; MinValue, MaxValue: LongInt;
  var Count: LongInt): Boolean;
var
  F: File;
  H: TNDXHeader;
  MinKey, MaxKey: TKey8;
  Stack: TNDXBlockStack;
  StackIdx: TNDXIdxStack;
  Depth: Integer;
  KeyOut: string;
  RecnoOut: LongInt;
  KeyVal: TKey8;
begin
  Count := 0;
  if MinValue > MaxValue then
  begin
    CountNumberRange := False;
    Exit;
  end;

  Assign(F, NdxFileName);
  {$I-}
  Reset(F, 1);
  {$I+}
  if IOResult <> 0 then
  begin
    CountNumberRange := False;
    Exit;
  end;

  if not ReadNDXHeader(F, H) then
  begin
    Close(F);
    CountNumberRange := False;
    Exit;
  end;

  if H.KeyLen < 8 then
  begin
    Close(F);
    CountNumberRange := False;
    Exit;
  end;

  MakeKey8FromLongInt(MinValue, MinKey);
  MakeKey8FromLongInt(MaxValue, MaxKey);
  DescendToFirstGE_Number(F, H, MinKey, Stack, StackIdx, Depth);
  while NextEntry(F, H, Stack, StackIdx, Depth, KeyOut, RecnoOut) do
  begin
    KeyStrToKey8(KeyOut, KeyVal);
    if CompareKey8(KeyVal, MinKey) < 0 then
    begin
      { Skip keys below the lower bound }
    end
    else if CompareKey8(KeyVal, MaxKey) > 0 then
      Depth := 0
    else if RecnoOut <> 0 then
      Inc(Count);
  end;

  Close(F);
  CountNumberRange := True;
end;

function ParseDateString(S: string; var Y, M, D: Integer): Boolean;
var
  Code: Integer;
  T: string;
begin
  S := TrimString(S);
  if Length(S) = 8 then
  begin
    T := Copy(S, 1, 4);
    Val(T, Y, Code);
    if Code <> 0 then
    begin
      ParseDateString := False;
      Exit;
    end;
    T := Copy(S, 5, 2);
    Val(T, M, Code);
    if Code <> 0 then
    begin
      ParseDateString := False;
      Exit;
    end;
    T := Copy(S, 7, 2);
    Val(T, D, Code);
    if Code <> 0 then
    begin
      ParseDateString := False;
      Exit;
    end;
  end
  else if (Length(S) = 10) and (S[5] = '-') and (S[8] = '-') then
  begin
    T := Copy(S, 1, 4);
    Val(T, Y, Code);
    if Code <> 0 then
    begin
      ParseDateString := False;
      Exit;
    end;
    T := Copy(S, 6, 2);
    Val(T, M, Code);
    if Code <> 0 then
    begin
      ParseDateString := False;
      Exit;
    end;
    T := Copy(S, 9, 2);
    Val(T, D, Code);
    if Code <> 0 then
    begin
      ParseDateString := False;
      Exit;
    end;
  end
  else
  begin
    ParseDateString := False;
    Exit;
  end;

  if (M < 1) or (M > 12) or (D < 1) or (D > 31) then
  begin
    ParseDateString := False;
    Exit;
  end;
  ParseDateString := True;
end;

function GregorianToJDN(Y, M, D: Integer): LongInt;
var
  A: LongInt;
  Y2: LongInt;
  M2: LongInt;
begin
  A := (14 - M) div 12;
  Y2 := Y + 4800 - A;
  M2 := M + 12 * A - 3;
  GregorianToJDN := D + (153 * M2 + 2) div 5 + 365 * Y2 + Y2 div 4 -
    Y2 div 100 + Y2 div 400 - 32045;
end;

function DateStrToJDN(DateStr: string; var JDN: LongInt): Boolean;
var
  Y, M, D: Integer;
begin
  if not ParseDateString(DateStr, Y, M, D) then
  begin
    DateStrToJDN := False;
    Exit;
  end;
  JDN := GregorianToJDN(Y, M, D);
  DateStrToJDN := True;
end;

function FindDateExact(NdxFileName, DateStr: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
var
  JDN: LongInt;
begin
  if not DateStrToJDN(DateStr, JDN) then
  begin
    Count := 0;
    FindDateExact := False;
    Exit;
  end;
  FindDateExact := FindNumberExact(NdxFileName, JDN, RowIds, MaxCount, Count);
end;

function FindDateRange(NdxFileName, StartDateStr, EndDateStr: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
var
  JDNStart: LongInt;
  JDNEnd: LongInt;
  Temp: LongInt;
begin
  if not DateStrToJDN(StartDateStr, JDNStart) then
  begin
    Count := 0;
    FindDateRange := False;
    Exit;
  end;
  if not DateStrToJDN(EndDateStr, JDNEnd) then
  begin
    Count := 0;
    FindDateRange := False;
    Exit;
  end;
  if JDNStart > JDNEnd then
  begin
    Temp := JDNStart;
    JDNStart := JDNEnd;
    JDNEnd := Temp;
  end;
  FindDateRange := FindNumberRange(NdxFileName, JDNStart, JDNEnd, RowIds,
    MaxCount, Count);
end;

function CountDateExact(NdxFileName, DateStr: string; var Count: LongInt): Boolean;
var
  JDN: LongInt;
begin
  if not DateStrToJDN(DateStr, JDN) then
  begin
    Count := 0;
    CountDateExact := False;
    Exit;
  end;
  CountDateExact := CountNumberExact(NdxFileName, JDN, Count);
end;

function CountDateRange(NdxFileName, StartDateStr, EndDateStr: string;
  var Count: LongInt): Boolean;
var
  JDNStart: LongInt;
  JDNEnd: LongInt;
  Temp: LongInt;
begin
  if not DateStrToJDN(StartDateStr, JDNStart) then
  begin
    Count := 0;
    CountDateRange := False;
    Exit;
  end;
  if not DateStrToJDN(EndDateStr, JDNEnd) then
  begin
    Count := 0;
    CountDateRange := False;
    Exit;
  end;
  if JDNStart > JDNEnd then
  begin
    Temp := JDNStart;
    JDNStart := JDNEnd;
    JDNEnd := Temp;
  end;
  CountDateRange := CountNumberRange(NdxFileName, JDNStart, JDNEnd, Count);
end;

end.
