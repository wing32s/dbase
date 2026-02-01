program TESTTEXT;

uses Assert, DBFUTIL, DBF, DBFMEMO, DBFTEXT;

{ Initialize a test DBF header with standard fields }
procedure InitTestHeader(var Header: TDBFHeader);
var
  I: Integer;
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.FieldCount := 5;
  Header.Version := $04;  { Explicitly set version }
  Header.Year := 124;      { 2024 - 1900 }
  Header.Month := 1;
  Header.Day := 27;
  
  Header.Fields[1].Name := 'NAME';
  Header.Fields[1].FieldType := 'C';
  Header.Fields[1].Length := 20;
  Header.Fields[1].Decimals := 0;
  
  Header.Fields[2].Name := 'AMOUNT';
  Header.Fields[2].FieldType := 'N';
  Header.Fields[2].Length := 10;
  Header.Fields[2].Decimals := 2;
  
  Header.Fields[3].Name := 'DATE';
  Header.Fields[3].FieldType := 'D';
  Header.Fields[3].Length := 8;
  Header.Fields[3].Decimals := 0;
  
  Header.Fields[4].Name := 'ACTIVE';
  Header.Fields[4].FieldType := 'L';
  Header.Fields[4].Length := 1;
  Header.Fields[4].Decimals := 0;
  
  Header.Fields[5].Name := 'NOTES';
  Header.Fields[5].FieldType := 'M';
  Header.Fields[5].Length := 10;
  Header.Fields[5].Decimals := 0;
end;

procedure TestExportDBFToText;
var
  TestHeader: TDBFHeader;
  TestDbf: PDBFFile;
  SmartValues: Pointer;
  TestFileName: string;
  TextFile: Text;
  Line: string;
  Result: Boolean;
begin
  BeginTest('ExportDBFToText');
  
  TestFileName := 'TESTEXP';
  InitTestHeader(TestHeader);
  
  { Create test DBF }
  TestDbf := nil;
  Result := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(Result, 'DBFFileCreate should succeed');
  SmartValues := AllocateSmartValueArray(TestHeader);
  
  { Add test data }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'John Doe'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '123.45'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '20240127'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, 'T'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, '0'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');
  
  { Add second record }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Jane Smith'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '678.90'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '20240128'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, 'F'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, '0'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');
  
  Result := FreeSmartValueArray(SmartValues); AssertTrue(Result, 'FreeSmartValueArray should succeed');
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');
  
  { Export to text }
  ExportDBFToText(TestFileName);
  
  { Verify text file exists and has correct content }
  Assign(TextFile, TestFileName + '.TXT');
  Reset(TextFile);
  
  { Check header line }
  ReadLn(TextFile, Line);
  AssertEqualsStr('NAME|AMOUNT|DATE|ACTIVE|NOTES', Line, 'Header line should match');
  
  { Check field spec line }
  ReadLn(TextFile, Line);
  AssertTrue(Pos('C(20)', Line) > 0, 'Should contain character field spec');
  AssertTrue(Pos('N(10,2)', Line) > 0, 'Should contain numeric field spec');
  AssertTrue(Pos('D(8)', Line) > 0, 'Should contain date field spec');
  AssertTrue(Pos('L(1)', Line) > 0, 'Should contain logical field spec');
  AssertTrue(Pos('M(10)', Line) > 0, 'Should contain memo field spec');
  
  { Check data lines }
  ReadLn(TextFile, Line);
  AssertTrue(Pos('John Doe', Line) > 0, 'Should contain first record');
  
  ReadLn(TextFile, Line);
  AssertTrue(Pos('Jane Smith', Line) > 0, 'Should contain second record');
  
  Close(TextFile);
  
  { Cleanup }
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.DBF');
  EndTest;
end;

procedure TestImportDBFFromText;
var
  TestDbf: PDBFFile;
  TestFileName: string;
  TextFile: Text;
  Header: TDBFHeader;
  RowBuffer: Pointer;
  Result: Boolean;
