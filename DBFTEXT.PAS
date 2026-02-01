unit DBFTEXT;

interface

uses DBFUTIL, DBF, DBFMEMO;

procedure ExportDBFToText(FileName: string);
procedure ImportDBFFromText(FileName: string);
procedure ImportDBFFromTextStreaming(FileName: string);  { Memory-optimized streaming version }
procedure ImportDBFFromTextFieldByField(FileName: string);  { Field-by-field minimal memory version }
procedure ImportDBFFromTextPacked(FileName: string);  { Packed buffer - maximum efficiency version }

procedure ExportDBFMemosToText(FileName: string);
procedure ImportDBFMemosFromText(FileName: string);
procedure ImportDBFMemosFromTextEx(FileName: string; PreserveBlocks: Boolean);

function ParseMemoLine(Buf: PByteArray; BufLen: LongInt; var RowIndex: LongInt;
  var FieldIdx: Integer; var MemoType: LongInt; var BlockNum: LongInt;
  var HasBlock: Boolean; var ContentStart: LongInt; var ContentLen: LongInt): Boolean;

implementation


function CountPipeFields(Line: string): Integer;
var
  I, Count: Integer;
begin
  Count := 0;
  for I := 1 to Length(Line) do
    if Line[I] = '|' then
      Inc(Count);
  if Length(Line) > 0 then
    Inc(Count);
  CountPipeFields := Count;
end;


function ExtractPipeField(Line: string; FieldNum: Integer): string;
var
  I, StartPos, EndPos, CurrentField: Integer;
begin
  StartPos := 1;
  CurrentField := 1;
  
  { Find start position }
  while (CurrentField < FieldNum) and (StartPos <= Length(Line)) do
  begin
    if Line[StartPos] = '|' then
      Inc(CurrentField);
    Inc(StartPos);
  end;
  
  { Find end position }
  EndPos := StartPos;
  while (EndPos <= Length(Line)) and (Line[EndPos] <> '|') do
    Inc(EndPos);
  
  if StartPos <= Length(Line) then
    ExtractPipeField := Copy(Line, StartPos, EndPos - StartPos)
  else
    ExtractPipeField := '';
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

procedure SplitPipe(Line: string; Values: Pointer; var Count: Integer; Header: TDBFHeader);
var
  I: Integer;
  S: string;
begin
  Count := 0;
  S := '';
  for I := 1 to Length(Line) do
  begin
    if Line[I] = '|' then
    begin
      Inc(Count);
      if Count <= Header.FieldCount then
        if not DBFFieldSetStr(Values, Header, Count, S) then ;
      S := '';
    end
    else
      S := S + Line[I];
  end;
  Inc(Count);
  if Count <= Header.FieldCount then
    if not DBFFieldSetStr(Values, Header, Count, S) then ;
end;

procedure ExportDBFToText(FileName: string);
var
  Dbf: PDBFFile;
  Header: TDBFHeader;
  F: Text;
  Buf: Pointer;
  FieldIdx: Integer;
  Line: string;
  RowIndex, RowCount: LongInt;
  DBFFileName, TextFileName: string;
  Ok: Boolean;
begin
  if not IsValid83FileName(FileName) then
  begin
    WriteLn('ERROR: invalid 8.3 filename: ', FileName);
    Exit;
  end;
  DBFFileName := FileName;
  TextFileName := FileName + '.TXT';
  Dbf := nil;
  Ok := DBFFileOpen(Dbf, DBFFileName);
  if not Ok then Exit;
  
  if not DBFFileGetHeader(Dbf, Header) then
  begin
    if not DBFFileClose(Dbf) then ;
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;
  
  Assign(F, TextFileName);
  Rewrite(F);

  Line := '';
  for FieldIdx := 1 to Header.FieldCount do
  begin
    if FieldIdx > 1 then
      Line := Line + '|';
    Line := Line + Header.Fields[FieldIdx].Name;
  end;
  WriteLn(F, Line);

  Line := '';
  for FieldIdx := 1 to Header.FieldCount do
  begin
    if FieldIdx > 1 then
      Line := Line + '|';
    Line := Line + BuildFieldSpec(Header.Fields[FieldIdx]);
  end;
  WriteLn(F, Line);

  RowCount := DBFFileGetActualRowCount(Dbf);
  if not DBFFileSeekToFirstRow(Dbf) then ;
  
  GetMem(Buf, Header.RecordSize);
  
  for RowIndex := 0 to RowCount - 1 do
  begin
    if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then ;
    
    { Check if row is not deleted }
    if PByteArray(Buf)^[0] <> Ord('*') then
    begin
      Line := '';
      for FieldIdx := 1 to Header.FieldCount do
      begin
        if FieldIdx > 1 then
          Line := Line + '|';
        Line := Line + TrimString(DBFFieldGetStr(Buf, Header, FieldIdx));
      end;
      WriteLn(F, Line);
    end;
  end;
  
  { Clean up }
  if Buf <> nil then FreeMem(Buf, Header.RecordSize);
  Close(F);
  if not DBFFileClose(Dbf) then ;
  if not DBFFileDispose(Dbf) then ;
