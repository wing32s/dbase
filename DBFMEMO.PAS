unit DBFMemo;

{ procedures for brute-force value matches }

interface

uses DBFUTIL, DBF;

const
  DBFMemoBlockSize = 512;
  DebugMemoImport = True;

type
  PDBFMemo = ^TDBFMemo;
  TDBFMemo = record
    F: File;
    IsOpen: Boolean;
    FileName: string[80];
  end;

  TMemoWriteState = record
    F: File;
    Open: Boolean;
    CloseOnEnd: Boolean;
    UseMemoHandle: Boolean;
    MemoPtr: PDBFMemo;
    StartBlock: LongInt;
    TotalLen: LongInt;
    Written: LongInt;
  end;
  
  { Dynamic array for memo block management }
  PLongIntArray = ^TLongIntArray;
  TLongIntArray = array[0..0] of LongInt;
  
  { Memo chunk management for streaming large memo fields }
  PMemoChunkArray = ^TMemoChunkArray;
  TMemoChunkArray = array[0..0] of string[255];

{ Memo compaction operations }
function GetUsedMemoBlocks(DBFFileName: string): PLongIntArray;
function CompactMemoFile(MemoFileName: string; UsedBlocks: PLongIntArray): PLongIntArray;
procedure UpdateMemoBlocks(DBFFileName: string; BlockMapping: PLongIntArray);

{ Memo chunk operations - Phase 1 }
function GetMemoChunk(MemoPtr: LongInt; ChunkIndex: Integer): string;
function WriteMemoChunk(MemoPtr: LongInt; ChunkIndex: Integer; ChunkText: string): Boolean;
function AppendMemoChunk(MemoPtr: LongInt; ChunkText: string): Boolean;
function GetMemoChunkCount(MemoPtr: LongInt): Integer;

function CreateMemoPointer(MemoText: string): LongInt;
function UpdateMemoPointer(var MemoPtr: LongInt; NewMemoPtr: LongInt): Boolean;

{ Memo file handle helpers (not wired yet) }
function DBFMemoOpen(var Memo: PDBFMemo; MemoFileName: string): Boolean;
function DBFMemoCreate(var Memo: PDBFMemo; MemoFileName: string): Boolean;
function DBFMemoClose(var Memo: PDBFMemo): Boolean;
function DBFMemoDispose(var Memo: PDBFMemo): Boolean;
function DBFMemoWriteM(var Memo: PDBFMemo; MemoType: LongInt; Text: string;
  var StartBlock: LongInt): Boolean;
function DBFMemoWriteBufferM(var Memo: PDBFMemo; MemoType: LongInt;
  var Buf; Len: LongInt; var StartBlock: LongInt): Boolean;
function DBFMemoWriteBeginM(var Memo: PDBFMemo; MemoType: LongInt;
  TotalLen: LongInt; var StartBlock: LongInt; var State: TMemoWriteState): Boolean;
function DBFMemoWriteBeginAtBlockM(var Memo: PDBFMemo; MemoType: LongInt;
  TotalLen: LongInt; StartBlock: LongInt; var State: TMemoWriteState): Boolean;
function DBFMemoGetInfoM(var Memo: PDBFMemo; StartBlock: LongInt;
  var MemoType: LongInt; var Len: LongInt): Boolean;