begin
  BeginTest('ImportDBFFromText');

  TestFileName := 'TESTIMP';

  { Create test text file }
  Assign(TextFile, TestFileName + '.TXT');
  Rewrite(TextFile);
  WriteLn(TextFile, 'NAME|AMOUNT|DATE|ACTIVE|NOTES');
  WriteLn(TextFile, 'C(20)|N(10,2)|D(8)|L(1)|M(10)');
  WriteLn(TextFile, 'Test User|999.99|20240129|T|Test memo');
  WriteLn(TextFile, 'Another User|111.11|20240130|F|Another memo');
  Close(TextFile);

  { Import from text }
  ImportDBFFromText(TestFileName);

  { Verify imported DBF }
  TestDbf := nil;
  Result := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(Result, 'DBFFileOpen should succeed');
  AssertNotNil(TestDbf, 'DBF should be created');

  Result := DBFFileGetHeader(TestDbf, Header);
  AssertTrue(Result, 'DBFFileGetHeader should succeed');
  AssertEqualsInt(5, Header.FieldCount, 'Should have 5 fields');
  AssertEqualsStr('NAME', Header.Fields[1].Name, 'First field should be NAME');
  AssertEqualsStr('C', Header.Fields[1].FieldType, 'First field should be character');

  { Verify first record }
  GetMem(RowBuffer, Header.RecordSize);
  AssertTrue(DBFFileSeekToFirstRow(TestDbf), 'DBFFileSeekToFirstRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, RowBuffer, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('Test User', TrimString(DBFFieldGetStr(RowBuffer, Header, 1)), 'First name should match');
  AssertEqualsStr('999.99', TrimString(DBFFieldGetStr(RowBuffer, Header, 2)), 'First amount should match');
  AssertEqualsStr('20240129', TrimString(DBFFieldGetStr(RowBuffer, Header, 3)), 'First date should match');
  AssertEqualsStr('T', TrimString(DBFFieldGetStr(RowBuffer, Header, 4)), 'First active should match');

  { Verify second record }
  AssertTrue(DBFFileReadRow(TestDbf, RowBuffer, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('Another User', TrimString(DBFFieldGetStr(RowBuffer, Header, 1)), 'Second name should match');
  AssertEqualsStr('111.11', TrimString(DBFFieldGetStr(RowBuffer, Header, 2)), 'Second amount should match');
  AssertEqualsStr('20240130', TrimString(DBFFieldGetStr(RowBuffer, Header, 3)), 'Second date should match');
  AssertEqualsStr('F', TrimString(DBFFieldGetStr(RowBuffer, Header, 4)), 'Second active should match');

  FreeMem(RowBuffer, Header.RecordSize);
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');

  { Cleanup }
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.DBF');
  EndTest;
end;

procedure TestImportDBFFromTextStreaming;
var
  TestDbf: PDBFFile;
  TestFileName: string;
  TextFile: Text;
  Header: TDBFHeader;
  SmartValues: Pointer;
  I: Integer;
  Result: Boolean;
begin
  BeginTest('ImportDBFFromTextStreaming');
  
  TestFileName := 'TESTSTR';
  
  { Create larger test text file to test streaming }
  Assign(TextFile, TestFileName + '.TXT');
  Rewrite(TextFile);
  WriteLn(TextFile, 'ID|NAME|VALUE|DATE');
  WriteLn(TextFile, 'N(5)|C(15)|N(8,2)|D(8)');
  
  { Add 100 records to test streaming efficiency }
  MemoryReport('Before creating large text file');
  for I := 1 to 100 do
  begin
    WriteLn(TextFile, IntToStrLocal(I), '|Record', IntToStrLocal(I), '|', 
            FloatToStrLocal(I * 1.5), '|202401', IntToStrLocal(I mod 28 + 1));
  end;
  Close(TextFile);
  MemoryReport('After creating large text file');
  
  { Import using streaming method }
  MemoryReport('Before streaming import');
  ImportDBFFromTextStreaming(TestFileName);
  MemoryReport('After streaming import');
  
  { Verify imported DBF }
  TestDbf := nil;
  Result := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(Result, 'DBFFileOpen should succeed');
  AssertNotNil(TestDbf, 'DBF should be created');

  Result := DBFFileGetHeader(TestDbf, Header);
  AssertTrue(Result, 'DBFFileGetHeader should succeed');
  AssertEqualsInt(4, Header.FieldCount, 'Should have 4 fields');
  
  { Verify record count }
  AssertEqualsInt(100, DBFFileGetActualRowCount(TestDbf), 'Should have 100 records');
  
  { Verify first and last records }
  GetMem(SmartValues, Header.RecordSize);

  { First record }
  AssertTrue(DBFFileSeekToFirstRow(TestDbf), 'DBFFileSeekToFirstRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('1', TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 'First ID should be 1');
  AssertEqualsStr('Record1', 
    TrimString(DBFFieldGetStr(SmartValues, Header, 2)), 'First name should be Record1');

  { Last record (seek to end) }
  AssertTrue(DBFFileSeekToRow(TestDbf, 99), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('100', 
    TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 'Last ID should be 100');
  AssertEqualsStr('Record100', 
    TrimString(DBFFieldGetStr(SmartValues, Header, 2)), 'Last name should be Record100');

  FreeMem(SmartValues, Header.RecordSize);
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');
  
  { Cleanup }
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.DBF');
  EndTest;
end;

procedure TestImportDBFFromTextFieldByField;
var
  TestDbf: PDBFFile;
  TestFileName: string;
  TextFile: Text;
  Header: TDBFHeader;
  SmartValues: Pointer;
  I: Integer;
  Result: Boolean;
begin
  BeginTest('ImportDBFFromTextFieldByField');
  
  TestFileName := 'TESTFLD';
  
  { Create test text file with varied data }
  Assign(TextFile, TestFileName + '.TXT');
  Rewrite(TextFile);
  WriteLn(TextFile, 'CODE|DESCRIPTION|PRICE|STOCK|ACTIVE');
  WriteLn(TextFile, 'C(8)|C(25)|N(8,2)|N(5)|L(1)');
  WriteLn(TextFile, 'A001|Widget A|19.99|100|T');
  WriteLn(TextFile, 'B002|Widget B|29.50|50|T');
  WriteLn(TextFile, 'C003|Widget C|0.99|1000|F');
  WriteLn(TextFile, 'D004|Widget D|199.99|5|T');
  Close(TextFile);
  
  { Import using field-by-field method }
  ImportDBFFromTextFieldByField(TestFileName);
  
  { Verify imported DBF }
  TestDbf := nil;
  Result := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(Result, 'DBFFileOpen should succeed');
  AssertNotNil(TestDbf, 'DBF should be created');

  Result := DBFFileGetHeader(TestDbf, Header);
  AssertTrue(Result, 'DBFFileGetHeader should succeed');
  AssertEqualsInt(5, Header.FieldCount, 'Should have 5 fields');
  AssertEqualsStr('CODE', Header.Fields[1].Name, 'First field should be CODE');
  AssertEqualsStr('DESCRIPTION', Header.Fields[2].Name, 
    'Second field should be DESCRIPTION');
  
  { Verify all records }
  GetMem(SmartValues, Header.RecordSize);
  AssertTrue(DBFFileSeekToFirstRow(TestDbf), 'DBFFileSeekToFirstRow should succeed');

  { Record 1 }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('A001', TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 
    'First code should be A001');
  AssertEqualsStr('Widget A', TrimString(DBFFieldGetStr(SmartValues, Header, 2)), 
    'First description should be Widget A');
  AssertEqualsStr('19.99', TrimString(DBFFieldGetStr(SmartValues, Header, 3)), 
    'First price should be 19.99');
  AssertEqualsStr('100', TrimString(DBFFieldGetStr(SmartValues, Header, 4)), 
    'First stock should be 100');
  AssertEqualsStr('T', TrimString(DBFFieldGetStr(SmartValues, Header, 5)), 
    'First active should be T');

  { Record 2 }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('B002', TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 
    'Second code should be B002');
  AssertEqualsStr('Widget B', TrimString(DBFFieldGetStr(SmartValues, Header, 2)), 
    'Second description should be Widget B');

  { Record 3 (inactive) }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('C003', TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 
    'Third code should be C003');
  AssertEqualsStr('F', TrimString(DBFFieldGetStr(SmartValues, Header, 5)), 
    'Third active should be F');

  { Record 4 (high price) }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('D004', TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 
    'Fourth code should be D004');
  AssertEqualsStr('199.99', TrimString(DBFFieldGetStr(SmartValues, Header, 3)), 
    'Fourth price should be 199.99');

  FreeMem(SmartValues, Header.RecordSize);
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');
  
  { Cleanup }
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.DBF');
  EndTest;
end;

procedure TestImportDBFFromTextPacked;
var
  TestDbf: PDBFFile;
  TestFileName: string;
  TextFile: Text;
  Header: TDBFHeader;
  SmartValues: Pointer;
  I: Integer;
  Result: Boolean;
begin
  BeginTest('ImportDBFFromTextPacked');
  
  TestFileName := 'TESTPAK';
  
  { Create test text file with many records to test packed efficiency }
  Assign(TextFile, TestFileName + '.TXT');
  Rewrite(TextFile);
  WriteLn(TextFile, 'ID|FIRST_NAME|LAST_NAME|EMAIL|PHONE|BIRTH_DATE');
  WriteLn(TextFile, 'N(6)|C(15)|C(20)|C(30)|C(15)|D(8)');
  
  { Add 50 records to test packed memory efficiency }
  MemoryReport('Before creating packed test data');
  for I := 1 to 50 do
  begin
    WriteLn(TextFile, IntToStrLocal(I), '|John', IntToStrLocal(I), '|Doe', IntToStrLocal(I), 
            '|john', IntToStrLocal(I), '@example.com|555-000', IntToStrLocal(I), 
            '|1980', IntToStrLocal(I mod 12 + 1), IntToStrLocal(I mod 28 + 1));
  end;
  Close(TextFile);
  MemoryReport('After creating packed test data');
  
  { Import using packed method }
  MemoryReport('Before packed import');
  ImportDBFFromTextPacked(TestFileName);
  MemoryReport('After packed import');
  
  { Verify imported DBF }
  TestDbf := nil;
  Result := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(Result, 'DBFFileOpen should succeed');
  AssertNotNil(TestDbf, 'DBF should be created');

  Result := DBFFileGetHeader(TestDbf, Header);
  AssertTrue(Result, 'DBFFileGetHeader should succeed');
  AssertEqualsInt(6, Header.FieldCount, 'Should have 6 fields');
  AssertEqualsStr('ID', Header.Fields[1].Name, 'First field should be ID');
  AssertEqualsStr('FIRST_NAME', Header.Fields[2].Name, 
    'Second field should be FIRST_NAME');
  
  { Verify record count }
  AssertEqualsInt(50, DBFFileGetActualRowCount(TestDbf), 'Should have 50 records');
  
  { Verify sample records }
  MemoryReport('Before row buffer allocation');
  GetMem(SmartValues, Header.RecordSize);
  MemoryReport('After row buffer allocation');

  { First record }
  MemoryReport('Before reading first record');
  AssertTrue(DBFFileSeekToFirstRow(TestDbf), 'DBFFileSeekToFirstRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  MemoryReport('After reading first record');
  AssertEqualsStr('1', TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 
    'First ID should be 1');
  AssertEqualsStr('John1', TrimString(DBFFieldGetStr(SmartValues, Header, 2)), 
    'First name should be John1');
  AssertEqualsStr('Doe1', TrimString(DBFFieldGetStr(SmartValues, Header, 3)), 
    'Last name should be Doe1');
  AssertEqualsStr('john1@example.com', TrimString(DBFFieldGetStr(SmartValues, Header, 4)), 
    'Email should match');
  AssertEqualsStr('555-0001', TrimString(DBFFieldGetStr(SmartValues, Header, 5)), 
    'Phone should match');

  { Record 25 }
  MemoryReport('Before reading middle record');
  AssertTrue(DBFFileSeekToRow(TestDbf, 24), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  MemoryReport('After reading middle record');
  AssertEqualsStr('25', TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 
    'ID 25 should be 25');
  AssertEqualsStr('John25', TrimString(DBFFieldGetStr(SmartValues, Header, 2)), 
    'Name 25 should be John25');

  { Last record }
  MemoryReport('Before reading last record');
  AssertTrue(DBFFileSeekToRow(TestDbf, 49), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  MemoryReport('After reading last record');
  AssertEqualsStr('50', TrimString(DBFFieldGetStr(SmartValues, Header, 1)), 
    'Last ID should be 50');
  AssertEqualsStr('John50', TrimString(DBFFieldGetStr(SmartValues, Header, 2)), 
    'Last name should be John50');

  MemoryReport('Before row buffer cleanup');
  FreeMem(SmartValues, Header.RecordSize);
  MemoryReport('After row buffer cleanup');
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');
  
  { Cleanup }
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.DBF');
  EndTest;
end;

procedure TestExportDBFMemosToText;
var
  TestHeader: TDBFHeader;
  TestDbf: PDBFFile;
  SmartValues: Pointer;
  TestFileName: string;
  TextFile: Text;
  Line: string;
  StartBlock: LongInt;
  Result: Boolean;
  MemoHandle: PDBFMemo;
begin
  BeginTest('ExportDBFMemosToText');
  
  TestFileName := 'TMEMEXP';

  { Clean up any leftover files from previous runs }
  EraseFile(TestFileName + '.DBF');
  EraseFile(TestFileName + '.DBT');
  EraseFile(TestFileName + '.TXT');

  { Create test DBF with memo fields }
  FillChar(TestHeader, SizeOf(TestHeader), 0);
  TestHeader.FieldCount := 3;
  TestHeader.Version := $05;  { dBase V with memo support }
  TestHeader.Year := 124;      { 2024 - 1900 }
  TestHeader.Month := 1;
  TestHeader.Day := 27;
  TestHeader.Fields[1].Name := 'ID';
  TestHeader.Fields[1].FieldType := 'N';
  TestHeader.Fields[1].Length := 5;
  TestHeader.Fields[1].Decimals := 0;
  
  TestHeader.Fields[2].Name := 'NAME';
  TestHeader.Fields[2].FieldType := 'C';
  TestHeader.Fields[2].Length := 20;
  TestHeader.Fields[2].Decimals := 0;
  
  TestHeader.Fields[3].Name := 'NOTES';
  TestHeader.Fields[3].FieldType := 'M';
  TestHeader.Fields[3].Length := 10;
  TestHeader.Fields[3].Decimals := 0;
  
  { Create DBF }
  MemoryReport('Before DBF creation with memo fields');
  TestDbf := nil;
  WriteLn('DBG: Before DBFFileCreate, TestDbf=', LongInt(TestDbf));
  Result := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  WriteLn('DBG: After DBFFileCreate, TestDbf=', LongInt(TestDbf));
  MemoryReport('After DBF creation');
  AssertTrue(Result, 'DBF creation should succeed');
  WriteLn('DBG: DBF created successfully, closing...');
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');
  TestDbf := nil;
  WriteLn('DBG: DBF closed and disposed');
  
  MemoryReport('Before SmartValueArray allocation for memos');
  SmartValues := AllocateSmartValueArray(TestHeader);
  MemoryReport('After SmartValueArray allocation');
  
  { Reopen DBF for adding records }
  TestDbf := nil;
  Result := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(Result, 'DBFFileOpen should succeed');
  AssertNotNil(TestDbf, 'DBF should reopen for records');
  
  MemoHandle := nil;
  Result := DBFMemoOpen(MemoHandle, TestFileName);
  if not Result then
    Result := DBFMemoCreate(MemoHandle, TestFileName);
  AssertTrue(Result, 'DBFMemoOpen/Create should succeed');
  AssertNotNil(MemoHandle, 'Memo handle should be valid');
  
  { Add records with real memo content }
  MemoryReport('Before adding memo records');
  
  { First record - write memo to DBT file }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, '1'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, 'John Doe'), 'DBFFieldSetStr should succeed');
  WriteLn('DBG: Writing memo for record 1');
  AssertTrue(DBFMemoWriteM(MemoHandle, 1, 
    'This is a test memo note for John Doe.', StartBlock), 
    'DBFMemoWrite should succeed');
  WriteLn('DBG: Memo written to block ', StartBlock);
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, IntToStrLocal(StartBlock)), 'DBFFieldSetStr should succeed');
  WriteLn('DBG: Set memo field to block ', StartBlock);
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 3), 'DBFFileAppendRow should succeed');
  
  { Second record - write memo to DBT file }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, '2'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, 'Jane Smith'), 'DBFFieldSetStr should succeed');
  WriteLn('DBG: Writing memo for record 2');
  AssertTrue(DBFMemoWriteM(MemoHandle, 2, 'Another memo note for Jane Smith with multiple lines of text.'
    + #13#10 + 'This is the second line of the memo.', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('DBG: Memo written to block ', StartBlock);
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, IntToStrLocal(StartBlock)), 'DBFFieldSetStr should succeed');
  WriteLn('DBG: Set memo field to block ', StartBlock);
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 3), 'DBFFileAppendRow should succeed');
  
  { Third record - write memo to DBT file }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, '3'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, 'Bob Wilson'), 'DBFFieldSetStr should succeed');
  WriteLn('DBG: Writing memo for record 3');
  AssertTrue(DBFMemoWriteM(MemoHandle, 3, 'Third memo note with special characters: @#$%^&*()'
    + #13#10 + 'Unicode test: αβγδε', StartBlock), 'DBFMemoWrite should succeed');
  WriteLn('DBG: Memo written to block ', StartBlock);
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, IntToStrLocal(StartBlock)), 'DBFFieldSetStr should succeed');
  WriteLn('DBG: Set memo field to block ', StartBlock);
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 3), 'DBFFileAppendRow should succeed');
  MemoryReport('After adding memo records');
  
  { Check if memo file was created }
  WriteLn('DBG: Checking memo file existence: ', TestFileName + '.DBT');
  if FileExists(TestFileName + '.DBT') then
    WriteLn('DBG: Memo file exists')
  else
    WriteLn('DBG: Memo file does NOT exist');
  
  MemoryReport('Before SmartValueArray cleanup');
  Result := FreeSmartValueArray(SmartValues); AssertTrue(Result, 'FreeSmartValueArray should succeed');
  MemoryReport('After SmartValueArray cleanup');
  Result := DBFMemoClose(MemoHandle); AssertTrue(Result, 'DBFMemoClose should succeed');
  Result := DBFMemoDispose(MemoHandle); AssertTrue(Result, 'DBFMemoDispose should succeed');
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');
  MemoryReport('After DBF cleanup');
  
  { Export memos to text }
  MemoryReport('Before memo export');
  ExportDBFMemosToText(TestFileName);
  MemoryReport('After memo export');
  
  { Verify memo text file exists and has correct content }
  Assign(TextFile, TestFileName + '.TXT');
  Reset(TextFile);
  
  { Check header line }
  ReadLn(TextFile, Line);
  AssertTrue(Pos('ID', Line) > 0, 'Should contain ID field');
  AssertTrue(Pos('NOTES', Line) > 0, 'Should contain NOTES field');

  { Check memo data lines - format: rowIndex|fieldIdx|memoType|block|content }
  ReadLn(TextFile, Line);
  AssertTrue(Pos('test memo note', Line) > 0, 'Should contain first memo content');

  ReadLn(TextFile, Line);
  if Pos('Another memo note', Line) > 0 then
    AssertTrue(True, 'Should contain second memo content')
  else
    AssertTrue(Pos('|2|', Line) > 0, 'Should contain second memo type 2 (base64)');

  ReadLn(TextFile, Line);
  AssertTrue(Pos('special characters', Line) > 0, 'Should contain third memo content');
  
  Close(TextFile);
  
  { Cleanup }
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.DBF');
  EraseFile(TestFileName + '.DBT');
  EndTest;