end;

procedure ImportDBFFromText(FileName: string);
var
  F: Text;
  Line1, Line2, Line: string;
  NameCount, SpecCount, ValueCount: Integer;
  Header: TDBFHeader;
  FieldType: Char;
  Len, Dec: Byte;
  I: Integer;
  Dbf: PDBFFile;
  Values: Pointer;
  TextFileName, DBFFileName: string;
  Ok: Boolean;
begin
  if not IsValid83FileName(FileName) then
  begin
    WriteLn('ERROR: invalid 8.3 filename: ', FileName);
    Exit;
  end;
  TextFileName := FileName + '.TXT';
  DBFFileName := FileName + '.DBF';
  WriteLn('Importing database from ' + TextFileName + ' to ' + DBFFileName);
  Assign(F, TextFileName);
  Reset(F);
  if EOF(F) then
  begin
    Close(F);
    Exit;
  end;
  ReadLn(F, Line1);
  if EOF(F) then
  begin
    Close(F);
    Exit;
  end;
  ReadLn(F, Line2);

  NameCount := CountPipeFields(Line1);
  SpecCount := CountPipeFields(Line2);
  if NameCount <> SpecCount then
  begin
    Close(F);
    Exit;
  end;

  FillChar(Header, SizeOf(Header), 0);
  Header.FieldCount := NameCount;
  for I := 1 to Header.FieldCount do
  begin
    Header.Fields[I].Name := TrimString(ExtractPipeField(Line1, I));
    if Length(Header.Fields[I].Name) > 11 then
      Header.Fields[I].Name := Copy(Header.Fields[I].Name, 1, 11);
    FieldType := 'C';
    Len := 1;
    Dec := 0;
    if ParseFieldSpec(ExtractPipeField(Line2, I), FieldType, Len, Dec) then
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
  Ok := DBFFileCreate(Dbf, FileName, Header);
  if not Ok then
  begin
    Close(F);
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;

  { Allocate SmartValueArray for Values }
  Values := AllocateSmartValueArray(Header);

  { Stream processing - read and process one line at a time }
  while not EOF(F) do
  begin
    ReadLn(F, Line);
    if TrimString(Line) <> '' then
    begin
      SplitPipe(Line, Values, ValueCount, Header);
      for I := ValueCount + 1 to Header.FieldCount do
        if not DBFFieldSetStr(Values, Header, I, '') then ;

      if not DBFFileAppendRow(Dbf, Values, Header.FieldCount) then ;
    end;
  end;
  Close(F);
  if not DBFFileClose(Dbf) then ;
  if not DBFFileDispose(Dbf) then ;
  if not FreeSmartValueArray(Values) then ;
end;


{ Field-by-field packed import - maximum memory efficiency }
procedure ImportDBFFromTextPacked(FileName: string);
var
  F: Text;
  Line1, Line2, Line: string;
  Values: Pointer;
  FieldCount, I, ValueCount: Integer;
  Header: TDBFHeader;
  FieldType: Char;
  Len, Dec: Byte;
  Dbf: PDBFFile;
  TextFileName, DBFFileName: string;
  ProcessedCount: LongInt;
  Ok: Boolean;