function DBFMemoReadChunkM(var Memo: PDBFMemo; StartBlock: LongInt;
  Offset: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;
function DBFMemoReadSmallM(var Memo: PDBFMemo; StartBlock: LongInt;
  var MemoType: LongInt; var Text: string): Boolean;
function DBFMemoReadBufferM(var Memo: PDBFMemo; StartBlock: LongInt;
  var MemoType: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;
function WriteMemoFromBufferM(var Memo: PDBFMemo; MemoType: LongInt;
  Buf: PByteArray; ContentStart, ContentLen: LongInt;
  var StartBlock: LongInt): Boolean;
function WriteMemoFromBufferAtBlockM(var Memo: PDBFMemo; MemoType: LongInt;
  Buf: PByteArray; ContentStart, ContentLen: LongInt; StartBlock: LongInt): Boolean;
function WriteMemoChunksM(var Memo: PDBFMemo; MemoBlock, MemoLen: LongInt;
  MemoType: LongInt; var OutF: Text): Boolean;

function DBFMemoWriteChunk(var State: TMemoWriteState; var Buf; Len: Word): Boolean;
function DBFMemoWriteEnd(var State: TMemoWriteState): Boolean;
function DBFMemoWriteEndAtBlock(var State: TMemoWriteState): Boolean;

implementation

function MemoPath(BaseName: string; var OutPath: string): Boolean;
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
    MemoPath := False;
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
    MemoPath := False;
    OutPath := '';
    Exit;
  end;
  if (Length(ExtPart) > 3) then
  begin
    MemoPath := False;
    OutPath := '';
    Exit;
  end;

  if (Length(ExtPart) = 0) then
    OutPath := PathPart + NamePart + '.DBT'
  else
    OutPath := PathPart + NamePart + '.' + ExtPart;
  MemoPath := True;
end;

function MemoAssign(var F: File; BaseName: string): Boolean;
var
  Path: string;
begin
  if not MemoPath(BaseName, Path) then
  begin
    MemoAssign := False;
    Exit;
  end;
  Assign(F, Path);
  MemoAssign := True;
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


function DecodeBase64ToMemo(P: PByteArray; Start, Len: LongInt; var State: TMemoWriteState): Boolean;
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
  DecodeBase64ToMemo := True;
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
            if not DBFMemoWriteChunk(State, OutBuf, OutLen) then
            begin
              DecodeBase64ToMemo := False;
              Exit;
            end;
            OutLen := 0;
          end;
          QLen := 0;
        end;
      end;
    end;
  end;
  if OutLen > 0 then
    if not DBFMemoWriteChunk(State, OutBuf, OutLen) then
    begin
      DecodeBase64ToMemo := False;
      Exit;
    end;
end;


function DecodeEscapedToMemo(P: PByteArray; Start, Len: LongInt; var State: TMemoWriteState): Boolean;
var
  I: LongInt;
  OutBuf: array[1..256] of Byte;
  OutLen: Word;
  C: Byte;
begin
  DecodeEscapedToMemo := True;
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
      if not DBFMemoWriteChunk(State, OutBuf, OutLen) then
      begin
        DecodeEscapedToMemo := False;
        Exit;
      end;
      OutLen := 0;
    end;
    Inc(I);
  end;
  if OutLen > 0 then
    if not DBFMemoWriteChunk(State, OutBuf, OutLen) then
    begin
      DecodeEscapedToMemo := False;
      Exit;
    end;
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

procedure DBFMemoAlloc(var Memo: PDBFMemo);
var
  P: PDBFMemo;
begin
  if Memo = nil then
  begin
    New(P);
    FillChar(P^, SizeOf(TDBFMemo), 0);
    Memo := P;
  end;
end;

function DBFMemoOpen(var Memo: PDBFMemo; MemoFileName: string): Boolean;
var
  P: PDBFMemo;
  Path: string;
  IoCode: Integer;
begin
  DBFMemoOpen := False;
  DBFMemoAlloc(Memo);
  if Memo = nil then
    Exit;
  if not MemoPath(MemoFileName, Path) then
    Exit;
  P := Memo;
  Assign(P^.F, Path);
  {$I-}
  Reset(P^.F, 1);
  IoCode := IOResult;
  {$I+}
  if IoCode <> 0 then
    Exit;
  P^.IsOpen := True;
  P^.FileName := Path;
  DBFMemoOpen := True;
end;

function DBFMemoCreate(var Memo: PDBFMemo; MemoFileName: string): Boolean;
var
  P: PDBFMemo;
  Path: string;
  IoCode: Integer;
begin
  DBFMemoCreate := False;
  DBFMemoAlloc(Memo);
  if Memo = nil then
    Exit;
  if not MemoPath(MemoFileName, Path) then
    Exit;
  P := Memo;
  Assign(P^.F, Path);
  {$I-}
  Rewrite(P^.F, 1);
  IoCode := IOResult;
  {$I+}
  if IoCode <> 0 then
    Exit;
  MemoInitFile(P^.F);
  P^.IsOpen := True;
  P^.FileName := Path;
  DBFMemoCreate := True;
end;

function DBFMemoClose(var Memo: PDBFMemo): Boolean;
var
  P: PDBFMemo;
begin
  if Memo = nil then
  begin
    DBFMemoClose := False;
    Exit;
  end;
  P := Memo;
  if P^.IsOpen then
    Close(P^.F);
  P^.IsOpen := False;
  DBFMemoClose := True;
end;

function DBFMemoDispose(var Memo: PDBFMemo): Boolean;
var
  P: PDBFMemo;
begin
  if Memo = nil then
  begin
    DBFMemoDispose := False;
    Exit;
  end;
  P := Memo;
  if P^.IsOpen then
    Close(P^.F);
  Dispose(P);
  Memo := nil;
  DBFMemoDispose := True;
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

function DBFMemoWriteM(var Memo: PDBFMemo; MemoType: LongInt; Text: string;
  var StartBlock: LongInt): Boolean;
var
  Dummy: Byte;
begin
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    StartBlock := 0;
    DBFMemoWriteM := False;
    Exit;
  end;
  if Length(Text) > 0 then
    DBFMemoWriteM := DBFMemoWriteBufferM(Memo, MemoType, Text[1], Length(Text), StartBlock)
  else
    DBFMemoWriteM := DBFMemoWriteBufferM(Memo, MemoType, Dummy, 0, StartBlock);
end;

function DBFMemoWriteBufferM(var Memo: PDBFMemo; MemoType: LongInt;
  var Buf; Len: LongInt; var StartBlock: LongInt): Boolean;
var
  State: TMemoWriteState;
begin
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    StartBlock := 0;
    DBFMemoWriteBufferM := False;
    Exit;
  end;
  if not DBFMemoWriteBeginM(Memo, MemoType, Len, StartBlock, State) then
  begin
    DBFMemoWriteBufferM := False;
    Exit;
  end;
  if Len > 0 then
    if not DBFMemoWriteChunk(State, Buf, Len) then
    begin
      if not DBFMemoWriteEnd(State) then ;
      DBFMemoWriteBufferM := False;
      Exit;
    end;
  DBFMemoWriteBufferM := DBFMemoWriteEnd(State);
end;

function DBFMemoWriteBeginM(var Memo: PDBFMemo; MemoType: LongInt;
  TotalLen: LongInt; var StartBlock: LongInt; var State: TMemoWriteState): Boolean;
var
  NextFree: LongInt;
  StartPos: LongInt;
begin
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    StartBlock := 0;
    DBFMemoWriteBeginM := False;
    Exit;
  end;
  DBFMemoWriteBeginM := False;
  StartBlock := 0;
  State.Open := False;
  State.CloseOnEnd := False;
  State.UseMemoHandle := True;
  State.MemoPtr := Memo;
  State.StartBlock := 0;
  State.TotalLen := 0;
  State.Written := 0;
  if TotalLen < 0 then
    TotalLen := 0;

  if not MemoReadHeader(Memo^.F, NextFree) then
  begin
    Seek(Memo^.F, 0);
    MemoInitFile(Memo^.F);
    NextFree := 1;
  end;

  StartBlock := NextFree;
  StartPos := StartBlock * DBFMemoBlockSize;
  Seek(Memo^.F, StartPos);
  WriteLongIntLE(Memo^.F, MemoType);
  WriteLongIntLE(Memo^.F, TotalLen);
  State.Open := True;
  State.StartBlock := StartBlock;
  State.TotalLen := TotalLen;
  State.Written := 0;
  DBFMemoWriteBeginM := True;
end;

function DBFMemoWriteBeginAtBlockM(var Memo: PDBFMemo; MemoType: LongInt;
  TotalLen: LongInt; StartBlock: LongInt; var State: TMemoWriteState): Boolean;
var
  NextFree: LongInt;
  StartPos: LongInt;
  TotalBytes: LongInt;
  BlocksNeeded: LongInt;
  FileLen: LongInt;
  MinSize: LongInt;
begin
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    DBFMemoWriteBeginAtBlockM := False;
    Exit;
  end;
  DBFMemoWriteBeginAtBlockM := False;
  State.Open := False;
  State.CloseOnEnd := False;
  State.UseMemoHandle := True;
  State.MemoPtr := Memo;
  State.StartBlock := 0;
  State.TotalLen := 0;
  State.Written := 0;
  if TotalLen < 0 then
    TotalLen := 0;
  if StartBlock < 1 then
    StartBlock := 1;

  if not MemoReadHeader(Memo^.F, NextFree) then
  begin
    Seek(Memo^.F, 0);
    MemoInitFile(Memo^.F);
    NextFree := 1;
  end;
  if DebugMemoImport then
    WriteLn('MEMO DBG: begin at block=', StartBlock, ' type=', MemoType, ' len=', TotalLen, ' nextfree=', NextFree);

  TotalBytes := 8 + TotalLen + 1;
  BlocksNeeded := (TotalBytes + DBFMemoBlockSize - 1) div DBFMemoBlockSize;
  MinSize := (StartBlock + BlocksNeeded) * DBFMemoBlockSize;
  FileLen := FileSize(Memo^.F);
  if FileLen < MinSize then
  begin
    Seek(Memo^.F, FileLen);
    MemoWriteZeros(Memo^.F, MinSize - FileLen);
  end;

  StartPos := StartBlock * DBFMemoBlockSize;
  Seek(Memo^.F, StartPos);
  WriteLongIntLE(Memo^.F, MemoType);
  WriteLongIntLE(Memo^.F, TotalLen);
  State.Open := True;
  State.StartBlock := StartBlock;
  State.TotalLen := TotalLen;
  State.Written := 0;
  DBFMemoWriteBeginAtBlockM := True;
end;

function DBFMemoGetInfoM(var Memo: PDBFMemo; StartBlock: LongInt;
  var MemoType: LongInt; var Len: LongInt): Boolean;
var
  StartPos: LongInt;
  MemoLen: LongInt;
begin
  MemoType := 0;
  Len := 0;
  DBFMemoGetInfoM := False;
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    Exit;
  end;
  if StartBlock <= 0 then
    Exit;

  StartPos := StartBlock * DBFMemoBlockSize;
  if FileSize(Memo^.F) <= StartPos then
    Exit;

  Seek(Memo^.F, StartPos);
  MemoType := ReadLongIntLE(Memo^.F);
  MemoLen := ReadLongIntLE(Memo^.F);
  if MemoLen < 0 then
    MemoLen := 0;
  Len := MemoLen;
  DBFMemoGetInfoM := True;
end;

function DBFMemoReadChunkM(var Memo: PDBFMemo; StartBlock: LongInt;
  Offset: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;
var
  StartPos: LongInt;
  MemoType: LongInt;
  MemoLen: LongInt;
  ToRead: LongInt;
begin
  ReadLen := 0;
  DBFMemoReadChunkM := False;
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    Exit;
  end;
  if (StartBlock <= 0) or (BufSize = 0) or (Offset < 0) then
    Exit;

  StartPos := StartBlock * DBFMemoBlockSize;
  if FileSize(Memo^.F) <= StartPos then
    Exit;

  Seek(Memo^.F, StartPos);
  MemoType := ReadLongIntLE(Memo^.F);
  MemoLen := ReadLongIntLE(Memo^.F);
  if MemoLen < 0 then
    MemoLen := 0;
  if Offset >= MemoLen then
  begin
    DBFMemoReadChunkM := True;
    Exit;
  end;

  Seek(Memo^.F, StartPos + 8 + Offset);
  ToRead := MemoLen - Offset;
  if ToRead > BufSize then
    ToRead := BufSize;
  BlockRead(Memo^.F, Buf, ToRead);
  ReadLen := ToRead;
  DBFMemoReadChunkM := True;
end;

function DBFMemoReadSmallM(var Memo: PDBFMemo; StartBlock: LongInt;
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
  Ok := DBFMemoGetInfoM(Memo, StartBlock, MemoType, MemoLen);
  if not Ok then
  begin
    DBFMemoReadSmallM := False;
    Exit;
  end;
  if MemoLen > 255 then
    MemoLen := 255;
  Offset := 0;
  while Offset < MemoLen do
  begin
    Ok := DBFMemoReadChunkM(Memo, StartBlock, Offset, Buf, SizeOf(Buf), ReadLen);
    if not Ok then
    begin
      DBFMemoReadSmallM := False;
      Exit;
    end;
    for I := 1 to ReadLen do
      Text := Text + Chr(Buf[I]);
    Inc(Offset, ReadLen);
    if ReadLen = 0 then
      Offset := MemoLen;
  end;
  DBFMemoReadSmallM := True;
end;

function DBFMemoReadBufferM(var Memo: PDBFMemo; StartBlock: LongInt;
  var MemoType: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;
var
  MemoLen: LongInt;
  ToRead: Word;
  Ok: Boolean;
begin
  ReadLen := 0;
  Ok := DBFMemoGetInfoM(Memo, StartBlock, MemoType, MemoLen);
  if not Ok then
  begin
    DBFMemoReadBufferM := False;
    Exit;
  end;
  if MemoLen < 0 then
    MemoLen := 0;
  if MemoLen > BufSize then
    ToRead := BufSize
  else
    ToRead := MemoLen;
  Ok := DBFMemoReadChunkM(Memo, StartBlock, 0, Buf, ToRead, ReadLen);
  DBFMemoReadBufferM := Ok;
end;

function WriteMemoFromBufferM(var Memo: PDBFMemo; MemoType: LongInt;
  Buf: PByteArray; ContentStart, ContentLen: LongInt;
  var StartBlock: LongInt): Boolean;
var
  DecLen: LongInt;
  State: TMemoWriteState;
begin
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    StartBlock := 0;
    WriteMemoFromBufferM := False;
    Exit;
  end;
  if ContentLen < 0 then
    ContentLen := 0;
  if MemoType = 2 then
    DecLen := Base64DecodedLen(Buf, ContentStart, ContentLen)
  else
    DecLen := EscapedDecodedLen(Buf, ContentStart, ContentLen);
  if DecLen < 0 then
  begin
    StartBlock := 0;
    WriteMemoFromBufferM := False;
    Exit;
  end;
  if not DBFMemoWriteBeginM(Memo, MemoType, DecLen, StartBlock, State) then
  begin
    WriteMemoFromBufferM := False;
    Exit;
  end;
  if MemoType = 2 then
  begin
    if not DecodeBase64ToMemo(Buf, ContentStart, ContentLen, State) then
    begin
      if not DBFMemoWriteEnd(State) then ;
      WriteMemoFromBufferM := False;
      Exit;
    end;
    if not DBFMemoWriteEnd(State) then
    begin
      WriteMemoFromBufferM := False;
      Exit;
    end;
  end
  else
  begin
    if not DecodeEscapedToMemo(Buf, ContentStart, ContentLen, State) then
    begin
      if not DBFMemoWriteEnd(State) then ;
      WriteMemoFromBufferM := False;
      Exit;
    end;
    if not DBFMemoWriteEnd(State) then
    begin
      WriteMemoFromBufferM := False;
      Exit;
    end;
  end;
  WriteMemoFromBufferM := StartBlock > 0;
end;

function WriteMemoFromBufferAtBlockM(var Memo: PDBFMemo; MemoType: LongInt;
  Buf: PByteArray; ContentStart, ContentLen: LongInt; StartBlock: LongInt): Boolean;
var
  DecLen: LongInt;
  State: TMemoWriteState;
begin
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    WriteMemoFromBufferAtBlockM := False;
    Exit;
  end;
  if ContentLen < 0 then
    ContentLen := 0;
  if MemoType = 2 then
    DecLen := Base64DecodedLen(Buf, ContentStart, ContentLen)
  else
    DecLen := EscapedDecodedLen(Buf, ContentStart, ContentLen);
  if DecLen < 0 then
  begin
    WriteMemoFromBufferAtBlockM := False;
    Exit;
  end;
  if not DBFMemoWriteBeginAtBlockM(Memo, MemoType, DecLen, StartBlock, State) then
  begin
    WriteMemoFromBufferAtBlockM := False;
    Exit;
  end;
  if MemoType = 2 then
  begin
    if not DecodeBase64ToMemo(Buf, ContentStart, ContentLen, State) then
    begin
      if not DBFMemoWriteEndAtBlock(State) then ;
      WriteMemoFromBufferAtBlockM := False;
      Exit;
    end;
    if not DBFMemoWriteEndAtBlock(State) then
    begin
      WriteMemoFromBufferAtBlockM := False;
      Exit;
    end;
  end
  else
  begin
    if not DecodeEscapedToMemo(Buf, ContentStart, ContentLen, State) then
    begin
      if not DBFMemoWriteEndAtBlock(State) then ;
      WriteMemoFromBufferAtBlockM := False;
      Exit;
    end;
    if not DBFMemoWriteEndAtBlock(State) then
    begin
      WriteMemoFromBufferAtBlockM := False;
      Exit;
    end;
  end;
  WriteMemoFromBufferAtBlockM := True;
end;

function WriteMemoChunksM(var Memo: PDBFMemo; MemoBlock, MemoLen: LongInt;
  MemoType: LongInt; var OutF: Text): Boolean;
var
  Offset: LongInt;
  ReadLen: Word;
  Chunk: array[1..256] of Byte;
  EncState: TB64EncState;
begin
  if (Memo = nil) or (not Memo^.IsOpen) then
  begin
    WriteMemoChunksM := False;
    Exit;
  end;
  WriteMemoChunksM := True;
  Offset := 0;
  if MemoType = 2 then
    B64EncInit(EncState);
  while Offset < MemoLen do
  begin
    if DBFMemoReadChunkM(Memo, MemoBlock, Offset, Chunk, SizeOf(Chunk), ReadLen) then
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
    begin
      WriteMemoChunksM := False;
      Exit;
    end;
  end;
  if MemoType = 2 then
    B64EncFinal(EncState, OutF);
end;

procedure MemoUpdateNextFree(var F: File; NextFree: LongInt);
begin
  Seek(F, 0);
  WriteLongIntLE(F, NextFree);
end;

function DBFMemoWriteBegin(MemoFileName: string; MemoType: LongInt;
  TotalLen: LongInt; var StartBlock: LongInt; var State: TMemoWriteState): Boolean;
var
  Res: Integer;
  NextFree: LongInt;
  StartPos: LongInt;
begin
  DBFMemoWriteBegin := False;
  StartBlock := 0;
  State.Open := False;
  State.CloseOnEnd := True;
  State.UseMemoHandle := False;
  State.MemoPtr := nil;
  State.StartBlock := 0;
  State.TotalLen := 0;
  State.Written := 0;
  if TotalLen < 0 then
    TotalLen := 0;
  if not MemoAssign(State.F, MemoFileName) then
    Exit;
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
  DBFMemoWriteBegin := True;
end;

function DBFMemoWriteChunk(var State: TMemoWriteState; var Buf; Len: Word): Boolean;
var
  ToWrite: Word;
begin
  if (not State.Open) or (Len = 0) then
  begin
    DBFMemoWriteChunk := False;
    Exit;
  end;
  if State.Written >= State.TotalLen then
  begin
    DBFMemoWriteChunk := True;
    Exit;
  end;
  ToWrite := Len;
  if (State.Written + ToWrite) > State.TotalLen then
    ToWrite := State.TotalLen - State.Written;
  if State.UseMemoHandle and (State.MemoPtr <> nil) then
    BlockWrite(State.MemoPtr^.F, Buf, ToWrite)
  else
    BlockWrite(State.F, Buf, ToWrite);
  Inc(State.Written, ToWrite);
  DBFMemoWriteChunk := True;
end;

function DBFMemoWriteEnd(var State: TMemoWriteState): Boolean;
var
  Remaining: LongInt;
  TotalLen: LongInt;
  BlocksNeeded: LongInt;
  PadLen: LongInt;
  NextFree: LongInt;
  Ch: Char;
begin
  if not State.Open then
  begin
    DBFMemoWriteEnd := False;
    Exit;
  end;

  Remaining := State.TotalLen - State.Written;
  if Remaining > 0 then
    if State.UseMemoHandle and (State.MemoPtr <> nil) then
      MemoWriteZeros(State.MemoPtr^.F, Remaining)
    else
      MemoWriteZeros(State.F, Remaining);

  Ch := Chr($1A);
  if State.UseMemoHandle and (State.MemoPtr <> nil) then
    BlockWrite(State.MemoPtr^.F, Ch, 1)
  else
    BlockWrite(State.F, Ch, 1);

  TotalLen := 8 + State.TotalLen + 1;
  BlocksNeeded := (TotalLen + DBFMemoBlockSize - 1) div DBFMemoBlockSize;
  PadLen := (BlocksNeeded * DBFMemoBlockSize) - TotalLen;
  if State.UseMemoHandle and (State.MemoPtr <> nil) then
    MemoWriteZeros(State.MemoPtr^.F, PadLen)
  else
    MemoWriteZeros(State.F, PadLen);

  NextFree := State.StartBlock + BlocksNeeded;
  if State.UseMemoHandle and (State.MemoPtr <> nil) then
    MemoUpdateNextFree(State.MemoPtr^.F, NextFree)
  else
    MemoUpdateNextFree(State.F, NextFree);
  if State.CloseOnEnd and (not State.UseMemoHandle) then
    Close(State.F);
  State.Open := False;
  DBFMemoWriteEnd := True;
end;

function DBFMemoWriteBeginAtBlock(MemoFileName: string; MemoType: LongInt;
  TotalLen: LongInt; StartBlock: LongInt; var State: TMemoWriteState): Boolean;
var
  Res: Integer;
  NextFree: LongInt;
  StartPos: LongInt;
  TotalBytes: LongInt;
  BlocksNeeded: LongInt;
  FileLen: LongInt;
  MinSize: LongInt;
begin
  DBFMemoWriteBeginAtBlock := False;
  State.Open := False;
  State.CloseOnEnd := True;
  State.UseMemoHandle := False;
  State.MemoPtr := nil;
  State.StartBlock := 0;
  State.TotalLen := 0;
  State.Written := 0;
  if TotalLen < 0 then
    TotalLen := 0;
  if StartBlock < 1 then
    StartBlock := 1;
  if not MemoAssign(State.F, MemoFileName) then
    Exit;
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
  DBFMemoWriteBeginAtBlock := True;
end;

function DBFMemoWriteEndAtBlock(var State: TMemoWriteState): Boolean;
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
  begin
    DBFMemoWriteEndAtBlock := False;
    Exit;
  end;

  Remaining := State.TotalLen - State.Written;
  if Remaining > 0 then
    if State.UseMemoHandle and (State.MemoPtr <> nil) then
      MemoWriteZeros(State.MemoPtr^.F, Remaining)
    else
      MemoWriteZeros(State.F, Remaining);

  Ch := Chr($1A);
  if State.UseMemoHandle and (State.MemoPtr <> nil) then
    BlockWrite(State.MemoPtr^.F, Ch, 1)
  else
    BlockWrite(State.F, Ch, 1);

  TotalLen := 8 + State.TotalLen + 1;
  BlocksNeeded := (TotalLen + DBFMemoBlockSize - 1) div DBFMemoBlockSize;
  PadLen := (BlocksNeeded * DBFMemoBlockSize) - TotalLen;
  if State.UseMemoHandle and (State.MemoPtr <> nil) then
    MemoWriteZeros(State.MemoPtr^.F, PadLen)
  else
    MemoWriteZeros(State.F, PadLen);

  if State.UseMemoHandle and (State.MemoPtr <> nil) then
  begin
    if MemoReadHeader(State.MemoPtr^.F, CurrentNextFree) then
    begin
      NextFree := State.StartBlock + BlocksNeeded;
      if NextFree > CurrentNextFree then
        MemoUpdateNextFree(State.MemoPtr^.F, NextFree);
    end;
  end
  else if MemoReadHeader(State.F, CurrentNextFree) then
  begin
    NextFree := State.StartBlock + BlocksNeeded;
    if NextFree > CurrentNextFree then
      MemoUpdateNextFree(State.F, NextFree);
  end;
  if DebugMemoImport then
    WriteLn('MEMO DBG: end at block=', State.StartBlock, ' blocks=', BlocksNeeded, ' nextfree=', NextFree);

  if State.CloseOnEnd and (not State.UseMemoHandle) then
    Close(State.F);
  State.Open := False;
  DBFMemoWriteEndAtBlock := True;
end;

function DBFMemoWriteBuffer(MemoFileName: string; MemoType: LongInt;
  var Buf; Len: LongInt; var StartBlock: LongInt): Boolean;
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
  DBFMemoWriteBuffer := False;
  StartBlock := 0;
  if Len < 0 then
    Len := 0;
  if not MemoAssign(F, MemoFileName) then
    Exit;
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
  DBFMemoWriteBuffer := True;
end;

function DBFMemoWrite(MemoFileName: string; MemoType: LongInt; Text: string;
  var StartBlock: LongInt): Boolean;
var
  Dummy: Byte;
begin
  if Length(Text) > 0 then
    DBFMemoWrite := DBFMemoWriteBuffer(MemoFileName, MemoType, Text[1], Length(Text), StartBlock)
  else
    DBFMemoWrite := DBFMemoWriteBuffer(MemoFileName, MemoType, Dummy, 0, StartBlock);
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
  if not MemoAssign(F, MemoFileName) then
    Exit;
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
  if not MemoAssign(F, MemoFileName) then
    Exit;
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


{ Memo chunk operations - Phase 1 Implementation }

{ Simple memo storage using temporary files }
const
  MemoExt = '.TMP';

var
  MemoCounter: LongInt;  { Global counter for unique IDs }

{ Generate 8.3-safe memo filename }
function MemoIdBase36(Value: LongInt): string;
const
  Digits: string[36] = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ';
var
  V: LongInt;
  R: Integer;
  S: string;
begin
  if Value < 0 then
    Value := -Value;
  if Value = 0 then
  begin
    MemoIdBase36 := '0';
    Exit;
  end;
  S := '';
  V := Value;
  while V > 0 do
  begin
    R := V mod 36;
    S := Digits[R + 1] + S;
    V := V div 36;
  end;
  MemoIdBase36 := S;
end;

function GetMemoFileName(MemoPtr: LongInt): string;
var
  IdStr: string;
begin
  IdStr := MemoIdBase36(MemoPtr);
  if Length(IdStr) > 7 then
    IdStr := Copy(IdStr, Length(IdStr) - 6, 7);
  GetMemoFileName := 'M' + IdStr + MemoExt;
end;


{ Get specific chunk from memo }
function GetMemoChunk(MemoPtr: LongInt; ChunkIndex: Integer): string;
const
  BlockSize = 512;
  DataOffset = 8;
var
  MemoFile: File;
  MemoFileName: string;
  MemoPathStr: string;
  Block: array[0..BlockSize-1] of Byte;
  ChunkText: string;
  DataLen: LongInt;
  I: Integer;
  BytesRead: Integer;
begin
  GetMemoChunk := '';
  MemoFileName := GetMemoFileName(MemoPtr);

  if not MemoPath(MemoFileName, MemoPathStr) then
    Exit;
  if not FileExists(MemoPathStr) then Exit;
  Assign(MemoFile, MemoPathStr);
  Reset(MemoFile, 1);  { Binary mode }

  { Seek to the requested block }
  Seek(MemoFile, ChunkIndex * BlockSize);

  if FilePos(MemoFile) >= FileSize(MemoFile) then
  begin
    Close(MemoFile);
    Exit;
  end;

  { Read 512-byte block }
  BlockRead(MemoFile, Block, BlockSize, BytesRead);

  if BytesRead < BlockSize then
  begin
    Close(MemoFile);
    Exit;
  end;

  { Extract data length from header (bytes 4-7) }
  DataLen := LongInt(Block[4]) or
             (LongInt(Block[5]) shl 8) or
             (LongInt(Block[6]) shl 16) or
             (LongInt(Block[7]) shl 24);

  { Extract text data from block }
  ChunkText := '';
  if DataLen > 0 then
  begin
    if DataLen > (BlockSize - DataOffset) then
      DataLen := BlockSize - DataOffset;

    ChunkText[0] := Chr(DataLen);  { Set string length }
    for I := 1 to DataLen do
      ChunkText[I] := Chr(Block[DataOffset + I - 1]);
  end;

  Close(MemoFile);
  GetMemoChunk := ChunkText;
end;

{ Write specific chunk to memo }
function WriteMemoChunk(MemoPtr: LongInt; ChunkIndex: Integer; ChunkText: string): Boolean;
const
  BlockSize = 512;
  DataOffset = 8;
  MaxDataPerBlock = BlockSize - DataOffset;  { 504 bytes of data per 512-byte block }
var
  MemoFile: File;
  MemoFileName: string;
  MemoPathStr: string;
  Block: array[0..BlockSize-1] of Byte;
  DataLen: LongInt;
  I: Integer;
  BytesToCopy: Integer;
begin
  WriteMemoChunk := False;
  MemoFileName := GetMemoFileName(MemoPtr);

  if not MemoPath(MemoFileName, MemoPathStr) then
    Exit;
  if not FileExists(MemoPathStr) then
    Exit;
  Assign(MemoFile, MemoPathStr);
  Reset(MemoFile, 1);  { Binary mode, read/write }

  { Seek to the requested block }
  Seek(MemoFile, ChunkIndex * BlockSize);

  if FilePos(MemoFile) >= FileSize(MemoFile) then
  begin
    Close(MemoFile);
    Exit;
  end;

  { Clear block }
  FillChar(Block, BlockSize, 0);

  { Truncate text to fit in one block }
  BytesToCopy := Length(ChunkText);
  if BytesToCopy > MaxDataPerBlock then
    BytesToCopy := MaxDataPerBlock;

  { Block header: bytes 0-3 = marker }
  Block[0] := $FF;
  Block[1] := $FF;
  Block[2] := $FF;
  Block[3] := $FF;

  { Block header: bytes 4-7 = data length }
  DataLen := BytesToCopy;
  Block[4] := Lo(Word(DataLen));
  Block[5] := Hi(Word(DataLen));
  Block[6] := Lo(Word(DataLen shr 16));
  Block[7] := Hi(Word(DataLen shr 16));

  { Copy text data }
  for I := 1 to BytesToCopy do
    Block[DataOffset + I - 1] := Ord(ChunkText[I]);

  { Write block at current position }
  BlockWrite(MemoFile, Block, BlockSize);

  Close(MemoFile);
  WriteMemoChunk := True;
end;

{ Append chunk to end of memo }
function AppendMemoChunk(MemoPtr: LongInt; ChunkText: string): Boolean;
const
  BlockSize = 512;
  DataOffset = 8;
  MaxDataPerBlock = BlockSize - DataOffset;  { 504 bytes of data per 512-byte block }
var
  MemoFile: File;
  MemoFileName: string;
  MemoPathStr: string;
  Block: array[0..BlockSize-1] of Byte;
  DataLen: LongInt;
  I: Integer;
  BytesToCopy: Integer;
begin
  AppendMemoChunk := False;
  MemoFileName := GetMemoFileName(MemoPtr);

  if not MemoPath(MemoFileName, MemoPathStr) then
    Exit;
  Assign(MemoFile, MemoPathStr);

  if FileExists(MemoPathStr) then
    Reset(MemoFile, 1)  { Binary mode, read/write }
  else
    Rewrite(MemoFile, 1);  { Binary mode }

  { Seek to end of file }
  Seek(MemoFile, FileSize(MemoFile));

  { Clear block }
  FillChar(Block, BlockSize, 0);

  { Truncate text to fit in one block }
  BytesToCopy := Length(ChunkText);
  if BytesToCopy > MaxDataPerBlock then
    BytesToCopy := MaxDataPerBlock;

  { Block header: bytes 0-3 = marker }
  Block[0] := $FF;
  Block[1] := $FF;
  Block[2] := $FF;
  Block[3] := $FF;

  { Block header: bytes 4-7 = data length }
  DataLen := BytesToCopy;
  Block[4] := Lo(Word(DataLen));
  Block[5] := Hi(Word(DataLen));
  Block[6] := Lo(Word(DataLen shr 16));
  Block[7] := Hi(Word(DataLen shr 16));

  { Copy text data }
  for I := 1 to BytesToCopy do
    Block[DataOffset + I - 1] := Ord(ChunkText[I]);

  { Write block at end }
  BlockWrite(MemoFile, Block, BlockSize);

  Close(MemoFile);
  AppendMemoChunk := True;
end;

{ Get total number of chunks in memo }
function GetMemoChunkCount(MemoPtr: LongInt): Integer;
const
  BlockSize = 512;
var
  MemoFile: File;
  MemoFileName: string;
  MemoPathStr: string;
  ChunkCount: Integer;
  FileLen: LongInt;
begin
  GetMemoChunkCount := 0;
  MemoFileName := GetMemoFileName(MemoPtr);

  if not MemoPath(MemoFileName, MemoPathStr) then
    Exit;
  if not FileExists(MemoPathStr) then Exit;
  Assign(MemoFile, MemoPathStr);
  Reset(MemoFile, 1);  { Binary mode }

  { Calculate number of 512-byte blocks }
  FileLen := FileSize(MemoFile);
  ChunkCount := FileLen div BlockSize;

  Close(MemoFile);
  GetMemoChunkCount := ChunkCount;
end;

{ Create memo pointer from initial text }
function CreateMemoPointer(MemoText: string): LongInt;
const
  BlockSize = 512;
  DataOffset = 8;  { Header is 8 bytes: 4 bytes marker + 4 bytes length }
  MaxDataPerBlock = BlockSize - DataOffset;  { 504 bytes of data per 512-byte block }
var
  MemoFile: File;
  MemoFileName: string;
  MemoPathStr: string;
  TempPtr: LongInt;
  Block: array[0..BlockSize-1] of Byte;
  TextPos: Integer;
  BlockCount: Integer;
  BytesToCopy: Integer;
  DataLen: LongInt;
  I: Integer;
begin
  CreateMemoPointer := 0;
  if MemoCounter = 0 then MemoCounter := 1;

  TempPtr := MemoCounter;
  Inc(MemoCounter);
  MemoFileName := GetMemoFileName(TempPtr);

  if not MemoPath(MemoFileName, MemoPathStr) then
    Exit;
  Assign(MemoFile, MemoPathStr);
  {$I-}
  Rewrite(MemoFile, 1);  { Record size = 1 byte for binary file }
  {$I+}
  if IOResult <> 0 then
    Exit;

  TextPos := 1;
  BlockCount := 0;

  { Write memo text in 512-byte blocks }
  while TextPos <= Length(MemoText) do
  begin
    { Clear block }
    FillChar(Block, BlockSize, 0);

    { Calculate how much data to write in this block }
    BytesToCopy := Length(MemoText) - TextPos + 1;
    if BytesToCopy > MaxDataPerBlock then
      BytesToCopy := MaxDataPerBlock;

    { Block header: bytes 0-3 = marker (FFFFFFFFh for data block) }
    Block[0] := $FF;
    Block[1] := $FF;
    Block[2] := $FF;
    Block[3] := $FF;

    { Block header: bytes 4-7 = data length in this block }
    DataLen := BytesToCopy;
    Block[4] := Lo(Word(DataLen));
    Block[5] := Hi(Word(DataLen));
    Block[6] := Lo(Word(DataLen shr 16));
    Block[7] := Hi(Word(DataLen shr 16));

    { Copy text data starting at offset 8 }
    for I := 1 to BytesToCopy do
      Block[DataOffset + I - 1] := Ord(MemoText[TextPos + I - 1]);

    { Write 512-byte block }
    {$I-}
    BlockWrite(MemoFile, Block, BlockSize);
    {$I+}
    if IOResult <> 0 then
    begin
      Close(MemoFile);
      Exit;
    end;

    Inc(TextPos, BytesToCopy);
    Inc(BlockCount);
  end;

  Close(MemoFile);
  CreateMemoPointer := TempPtr;
end;

{ Update memo pointer to new memo }
function UpdateMemoPointer(var MemoPtr: LongInt; NewMemoPtr: LongInt): Boolean;
var
  OldFileName: string;
  TempFile: File;
  IoCode: Integer;
begin
  UpdateMemoPointer := False;
  { Clean up old memo file }
  OldFileName := GetMemoFileName(MemoPtr);

  {$I-}  { Turn off I/O checking }
  Assign(TempFile, OldFileName);
  Erase(TempFile);  { Erase needs file variable }
  IoCode := IOResult;
  {$I+}  { Turn on I/O checking }

  { Update pointer }
  MemoPtr := NewMemoPtr;
  UpdateMemoPointer := (IoCode = 0);
end;

{ Get memo text from pointer }
function GetMemoFromPointer(MemoPtr: LongInt): string;
var
  MemoFileName: string;
  ChunkCount: Integer;
  I: Integer;
  ChunkText: string;
  Buf: string;
begin
  GetMemoFromPointer := '';
  MemoFileName := GetMemoFileName(MemoPtr);

  if not FileExists(MemoFileName) then Exit;

  { Get total number of chunks }
  ChunkCount := GetMemoChunkCount(MemoPtr);

  { Concatenate all chunks }
  Buf := '';
  for I := 0 to ChunkCount - 1 do
  begin
    ChunkText := GetMemoChunk(MemoPtr, I);
    Buf := Buf + ChunkText;
  end;

  GetMemoFromPointer := Buf;
end;


{ Memo chunking functions }
function CountMemoChunks(MemoText: string): Integer;
begin
  if Length(MemoText) = 0 then
    CountMemoChunks := 0
  else
    CountMemoChunks := (Length(MemoText) - 1) div 255 + 1;
end;

function GetMemoTextChunk(MemoText: string; ChunkIndex: Integer): string;
var
  StartPos, EndPos: Integer;
begin
  StartPos := ChunkIndex * 255 + 1;
  EndPos := StartPos + 254;
  
  if StartPos > Length(MemoText) then
    GetMemoTextChunk := ''
  else
  begin
    if EndPos > Length(MemoText) then
      EndPos := Length(MemoText);
    GetMemoTextChunk := Copy(MemoText, StartPos, EndPos - StartPos + 1);
  end;
end;

function AssembleMemoChunks(Chunks: PMemoChunkArray; ChunkCount: Integer): string;
var
  I: Integer;
  Buf : string;
begin
  Buf := '';
  for I := 0 to ChunkCount - 1 do
    Buf := Buf + Chunks^[I];
  AssembleMemoChunks := Buf;
end;

function WriteMemoChunks(MemoFileName: string; MemoBlock, MemoLen: LongInt;
  MemoType: LongInt; var OutF: Text): Boolean;
var
  Offset: LongInt;
  ReadLen: Word;
  Chunk: array[1..256] of Byte;
  EncState: TB64EncState;
begin
  WriteMemoChunks := True;
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
    begin
      WriteMemoChunks := False;
      Exit;
    end;
  end;
  if MemoType = 2 then
    B64EncFinal(EncState, OutF);
end;

function WriteMemoFromBuffer(MemoFileName: string; MemoType: LongInt;
  Buf: PByteArray; ContentStart, ContentLen: LongInt;
  var StartBlock: LongInt): Boolean;
var
  DecLen: LongInt;
  State: TMemoWriteState;
begin
  WriteMemoFromBuffer := False;
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
    if not DBFMemoWriteBegin(MemoFileName, MemoType, DecLen, StartBlock, State) then
    begin
      StartBlock := 0;
      Exit;
    end;
    if DebugMemoImport then
      WriteLn('MEMO DBG: append startblock=', StartBlock);
    if MemoType = 1 then
    begin
      if not DecodeEscapedToMemo(Buf, ContentStart, ContentLen, State) then
      begin
        StartBlock := 0;
        if State.Open then
          if not DBFMemoWriteEnd(State) then ;
        Exit;
      end;
    end
    else if MemoType = 2 then
    begin
      if not DecodeBase64ToMemo(Buf, ContentStart, ContentLen, State) then
      begin
        StartBlock := 0;
        if State.Open then
          if not DBFMemoWriteEnd(State) then ;
        Exit;
      end;
    end;
    if not DBFMemoWriteEnd(State) then
      StartBlock := 0;
    WriteMemoFromBuffer := StartBlock > 0;
  end
  else
    StartBlock := 0;
end;

function WriteMemoFromBufferAtBlock(MemoFileName: string; MemoType: LongInt;
  Buf: PByteArray; ContentStart, ContentLen: LongInt; StartBlock: LongInt): Boolean;
var
  DecLen: LongInt;
  State: TMemoWriteState;
begin
  WriteMemoFromBufferAtBlock := False;
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
  if not DBFMemoWriteBeginAtBlock(MemoFileName, MemoType, DecLen, StartBlock, State) then
    Exit;
  if MemoType = 1 then
  begin
    if not DecodeEscapedToMemo(Buf, ContentStart, ContentLen, State) then
    begin
      if State.Open then
        if not DBFMemoWriteEndAtBlock(State) then ;
      Exit;
    end;
  end
  else if MemoType = 2 then
  begin
    if not DecodeBase64ToMemo(Buf, ContentStart, ContentLen, State) then
    begin
      if State.Open then
        if not DBFMemoWriteEndAtBlock(State) then ;
      Exit;
    end;
  end;
  if not DBFMemoWriteEndAtBlock(State) then
    Exit;
  WriteMemoFromBufferAtBlock := True;
end;

{ Memo compaction operations }

function GetUsedMemoBlocks(DBFFileName: string): PLongIntArray;
var
  Dbf: PDBFFile;
  Header: TDBFHeader;
  RowIndex, RowCount: LongInt;
  FieldIdx: Integer;
  Buf: Pointer;
  BlockNum: LongInt;
  UsedBlocks: PLongIntArray;
  BlockCount: Integer;
  I: Integer;
  Found: Boolean;
  FieldValue: string;
  ReturnVal: PLongIntArray;
  Ok: Boolean;
begin
  ReturnVal := nil;
  Dbf := nil;
  Ok := DBFFileOpen(Dbf, DBFFileName);
  if not Ok then Exit;
  
  if not DBFFileGetHeader(Dbf, Header) then
  begin
    if not DBFFileClose(Dbf) then ;
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;
  
  RowCount := DBFFileGetActualRowCount(Dbf);
  
  { Temporary array for collecting blocks }
  GetMem(UsedBlocks, 1000 * SizeOf(LongInt));  { Max 1000 memo blocks }
  BlockCount := 0;
  
  GetMem(Buf, Header.RecordSize);
  
  if not DBFFileSeekToFirstRow(Dbf) then ;
  
  for RowIndex := 0 to RowCount - 1 do
  begin
    if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then ;
    
    for FieldIdx := 1 to Header.FieldCount do
    begin
      if UpCase(Header.Fields[FieldIdx].FieldType) = 'M' then
      begin
        FieldValue := DBFFieldGetStr(Buf, Header, FieldIdx);
        BlockNum := ParseInt(TrimString(FieldValue));
        if BlockNum > 0 then
        begin
          { Check if block already in list }
          Found := False;
          I := 0;
          while (I < BlockCount) and (not Found) do
          begin
            if UsedBlocks^[I] = BlockNum then
              Found := True
            else
              Inc(I);
          end;
          
          if not Found then
          begin
            UsedBlocks^[BlockCount] := BlockNum;
            Inc(BlockCount);
          end;
        end;
      end;
    end;
  end;
  
  { Create properly sized array }
  if BlockCount > 0 then
  begin
    GetMem(ReturnVal, BlockCount * SizeOf(LongInt));
    for I := 0 to BlockCount - 1 do
      ReturnVal^[I] := UsedBlocks^[I];
    GetUsedMemoBlocks := ReturnVal;
  end;
  
  { Clean up }
  if Buf <> nil then FreeMem(Buf, Header.RecordSize);
  if UsedBlocks <> nil then FreeMem(UsedBlocks, 1000 * SizeOf(LongInt));
  if not DBFFileClose(Dbf) then ;
  if not DBFFileDispose(Dbf) then ;
end;

function CompactMemoFile(MemoFileName: string; UsedBlocks: PLongIntArray): PLongIntArray;
var
  InF, OutF: File;
  TempFileName: string;
  MemoPathStr: string;
  TempPathStr: string;
  Ok: Boolean;
  BlockCount, I: Integer;
  OldBlock, NewBlock: LongInt;
  MemoType, MemoLen: LongInt;
  Offset: LongInt;
  ReadLen: Word;
  Chunk: array[1..256] of Byte;
  State: TMemoWriteState;
  BlockMapping: PLongIntArray;

begin
  CompactMemoFile := nil;
  TempFileName := MemoFileName + 'T';

  { Count used blocks }
  BlockCount := 0;
  while UsedBlocks^[BlockCount] > 0 do Inc(BlockCount);

  if BlockCount = 0 then Exit;

  { Create block mapping array }
  GetMem(BlockMapping, BlockCount * SizeOf(LongInt));

  if not MemoPath(MemoFileName, MemoPathStr) then
    Exit;
  Assign(InF, MemoPathStr);
  Reset(InF, 1);

  if not MemoPath(TempFileName, TempPathStr) then
  begin
    Close(InF);
    Exit;
  end;
  Assign(OutF, TempPathStr);
  Rewrite(OutF, 1);
  MemoInitFile(OutF);
  
  { Copy used memo blocks to new file }
  for I := 0 to BlockCount - 1 do
  begin
    OldBlock := UsedBlocks^[I];
    NewBlock := I + 1;  { New blocks start from 1 }
    BlockMapping^[I] := NewBlock;
    
    if DBFMemoGetInfo(MemoFileName, OldBlock, MemoType, MemoLen) then
    begin
      if not DBFMemoWriteBegin(TempFileName, MemoType, MemoLen, NewBlock, State) then
      begin
        Close(InF);
        Close(OutF);
        if BlockMapping <> nil then
          FreeMem(BlockMapping, BlockCount * SizeOf(LongInt));
        Exit;
      end;
      Offset := 0;
      while Offset < MemoLen do
      begin
        if DBFMemoReadChunk(MemoFileName, OldBlock, Offset, Chunk, SizeOf(Chunk), ReadLen) then
        begin
          if ReadLen > 0 then
            if not DBFMemoWriteChunk(State, Chunk, ReadLen) then
            begin
              if State.Open then
                if not DBFMemoWriteEnd(State) then ;
              Close(InF);
              Close(OutF);
              if BlockMapping <> nil then
                FreeMem(BlockMapping, BlockCount * SizeOf(LongInt));
              Exit;
            end;
          Inc(Offset, ReadLen);
          if ReadLen = 0 then Offset := MemoLen;
        end
        else
          Offset := MemoLen;
      end;
      if not DBFMemoWriteEnd(State) then
      begin
        Close(InF);
        Close(OutF);
        if BlockMapping <> nil then
          FreeMem(BlockMapping, BlockCount * SizeOf(LongInt));
        Exit;
      end;
    end;
  end;
  
  Close(InF);
  Close(OutF);
  
  { Replace original file }
  if not MemoPath(MemoFileName, MemoPathStr) then
    Exit;
  if not MemoPath(TempFileName, TempPathStr) then
    Exit;
  Ok := DeleteFile(MemoPathStr);
  Ok := RenameFile(TempPathStr, MemoPathStr);
  
  CompactMemoFile := BlockMapping;
end;

procedure UpdateMemoBlocks(DBFFileName: string; BlockMapping: PLongIntArray);
var
  Dbf: PDBFFile;
  Header: TDBFHeader;
  RowIndex, RowCount: LongInt;
  FieldIdx: Integer;
  Buf: Pointer;
  Values: Pointer;
  BlockNum: LongInt;
  I: Integer;
  BlockStr: string;
  FieldValue: string;
  Ok: Boolean;
begin
  Dbf := nil;
  Ok := DBFFileOpen(Dbf, DBFFileName);
  if not Ok then Exit;
  
  if not DBFFileGetHeader(Dbf, Header) then
  begin
    if not DBFFileClose(Dbf) then ;
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;
  
  RowCount := DBFFileGetActualRowCount(Dbf);
  
  GetMem(Buf, Header.RecordSize);
  Values := AllocateSmartValueArray(Header);
  
  if not DBFFileSeekToFirstRow(Dbf) then ;
  
  for RowIndex := 0 to RowCount - 1 do
  begin
    if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then ;
    
    { Initialize values }
    for FieldIdx := 1 to Header.FieldCount do
      if not DBFFieldSetStr(Values, Header, FieldIdx, '') then ;
    
    for FieldIdx := 1 to Header.FieldCount do
    begin
      if UpCase(Header.Fields[FieldIdx].FieldType) = 'M' then
      begin
        FieldValue := DBFFieldGetStr(Buf, Header, FieldIdx);
        BlockNum := ParseInt(TrimString(FieldValue));
        if BlockNum > 0 then
        begin
          { Find new block number }
          I := 0;
          while (I < 1000) do  { Max blocks }
          begin
            if BlockMapping^[I] = 0 then
            begin
              I := 1000;  { Exit loop }
            end
            else if BlockMapping^[I] = BlockNum then
            begin
              Str(BlockMapping^[I], BlockStr);
              if not DBFFieldSetStr(Values, Header, FieldIdx, BlockStr) then ;
              I := 1000;  { Exit loop }
            end
            else
              Inc(I);
          end;
        end
        else
          if not DBFFieldSetStr(Values, Header, FieldIdx, '0') then ;
      end
      else
        if not DBFFieldSetStr(Values, Header, FieldIdx, DBFFieldGetStr(Buf, Header, FieldIdx)) then ;
    end;
    
    if not DBFFileWriteRow(Dbf, Values, Header.FieldCount) then ;
  end;
  
  { Clean up }
  if Buf <> nil then FreeMem(Buf, Header.RecordSize);
  if Values <> nil then if not FreeSmartValueArray(Values) then ;
  Ok := DBFFileClose(Dbf);
  Ok := DBFFileDispose(Dbf);
end;

end.