end;

procedure TestImportDBFMemosFromText;
var
  TestDbf: PDBFFile;
  TestFileName: string;
  TextFile: Text;
  Header: TDBFHeader;
  SmartValues: Pointer;
  Result: Boolean;
  MemoBlock: LongInt;
  MemoType: LongInt;
  MemoText: string;
  MemoHandle: PDBFMemo;
begin
  BeginTest('ImportDBFMemosFromText');

  TestFileName := 'TMEMIMP';

  { Clean up any leftover files }
  EraseFile(TestFileName + '.DBF');
  EraseFile(TestFileName + '.DBT');
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.MEM');

  { Step 1: Create regular .TXT for DBF import }
  Assign(TextFile, TestFileName + '.TXT');
  Rewrite(TextFile);
  WriteLn(TextFile, 'ID|NAME|NOTES');
  WriteLn(TextFile, 'N(5)|C(20)|M(10)');
  WriteLn(TextFile, '1|Alice Johnson|0');
  WriteLn(TextFile, '2|Bob Miller|0');
  WriteLn(TextFile, '3|Carol Davis|0');
  Close(TextFile);

  { Step 2: Import to create DBF with memo fields }
  ImportDBFFromText(TestFileName);

  { Step 3: Create .MEM file with memo content }
  { Format: rowIndex|fieldIdx|memoType|memoContent }
  Assign(TextFile, TestFileName + '.MEM');
  Rewrite(TextFile);
  WriteLn(TextFile, '0|3|1|Alice memo note with important information.');
  WriteLn(TextFile, '1|3|1|Bob memo contains technical details.');
  WriteLn(TextFile, '2|3|1|Carol memo has project status updates.');
  Close(TextFile);

  { Step 4: Import memos into existing DBF }
  ImportDBFMemosFromText(TestFileName);

  { Verify imported DBF }
  TestDbf := nil;
  Result := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(Result, 'DBFFileOpen should succeed');
  AssertNotNil(TestDbf, 'DBF should be created');
  MemoHandle := nil;
  Result := DBFMemoOpen(MemoHandle, TestFileName);
  AssertTrue(Result, 'DBFMemoOpen should succeed');
  AssertNotNil(MemoHandle, 'Memo handle should be valid');

  Result := DBFFileGetHeader(TestDbf, Header);
  AssertTrue(Result, 'DBFFileGetHeader should succeed');
  AssertEqualsInt(3, Header.FieldCount, 'Should have 3 fields');
  AssertEqualsStr('NOTES', Header.Fields[3].Name, 'Third field should be NOTES');
  AssertEqualsStr('M', Header.Fields[3].FieldType, 'Third field should be memo type');

  { Verify regular fields }
  GetMem(SmartValues, Header.RecordSize);
  AssertTrue(DBFFileSeekToFirstRow(TestDbf), 'DBFFileSeekToFirstRow should succeed');

  { First record }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('1', TrimString(DBFFieldGetStr(SmartValues, Header, 1)),
    'First ID should be 1');
  AssertEqualsStr('Alice Johnson', TrimString(DBFFieldGetStr(SmartValues, Header, 2)),
    'First name should be Alice Johnson');
  { Verify memo block was written }
  MemoBlock := ParseInt(TrimString(DBFFieldGetStr(SmartValues, Header, 3)));
  AssertTrue(MemoBlock > 0, 'First record should have memo block');
  if MemoBlock > 0 then
  begin
    Result := DBFMemoReadSmallM(MemoHandle, MemoBlock, MemoType, MemoText);
    AssertTrue(Result, 'Should read first memo');
    AssertTrue(Pos('Alice memo', MemoText) > 0, 'First memo should contain Alice text');
  end;

  { Second record }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('2', TrimString(DBFFieldGetStr(SmartValues, Header, 1)),
    'Second ID should be 2');

  { Third record }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('3', TrimString(DBFFieldGetStr(SmartValues, Header, 1)),
    'Third ID should be 3');

  FreeMem(SmartValues, Header.RecordSize);
  Result := DBFMemoClose(MemoHandle); AssertTrue(Result, 'DBFMemoClose should succeed');
  Result := DBFMemoDispose(MemoHandle); AssertTrue(Result, 'DBFMemoDispose should succeed');
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');

  { Cleanup }
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.MEM');
  EraseFile(TestFileName + '.DBF');
  EraseFile(TestFileName + '.DBT');
  EndTest;