begin
  TextFileName := FileName + '.TXT';
  DBFFileName := FileName + '.DBF';
  WriteLn('Smart import from ' + TextFileName + ' to ' + DBFFileName);
  
  Assign(F, TextFileName);
  Reset(F);
  if EOF(F) then
  begin
    Close(F);
    Exit;
  end;
  
  { Read header lines }
  ReadLn(F, Line1);
  if EOF(F) then
  begin
    Close(F);
    Exit;
  end;
  ReadLn(F, Line2);

  { Count actual fields needed }
  FieldCount := CountPipeFields(Line1);
  if FieldCount > DBFMaxFields then
    FieldCount := DBFMaxFields;
    
  WriteLn('Detected ', FieldCount, ' fields - allocating smart memory');

  { Parse field definitions first, then allocate }
  FillChar(Header, SizeOf(Header), 0);
  Header.FieldCount := FieldCount;

  for I := 0 to FieldCount - 1 do
  begin
    { Extract field name and spec }
    FieldType := 'C';
    Len := 1;
    Dec := 0;
    
    if ParseFieldSpec(ExtractPipeField(Line2, I + 1), FieldType, Len, Dec) then
    begin
      Header.Fields[I + 1].FieldType := FieldType;
      Header.Fields[I + 1].Length := Len;
      Header.Fields[I + 1].Decimals := Dec;
    end
    else
    begin
      Header.Fields[I + 1].FieldType := 'C';
      Header.Fields[I + 1].Length := 1;
      Header.Fields[I + 1].Decimals := 0;
    end;
    
    { Extract field name }
    Header.Fields[I + 1].Name := ExtractPipeField(Line1, I + 1);
    if Length(Header.Fields[I + 1].Name) > 11 then
      Header.Fields[I + 1].Name := Copy(Header.Fields[I + 1].Name, 1, 11);
  end;

  Dbf := nil;
  Ok := DBFFileCreate(Dbf, FileName, Header);
  if not Ok then
  begin
    Close(F);
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;

  { Allocate SmartValueArray after Header is initialized }
  Values := AllocateSmartValueArray(Header);

  { Stream processing with SmartValueArray }
  ProcessedCount := 0;
  while not EOF(F) do
  begin
    ReadLn(F, Line);
    if TrimString(Line) <> '' then
    begin
      SplitPipe(Line, Values, ValueCount, Header);
      for I := ValueCount + 1 to Header.FieldCount do
        if not DBFFieldSetStr(Values, Header, I, '') then ;
      
      if not DBFFileAppendRow(Dbf, Values, Header.FieldCount) then ;
      Inc(ProcessedCount);
      
      if (ProcessedCount mod 1000) = 0 then
        WriteLn('Processed ', ProcessedCount, ' records...');
    end;
  end;
  
  Close(F);
  if not DBFFileClose(Dbf) then ;
  if not DBFFileDispose(Dbf) then ;
  if not FreeSmartValueArray(Values) then ;
  
  WriteLn('Smart import completed: ', ProcessedCount, ' records');
  WriteLn('Memory used: SmartValueArray (optimal storage)');
end;

{ Field-by-field streaming import - minimal memory usage }
procedure ImportDBFFromTextFieldByField(FileName: string);
var
  F: Text;
  Line1, Line2, Line: string;
  FieldCount, I: Integer;
  Header: TDBFHeader;
  FieldType: Char;
  Len, Dec: Byte;
  Dbf: PDBFFile;
  TextFileName, DBFFileName: string;
  ProcessedCount: LongInt;
  SmartValues: Pointer;
  Ok: Boolean;