end;

procedure TestImportDBFMemosFromTextEx;
var
  TestDbf: PDBFFile;
  TestFileName: string;
  TextFile: Text;
  Header: TDBFHeader;
  SmartValues: Pointer;
  Result: Boolean;
  MemoBlock: LongInt;
  MemoType: LongInt;
  MemoText: string;
  MemoHandle: PDBFMemo;
begin
  BeginTest('ImportDBFMemosFromTextEx');

  TestFileName := 'TMEMEX';

  { Clean up any leftover files }
  EraseFile(TestFileName + '.DBF');
  EraseFile(TestFileName + '.DBT');
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.MEM');

  { Step 1: Create regular .TXT for DBF import }
  Assign(TextFile, TestFileName + '.TXT');
  Rewrite(TextFile);
  WriteLn(TextFile, 'ID|TITLE|DESCRIPTION|NOTES');
  WriteLn(TextFile, 'N(5)|C(30)|C(50)|M(10)');
  WriteLn(TextFile, '1|Project Alpha|Initial project setup|0');
  WriteLn(TextFile, '2|Project Beta|Development phase|0');
  WriteLn(TextFile, '3|Project Gamma|Testing and QA|0');
  Close(TextFile);

  { Step 2: Import to create DBF with memo fields }
  ImportDBFFromText(TestFileName);

  { Step 3: Create .MEM file with memo content }
  { Format: rowIndex|fieldIdx|memoType|memoContent }
  Assign(TextFile, TestFileName + '.MEM');
  Rewrite(TextFile);
  WriteLn(TextFile, '0|4|1|Detailed project documentation with technical specs.');
  WriteLn(TextFile, '1|4|1|Development progress report with milestones.');
  WriteLn(TextFile, '2|4|1|Testing procedures and quality assurance protocols.');
  Close(TextFile);

  { Step 4: Import memos with block preservation }
  ImportDBFMemosFromTextEx(TestFileName, True);

  { Verify imported DBF with memos }
  TestDbf := nil;
  Result := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(Result, 'DBFFileOpen should succeed');
  AssertNotNil(TestDbf, 'DBF should be created');
  MemoHandle := nil;
  Result := DBFMemoOpen(MemoHandle, TestFileName);
  AssertTrue(Result, 'DBFMemoOpen should succeed');
  AssertNotNil(MemoHandle, 'Memo handle should be valid');

  Result := DBFFileGetHeader(TestDbf, Header);
  AssertTrue(Result, 'DBFFileGetHeader should succeed');
  AssertEqualsInt(4, Header.FieldCount, 'Should have 4 fields');
  AssertEqualsStr('NOTES', Header.Fields[4].Name, 'Fourth field should be NOTES');
  AssertEqualsStr('M', Header.Fields[4].FieldType, 'Fourth field should be memo type');

  { Verify records }
  GetMem(SmartValues, Header.RecordSize);
  AssertTrue(DBFFileSeekToFirstRow(TestDbf), 'DBFFileSeekToFirstRow should succeed');

  { First record - Project Alpha }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('1', TrimString(DBFFieldGetStr(SmartValues, Header, 1)),
    'First ID should be 1');
  AssertEqualsStr('Project Alpha', TrimString(DBFFieldGetStr(SmartValues, Header, 2)),
    'First title should be Project Alpha');
  { Verify memo block was written }
  MemoBlock := ParseInt(TrimString(DBFFieldGetStr(SmartValues, Header, 4)));
  AssertTrue(MemoBlock > 0, 'First record should have memo block');
  if MemoBlock > 0 then
  begin
    Result := DBFMemoReadSmallM(MemoHandle, MemoBlock, MemoType, MemoText);
    AssertTrue(Result, 'Should read first memo');
    AssertTrue(Pos('technical specs', MemoText) > 0, 'First memo should contain specs text');
  end;

  { Second record - Project Beta }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('2', TrimString(DBFFieldGetStr(SmartValues, Header, 1)),
    'Second ID should be 2');

  { Third record - Project Gamma }
  AssertTrue(DBFFileReadRow(TestDbf, SmartValues, Header.RecordSize), 'DBFFileReadRow should succeed');
  AssertEqualsStr('3', TrimString(DBFFieldGetStr(SmartValues, Header, 1)),
    'Third ID should be 3');

  FreeMem(SmartValues, Header.RecordSize);
  Result := DBFMemoClose(MemoHandle); AssertTrue(Result, 'DBFMemoClose should succeed');
  Result := DBFMemoDispose(MemoHandle); AssertTrue(Result, 'DBFMemoDispose should succeed');
  Result := DBFFileClose(TestDbf); AssertTrue(Result, 'DBFFileClose should succeed');
  Result := DBFFileDispose(TestDbf); AssertTrue(Result, 'DBFFileDispose should succeed');

  { Cleanup }
  EraseFile(TestFileName + '.TXT');
  EraseFile(TestFileName + '.MEM');
  EraseFile(TestFileName + '.DBF');
  EraseFile(TestFileName + '.DBT');
  EndTest;