begin
  TextFileName := FileName + '.TXT';
  DBFFileName := FileName + '.DBF';
  WriteLn('Field-by-field import from ' + TextFileName + ' to ' + DBFFileName);
  
  Assign(F, TextFileName);
  Reset(F);
  if EOF(F) then
  begin
    Close(F);
    Exit;
  end;
  
  { Read header lines }
  ReadLn(F, Line1);
  if EOF(F) then
  begin
    Close(F);
    Exit;
  end;
  ReadLn(F, Line2);

  { Count actual fields needed }
  FieldCount := CountPipeFields(Line1);
  if FieldCount > DBFMaxFields then
    FieldCount := DBFMaxFields;
    
  WriteLn('Detected ', FieldCount, ' fields - allocating minimal memory');
  
  { Parse field definitions }
  FillChar(Header, SizeOf(Header), 0);
  Header.FieldCount := FieldCount;
  
  for I := 0 to FieldCount - 1 do
  begin
    Header.Fields[I + 1].Name := ExtractPipeField(Line1, I + 1);
    if Length(Header.Fields[I + 1].Name) > 11 then
      Header.Fields[I + 1].Name := Copy(Header.Fields[I + 1].Name, 1, 11);
      
    FieldType := 'C';
    Len := 1;
    Dec := 0;
    
    if ParseFieldSpec(ExtractPipeField(Line2, I + 1), FieldType, Len, Dec) then
    begin
      Header.Fields[I + 1].FieldType := FieldType;
      Header.Fields[I + 1].Length := Len;
      Header.Fields[I + 1].Decimals := Dec;
    end
    else
    begin
      Header.Fields[I + 1].FieldType := 'C';
      Header.Fields[I + 1].Length := 1;
      Header.Fields[I + 1].Decimals := 0;
    end;
  end;

  Dbf := nil;
  Ok := DBFFileCreate(Dbf, FileName, Header);
  if not Ok then
  begin
    Close(F);
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;
  
  { Allocate SmartValueArray for DBF operations }
  SmartValues := AllocateSmartValueArray(Header);
  
  { Stream processing with minimal memory }
  ProcessedCount := 0;
  while not EOF(F) do
  begin
    ReadLn(F, Line);
    if TrimString(Line) <> '' then
    begin
      { Extract only the fields we need }
      for I := 1 to Header.FieldCount do
        if not DBFFieldSetStr(SmartValues, Header, I, ExtractPipeField(Line, I)) then ;
        
      if not DBFFileAppendRow(Dbf, SmartValues, Header.FieldCount) then ;
      Inc(ProcessedCount);
      
      if (ProcessedCount mod 1000) = 0 then
        WriteLn('Processed ', ProcessedCount, ' records...');
    end;
  end;
  
  Close(F);
  if not DBFFileClose(Dbf) then ;
  if not DBFFileDispose(Dbf) then ;
  
  { Clean up dynamic memory }
  if not FreeSmartValueArray(SmartValues) then ;
  
  WriteLn('Field-by-field import completed: ', ProcessedCount, ' records');
  WriteLn('Memory used: SmartValueArray (optimal storage)');
end;

procedure ImportDBFFromTextStreaming(FileName: string);
var
  F: Text;
  Line1, Line2, Line: string;
  Header: TDBFHeader;
  FieldType: Char;
  Len, Dec: Byte;
  I: Integer;
  Dbf: PDBFFile;
  Values: Pointer;  { SmartValueArray for single row }
  TextFileName, DBFFileName: string;
  ProcessedCount: LongInt;
  ValueCount: Integer;
  Ok: Boolean;
begin
  TextFileName := FileName + '.TXT';
  DBFFileName := FileName + '.DBF';
  WriteLn('Streaming import from ' + TextFileName + ' to ' + DBFFileName);
  
  Assign(F, TextFileName);
  Reset(F);
  if EOF(F) then
  begin
    Close(F);
    Exit;
  end;
  
  { Read header lines }
  ReadLn(F, Line1);
  if EOF(F) then
  begin
    Close(F);
    Exit;
  end;
  ReadLn(F, Line2);

  { Parse field definitions directly without large arrays }
  FillChar(Header, SizeOf(Header), 0);
  Header.FieldCount := CountPipeFields(Line1);
  if Header.FieldCount > DBFMaxFields then
    Header.FieldCount := DBFMaxFields;
    
  for I := 1 to Header.FieldCount do
  begin
    Header.Fields[I].Name := ExtractPipeField(Line1, I);
    if Length(Header.Fields[I].Name) > 11 then
      Header.Fields[I].Name := Copy(Header.Fields[I].Name, 1, 11);
    FieldType := 'C';
    Len := 1;
    Dec := 0;
    if ParseFieldSpec(ExtractPipeField(Line2, I), FieldType, Len, Dec) then
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
  Ok := DBFFileCreate(Dbf, FileName, Header);
  if not Ok then
  begin
    Close(F);
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;
  
  { Allocate SmartValueArray for values }
  Values := AllocateSmartValueArray(Header);
  
  { Stream processing - minimal memory usage }
  ProcessedCount := 0;
  while not EOF(F) do
  begin
    ReadLn(F, Line);
    if TrimString(Line) <> '' then
    begin
      SplitPipe(Line, Values, ValueCount, Header);
      for I := ValueCount + 1 to Header.FieldCount do
        if not DBFFieldSetStr(Values, Header, I, '') then ;
      if not DBFFileAppendRow(Dbf, Values, Header.FieldCount) then ;
      Inc(ProcessedCount);
      
      { Progress indicator for large files }
      if (ProcessedCount mod 1000) = 0 then
        WriteLn('Processed ', ProcessedCount, ' records...');
    end;
  end;
  Close(F);
  if not DBFFileClose(Dbf) then ;
  if not DBFFileDispose(Dbf) then ;
  
  { Clean up }
  if not FreeSmartValueArray(Values) then ;
  WriteLn('Streaming import completed: ', ProcessedCount, ' records');
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


procedure ImportDBFMemosFromText(FileName: string);
begin
  if not IsValid83FileName(FileName) then
  begin
    WriteLn('ERROR: invalid 8.3 filename: ', FileName);
    Exit;
  end;
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
  Header: TDBFHeader;
  RowIndex: LongInt;
  FieldIdx: Integer;
  MemoType: LongInt;
  BlockNum: LongInt;
  HasBlock: Boolean;
  I: Integer;
  ContentStart: LongInt;
  ContentLen: LongInt;
  StartBlock: LongInt;
  RowBuf: Pointer;
  Values: Pointer;
  BlockStr: string[20];
  DoneLine: Boolean;
  TextFileName, DBFFileName, MemoFileName: string;
  Ok: Boolean;
  Memo: PDBFMemo;
  MemoOk: Boolean;
begin
  if not IsValid83FileName(FileName) then
  begin
    WriteLn('ERROR: invalid 8.3 filename: ', FileName);
    Exit;
  end;
  TextFileName := FileName + '.MEM';
  DBFFileName := FileName + '.DBF';
  MemoFileName := FileName;
  
  Assign(F, TextFileName);
  Reset(F, 1);
  Dbf := nil;
  Ok := DBFFileOpen(Dbf, FileName);
  if not Ok then
  begin
    Close(F);
    Exit;
  end;
  
  if not DBFFileGetHeader(Dbf, Header) then
  begin
    Close(F);
    if not DBFFileClose(Dbf) then ;
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;

  Memo := nil;
  MemoOk := DBFMemoOpen(Memo, MemoFileName);
  if not MemoOk then
    MemoOk := DBFMemoCreate(Memo, MemoFileName);
  if not MemoOk then
  begin
    Close(F);
    if not DBFFileClose(Dbf) then ;
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;

  Buf := nil;
  BufCap := 0;
  GetMem(RowBuf, Header.RecordSize);
  Values := AllocateSmartValueArray(Header);
  
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
         (FieldIdx <= Header.FieldCount) and
         (UpCase(Header.Fields[FieldIdx].FieldType) = 'M') then
      begin
        if DebugMemoImport then
          WriteLn('MEMO DBG: row=', RowIndex, ' field=', FieldIdx,
                  ' type=', MemoType, ' block=', BlockNum,
                  ' hasblock=', Ord(HasBlock), ' len=', ContentLen);
        if PreserveBlocks and HasBlock then
        begin
          StartBlock := BlockNum;
          if not WriteMemoFromBufferAtBlockM(Memo, MemoType, Buf, ContentStart, ContentLen, StartBlock) then ;
        end
        else
          if not WriteMemoFromBufferM(Memo, MemoType, Buf, ContentStart, ContentLen, StartBlock) then ;
        if not DBFFileSeekToRow(Dbf, RowIndex) then ;
        if not DBFFileReadRow(Dbf, RowBuf, Header.RecordSize) then ;
        Str(StartBlock, BlockStr);
        if DebugMemoImport then
          WriteLn('MEMO DBG: set row=', RowIndex, ' field=', FieldIdx, ' blockstr=', BlockStr);
        
        { Get all field values }
        for I := 1 to Header.FieldCount do
          if not DBFFieldSetStr(Values, Header, I, DBFFieldGetStr(RowBuf, Header, I)) then ;
          
          { Update the memo field with new block number }
          if not DBFFieldSetStr(Values, Header, FieldIdx, BlockStr) then ;
          
          { Re-seek to target row before writing since read advanced the cursor }
          if not DBFFileSeekToRow(Dbf, RowIndex) then ;
          if not DBFFileWriteRow(Dbf, Values, Header.FieldCount) then ;
        end;
      end;
    end;

  if Buf <> nil then
    FreeMem(Buf, BufCap);
  if RowBuf <> nil then
    FreeMem(RowBuf, Header.RecordSize);
  if Values <> nil then
    if not FreeSmartValueArray(Values) then ;
  Close(F);
  if not DBFMemoClose(Memo) then ;
  if not DBFMemoDispose(Memo) then ;
  if not DBFFileClose(Dbf) then ;
  if not DBFFileDispose(Dbf) then ;