end;

procedure TestParseMemoLine;
var
  TestBuffer: array[0..255] of Byte;
  RowIndex: LongInt;
  FieldIdx: Integer;
  MemoType: LongInt;
  BlockNum: LongInt;
  HasBlock: Boolean;
  ContentStart: LongInt;
  ContentLen: LongInt;
  Result: Boolean;
  TestString: string;
begin
  BeginTest('ParseMemoLine');
  
  { Test 1: Valid memo line with block number }
  { Format: rowIndex|fieldIdx|memoType|blockNum|content }
  TestString := '1|3|1|5|This is test memo content';
  FillChar(TestBuffer, SizeOf(TestBuffer), 0);
  Move(TestString[1], TestBuffer, Length(TestString));

  Result := ParseMemoLine(@TestBuffer, Length(TestString), RowIndex, FieldIdx,
                         MemoType, BlockNum, HasBlock, ContentStart, ContentLen);

  AssertTrue(Result, 'Should parse valid memo line');
  AssertEqualsInt(1, RowIndex, 'Row index should be 1');
  AssertEqualsInt(3, FieldIdx, 'Field index should be 3');
  AssertEqualsInt(1, MemoType, 'Memo type should be 1');
  AssertEqualsInt(5, BlockNum, 'Block number should be 5');
  AssertTrue(HasBlock, 'Should have block');
  AssertTrue(ContentLen > 0, 'Content length should be positive');

  { Test 2: Memo line without block number }
  { Format: rowIndex|fieldIdx|memoType|content }
  TestString := '2|1|0|Simple memo text here';
  FillChar(TestBuffer, SizeOf(TestBuffer), 0);
  Move(TestString[1], TestBuffer, Length(TestString));

  Result := ParseMemoLine(@TestBuffer, Length(TestString), RowIndex, FieldIdx,
                         MemoType, BlockNum, HasBlock, ContentStart, ContentLen);

  AssertTrue(Result, 'Should parse memo line without block');
  AssertEqualsInt(2, RowIndex, 'Row index should be 2');
  AssertEqualsInt(1, FieldIdx, 'Field index should be 1');
  AssertEqualsInt(1, MemoType, 'Memo type should default to 1');
  AssertFalse(HasBlock, 'Should not have block');
  AssertTrue(ContentLen > 0, 'Content length should be positive');
  
  { Test 3: Invalid memo line }
  TestString := 'INVALID LINE FORMAT';
  FillChar(TestBuffer, SizeOf(TestBuffer), 0);
  Move(TestString[1], TestBuffer, Length(TestString));
  
  Result := ParseMemoLine(@TestBuffer, Length(TestString), RowIndex, FieldIdx, 
                         MemoType, BlockNum, HasBlock, ContentStart, ContentLen);
  
  AssertFalse(Result, 'Should fail to parse invalid memo line');
  
  { Test 4: Empty buffer }
  FillChar(TestBuffer, SizeOf(TestBuffer), 0);
  
  Result := ParseMemoLine(@TestBuffer, 0, RowIndex, FieldIdx, 
                         MemoType, BlockNum, HasBlock, ContentStart, ContentLen);
  
  AssertFalse(Result, 'Should fail to parse empty buffer');
  EndTest;
end;

procedure TestDBFTextModule;
begin
  WriteLn('Testing DBFTEXT Module');
  TestExportDBFToText;
  TestImportDBFFromText;
  TestImportDBFFromTextStreaming;
  TestImportDBFFromTextFieldByField;
  TestImportDBFFromTextPacked;
  TestExportDBFMemosToText;
  TestImportDBFMemosFromText;
  TestImportDBFMemosFromTextEx;
  TestParseMemoLine;
end;

begin
  ResetAsserts;
  TestDBFTextModule;
  PrintSummary;
end.