end;


procedure ExportDBFMemosToText(FileName: string);
var
  Dbf: PDBFFile;
  Header: TDBFHeader;
  F: Text;
  Buf: Pointer;
  RowIndex, RowCount: LongInt;
  FieldIdx: Integer;
  MemoBlock: LongInt;
  MemoType: LongInt;
  MemoLen: LongInt;
  DBFFileName, MemoFileName, TextFileName : string;
  ExportRowIndex : LongInt;
  FieldValue: string;
  Ok: Boolean;
  Memo: PDBFMemo;
  MemoOk: Boolean;
begin
  if not IsValid83FileName(FileName) then
  begin
    WriteLn('ERROR: invalid 8.3 filename: ', FileName);
    Exit;
  end;
  DBFFileName := FileName + '.DBF';
  MemoFileName := FileName;
  TextFileName := FileName + '.TXT';
  WriteLn('DBG: ExportDBFMemosToText - DBF=', DBFFileName, ' MEMO=', MemoFileName, '.DBT TXT=', TextFileName);

  Dbf := nil;
  WriteLn('DBG: Opening DBF file: ', FileName);
  Ok := DBFFileOpen(Dbf, FileName);
  WriteLn('DBG: DBF opened, Dbf=', LongInt(Dbf));
  if not Ok then Exit;
  
  if not DBFFileGetHeader(Dbf, Header) then
  begin
    if not DBFFileClose(Dbf) then ;
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;

  Memo := nil;
  MemoOk := DBFMemoOpen(Memo, MemoFileName);
  if not MemoOk then
  begin
    if not DBFFileClose(Dbf) then ;
    if not DBFFileDispose(Dbf) then ;
    Exit;
  end;

  Assign(F, TextFileName);
  Rewrite(F);
  WriteLn('DBG: Created export file: ', TextFileName);
  
  { Write header }
  WriteLn(F, 'ID|NAME|NOTES');
  WriteLn('DBG: Wrote header to export file');

  GetMem(Buf, Header.RecordSize);
  
  RowCount := DBFFileGetActualRowCount(Dbf);
  if not DBFFileSeekToFirstRow(Dbf) then ;
  ExportRowIndex := 0;
  
  for RowIndex := 0 to RowCount - 1 do
  begin
    if not DBFFileReadRow(Dbf, Buf, Header.RecordSize) then ;
    
    { Check if row is not deleted }
    if PByteArray(Buf)^[0] <> Ord('*') then
    begin
      for FieldIdx := 1 to Header.FieldCount do
      begin
        if UpCase(Header.Fields[FieldIdx].FieldType) = 'M' then
        begin
          FieldValue := DBFFieldGetStr(Buf, Header, FieldIdx);
          MemoBlock := ParseInt(TrimString(FieldValue));
          WriteLn('DBG: Found memo field ', FieldIdx, ' with block ', MemoBlock, ' value=[', FieldValue, ']');
          
          if MemoBlock > 0 then
          begin
            WriteLn('DBG: Getting memo info for block ', MemoBlock);
            WriteLn('DBG: Memo file: ', MemoFileName, '.DBT');
            if FileExists(MemoFileName + '.DBT') then
              WriteLn('DBG: Memo file exists before getinfo')
            else
              WriteLn('DBG: Memo file does NOT exist before getinfo');
              
            if DBFMemoGetInfoM(Memo, MemoBlock, MemoType, MemoLen) then
            begin
              WriteLn('DBG: Memo info - Type=', MemoType, ' Len=', MemoLen);
              Write(F, ExportRowIndex, '|', FieldIdx, '|', MemoType, '|', MemoBlock, '|');
              if not WriteMemoChunksM(Memo, MemoBlock, MemoLen, MemoType, F) then ;
              WriteLn(F);
            end
            else
              WriteLn('DBG: Failed to get memo info for block ', MemoBlock);
          end
          else
            WriteLn('DBG: Memo block is 0 or negative, skipping');
        end;
      end;
      Inc(ExportRowIndex);
    end;
  end;

  { Clean up allocated memory }
  if Buf <> nil then FreeMem(Buf, Header.RecordSize);
  
  Close(F);
  if not DBFMemoClose(Memo) then ;
  if not DBFMemoDispose(Memo) then ;
  if not DBFFileClose(Dbf) then ;
  if not DBFFileDispose(Dbf) then ;
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

end.
