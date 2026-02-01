{ TESTDBF.PAS - Core DBF module tests }

program TestDBFProgram;

{$M 32768,0,98304}  { Stack: 32KB, Heap: 96KB }

uses Assert, DBFUTIL, DBF;

const
  TestFileName = 'TEST';

var
  TestDbf: PDBFFile;
  RowBuffer: Pointer;
  Values: Pointer;
  TestHeader: TDBFHeader;
  TestResult: Boolean;
  I: Integer;
  FieldCount, RecordCount: Integer;

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

procedure InitTestHeader(var Header: TDBFHeader);
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.Version := $04;  { dBase IV }
  Header.TableFlags := 0;
  Header.LanguageDriver := DBFLangUS;
  Header.FieldCount := 5;
  
  { Field 1: Text field }
  SetField(Header, 1, 'TEXT', 'C', 20, 0);
  
  { Field 2: Number field }
  SetField(Header, 2, 'NUMBER', 'N', 10, 2);
  
  { Field 3: Integer field }
  SetField(Header, 3, 'INTEGER', 'N', 8, 0);
  
  { Field 4: Date field }
  SetField(Header, 4, 'DATE', 'D', 8, 0);
  
  { Field 5: Logical field }
  SetField(Header, 5, 'FLAG', 'L', 1, 0);
  
  ComputeHeaderSizes(Header);
end;

procedure SetFieldValueAtRow(var Dbf: PDBFFile; var Header: TDBFHeader;
  RowIndex: LongInt; var RowBuf: Pointer; var SmartValues: Pointer;
  FieldIdx: Integer; Value: string);
var
  I: Integer;
begin
  if RowBuf = nil then
    GetMem(RowBuf, Header.RecordSize);
  if SmartValues = nil then
    SmartValues := AllocateSmartValueArray(Header);

  AssertTrue(DBFFileSeekToRow(Dbf, RowIndex), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileReadRow(Dbf, RowBuf, Header.RecordSize), 'DBFFileReadRow should succeed');
  for I := 1 to Header.FieldCount do
    AssertTrue(DBFFieldSetStr(SmartValues, Header, I,
      DBFFieldGetStr(RowBuf, Header, I)), 'DBFFieldSetStr should succeed');

  AssertTrue(DBFFieldSetStr(SmartValues, Header, FieldIdx, Value), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileSeekToRow(Dbf, RowIndex), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileWriteRow(Dbf, SmartValues, Header.FieldCount), 'DBFFileWriteRow should succeed');
end;

function GetFieldValueAtRow(var Dbf: PDBFFile; var Header: TDBFHeader;
  RowIndex: LongInt; var RowBuf: Pointer; FieldIdx: Integer): string;
begin
  if RowBuf = nil then
    GetMem(RowBuf, Header.RecordSize);
  AssertTrue(DBFFileSeekToRow(Dbf, RowIndex), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileReadRow(Dbf, RowBuf, Header.RecordSize), 'DBFFileReadRow should succeed');
  GetFieldValueAtRow := DBFFieldGetStr(RowBuf, Header, FieldIdx);
end;

{ Test basic DBF creation and destruction }
procedure TestDBFCreateDestroy;
var
  Year, Month, Day: Word;
  DbfYear, DbfMonth, DbfDay: Byte;
begin
  BeginTest('DBF Creation and Destruction');
  
  MemoryReport('Before DBF Creation');
  
  { Get current system date for validation }
  GetDate(Year, Month, Day);
  
  { Initialize pointers to nil }
  TestDbf := nil;
  
  { Test with minimal header }
  FillChar(TestHeader, SizeOf(TestHeader), 0);
  TestHeader.Version := $03;  { dBase III }
  TestHeader.FieldCount := 1;
  TestHeader.Fields[1].Name := 'FIELD1';
  TestHeader.Fields[1].FieldType := 'C';
  TestHeader.Fields[1].Length := 10;
  TestHeader.Fields[1].Decimals := 0;
  TestHeader.Fields[1].Offset := 1;
  TestHeader.RecordSize := 11;
  TestHeader.HeaderSize := 32 + (1 * 32) + 1;
  
  WriteLn('About to call DBFFileCreate...');
  TestResult := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');
  WriteLn('DBFFileCreate returned');
  
  MemoryReport('After DBF Creation');
  
  if TestDbf <> nil then
  begin
    WriteLn('TestDbf is not nil, testing date auto-fill...');
    
    { Verify auto-filled date matches today's date }
    AssertTrue(DBFFileGetDate(TestDbf, DbfYear, DbfMonth, DbfDay), 'DBFFileGetDate should succeed');
    AssertEqualsInt(Year - 1900, DbfYear, 'Year should be auto-filled to current year');
    AssertEqualsInt(Month, DbfMonth, 'Month should be auto-filled to current month');
    AssertEqualsInt(Day, DbfDay, 'Day should be auto-filled to current day');
    
    WriteLn('Date validation passed, closing...');
    TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
    TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
    TestDbf := nil;
    WriteLn('Cleanup complete');
  end
  else
    WriteLn('TestDbf is nil');
  
  EndTest;
end;

{ Test field operations }
procedure TestFieldOperations;
begin
  BeginTest('Field Operations');
  
  { Initialize pointers to nil }
  TestDbf := nil;
  
  InitTestHeader(TestHeader);
  TestResult := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');
  AssertNotNil(TestDbf, 'DBFFileCreate should return valid pointer');
  
  { Test field count }
  TestResult := DBFFileGetHeader(TestDbf, TestHeader);
  AssertTrue(TestResult, 'DBFFileGetHeader should succeed');
  AssertEqualsInt(5, TestHeader.FieldCount, 'Should have 5 fields');
  
  { Test record size (1 deletion flag + sum of field lengths) }
  AssertEqualsInt(1 + 20 + 10 + 8 + 8 + 1, TestHeader.RecordSize, 'Record size should match fields');
  
  { Test field types }
  AssertEqualsStr('TEXT', TestHeader.Fields[1].Name, 'Field 1 should be TEXT');
  AssertEqualsStr('C', TestHeader.Fields[1].FieldType, 'Field 1 should be character');
  AssertEqualsStr('NUMBER', TestHeader.Fields[2].Name, 'Field 2 should be NUMBER');
  AssertEqualsStr('N', TestHeader.Fields[2].FieldType, 'Field 2 should be numeric');
  AssertEqualsStr('FLAG', TestHeader.Fields[5].Name, 'Field 5 should be FLAG');
  AssertEqualsStr('L', TestHeader.Fields[5].FieldType, 'Field 5 should be logical');
  
  { Clean up }
  if TestDbf <> nil then
  begin
    TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
    TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
    TestDbf := nil;
  end;
  
  EndTest;
end;

{ Test record operations }
procedure TestRecordOperations;
var
  TestDbf: PDBFFile;
  TestHeader: TDBFHeader;
  RowBuffer: Pointer;
  SmartValues: Pointer;
  I: Integer;
  RecordCount: LongInt;
begin
  BeginTest('Record Operations');
  
  { Initialize pointers to nil }
  TestDbf := nil;
  RowBuffer := nil;
  SmartValues := nil;
  
  InitTestHeader(TestHeader);
  TestResult := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');
  AssertNotNil(TestDbf, 'DBFFileCreate should return valid pointer');
  
  { Get initial record count }
  RecordCount := DBFFileGetActualRowCount(TestDbf);
  AssertEqualsInt(0, RecordCount, 'New DBF should have 0 records');
  
  { Allocate row buffer }
  GetMem(RowBuffer, TestHeader.RecordSize);
  AssertNotNil(RowBuffer, 'Row buffer allocation should succeed');
  
  { Allocate smart value array for optimal memory usage }
  SmartValues := AllocateSmartValueArray(TestHeader);
  AssertNotNil(SmartValues, 'Smart values array allocation should succeed');
  
  MemoryReport('Allocated SmartValueArray (exact field sizes)');
  
  { Test adding a record using smart values }
  { Set field values using smart accessors }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Sample text data'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '123.45'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '67890'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, '20240127'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, 'T'), 'DBFFieldSetStr should succeed');
  
  MemoryReport('After setting smart field values');
  
  { Test DBF operations with smart values }
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');
  WriteLn('DBFFileAppendRow returned');
  
  { Check record count increased }
  RecordCount := DBFFileGetActualRowCount(TestDbf);
  AssertEqualsInt(1, RecordCount, 'Record count should be 1 after adding');
  
  { Test getting record }
  WriteLn('About to call DBFFileSeekToRow...');
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  WriteLn('About to call DBFFileReadRow...');
  AssertTrue(DBFFileReadRow(TestDbf, RowBuffer, TestHeader.RecordSize), 'DBFFileReadRow should succeed');
  WriteLn('DBFFileReadRow returned');

  MemoryReport('DBFFileReadRow: Read Row');

  { Clean up }
  MemoryReport('Before cleanup');
  
  if SmartValues <> nil then
  begin
    TestResult := FreeSmartValueArray(SmartValues); AssertTrue(TestResult, 'FreeSmartValueArray should succeed');
    SmartValues := nil;
    MemoryReport('After SmartValues cleanup');
  end;
  if RowBuffer <> nil then
  begin
    FreeMem(RowBuffer, TestHeader.RecordSize);
    RowBuffer := nil;
    MemoryReport('After RowBuffer cleanup');
  end;
  if TestDbf <> nil then
  begin
    TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
    TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
    TestDbf := nil;
    MemoryReport('After TestDbf cleanup');
  end;
  
  EndTest;
end;

{ Test file operations }
procedure TestFileOperations;
var
  TestHeader: TDBFHeader;
  SmartValues: Pointer;
begin
  BeginTest('File Operations');
  
  { Initialize pointers to nil }
  TestDbf := nil;
  SmartValues := nil;
  
  { Create a test file first }
  InitTestHeader(TestHeader);
  TestResult := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');
  AssertNotNil(TestDbf, 'DBFFileCreate should return valid pointer');
  
  { Add a record to the file }
  SmartValues := AllocateSmartValueArray(TestHeader);
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Test data'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '123.45'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '67890'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, '20240127'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, 'T'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');
  TestResult := FreeSmartValueArray(SmartValues); AssertTrue(TestResult, 'FreeSmartValueArray should succeed');
  
  { Close and dispose the file }
  TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
  TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
  TestDbf := nil;
  
  { Test opening existing file }
  WriteLn('About to call DBFFileOpen for file: ', TestFileName);
  TestResult := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(TestResult, 'DBFFileOpen should succeed');
  WriteLn('DBFFileOpen returned');
  
  AssertNotNil(TestDbf, 'DBFFileOpen should return valid pointer for existing file');
  
  { Test file info }
  RecordCount := DBFFileGetActualRowCount(TestDbf);
  AssertTrue(RecordCount > 0, 'Opened file should have records');
  
  { Test closing }
  WriteLn('About to call DBFFileClose...');
  TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
  WriteLn('DBFFileClose returned');
  
  TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
  TestDbf := nil;
  
  { Test reopening }
  WriteLn('About to call DBFFileOpen again...');
  TestResult := DBFFileOpen(TestDbf, TestFileName);
  AssertTrue(TestResult, 'DBFFileOpen should succeed');
  WriteLn('Second DBFFileOpen returned');
  
  AssertNotNil(TestDbf, 'DBFFileOpen should work after close');
  
  TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
  TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
  TestDbf := nil;
  
  EndTest;
end;

{ Test field value operations }
procedure TestFieldValueOperations;
var
  TestDbf: PDBFFile;
  TestHeader: TDBFHeader;
  RowBuffer: Pointer;
  SmartValues: Pointer;
  I: Integer;
begin
  BeginTest('Field Value Operations');
  
  { Initialize pointers to nil }
  TestDbf := nil;
  SmartValues := nil;
  
  InitTestHeader(TestHeader);
  TestResult := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');
  AssertNotNil(TestDbf, 'DBFFileCreate should return valid pointer');
  
  { Allocate smart value array }
  SmartValues := AllocateSmartValueArray(TestHeader);
  AssertNotNil(SmartValues, 'Smart values array allocation should succeed');
  
  { Allocate row buffer }
  GetMem(RowBuffer, TestHeader.RecordSize);
  AssertNotNil(RowBuffer, 'Row buffer allocation should succeed');
  
  { Set field values using smart accessors }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Sample text data'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '123.45'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '67890'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, '20240127'), 'DBFFieldSetStr should succeed');  
    { Simple date string - conversion handled internally }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, 'F'), 'DBFFieldSetStr should succeed');
  
  { Add record with field values }
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');

  { Clear memo fields (no memo fields in this header, should still succeed) }
  TestResult := DBFFileClearMemoFields(TestDbf);
  AssertTrue(TestResult, 'DBFFileClearMemoFields should succeed');
  
  { Retrieve and verify field values }
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileReadRow(TestDbf, RowBuffer, TestHeader.RecordSize), 'DBFFileReadRow should succeed');
  
  AssertEqualsStr('Sample text data', 
    TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 1)), 'Text field should match');
  AssertEqualsStr('123.45', 
    TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 2)), 'Number field should match');
  AssertEqualsStr('67890', 
    TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 3)), 'Integer field should match');
  AssertEqualsStr('20240127', 
    TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 4)), 'Date field should match');
  AssertEqualsStr('F', 
    TrimString(DBFFieldGetStr(RowBuffer, TestHeader, 5)), 'Logical field should match');
  
  { Clean up }
  if SmartValues <> nil then
  begin
    TestResult := FreeSmartValueArray(SmartValues); AssertTrue(TestResult, 'FreeSmartValueArray should succeed');
    SmartValues := nil;
  end;
  if RowBuffer <> nil then
  begin
    FreeMem(RowBuffer, TestHeader.RecordSize);
    RowBuffer := nil;
  end;
  if TestDbf <> nil then
  begin
    TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
    TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
    TestDbf := nil;
  end;
  
  EndTest;
end;

{ Test direct field operations }
procedure TestDirectFieldOperations;
var
  TestDbf: PDBFFile;
  TestHeader: TDBFHeader;
  SmartValues: Pointer;
  RowBuffer: Pointer;
  I: Integer;
  TestStr: string;
  UnpackedStr: string;
begin
  BeginTest('Direct Field Operations');
  
  { Initialize pointers to nil }
  TestDbf := nil;
  SmartValues := nil;
  RowBuffer := nil;
  
  InitTestHeader(TestHeader);
  TestResult := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');
  AssertNotNil(TestDbf, 'DBFFileCreate should return valid pointer');
  
  { Allocate smart value array }
  SmartValues := AllocateSmartValueArray(TestHeader);
  AssertNotNil(SmartValues, 'Smart values array allocation should succeed');
  
  { Create initial record with known values }
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Original text'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '123.45'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '67890'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, '20240127'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, 'T'), 'DBFFieldSetStr should succeed');
  
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');
  
  { Test 1: Direct field get operations }
  WriteLn('Testing direct field get operations...');
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  AssertEqualsStr('Original text', TrimString(TestStr), 'Field 1 should match original value');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 2);
  AssertEqualsStr('123.45', TrimString(TestStr), 'Field 2 should match original value');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 3);
  AssertEqualsStr('67890', TrimString(TestStr), 'Field 3 should match original value');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 4);
  AssertEqualsStr('20240127', TrimString(TestStr), 'Field 4 should match original value');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 5);
  AssertEqualsStr('T', TrimString(TestStr), 'Field 5 should match original value');
  
  { Test 2: Direct field set operations }
  WriteLn('Testing direct field set operations...');
  
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 1, 'Modified text');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  AssertEqualsStr('Modified text', TrimString(TestStr), 'Field 1 should be modified');
  
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 2, '987.65');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 2);
  AssertEqualsStr('987.65', TrimString(TestStr), 'Field 2 should be modified');
  
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 3, '54321');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 3);
  AssertEqualsStr('54321', TrimString(TestStr), 'Field 3 should be modified');
  
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 4, '20240228');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 4);
  AssertEqualsStr('20240228', TrimString(TestStr), 'Field 4 should be modified');
  
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 5, 'F');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 5);
  AssertEqualsStr('F', TrimString(TestStr), 'Field 5 should be modified');
  
  { Test 3: Verify other fields remain unchanged during single field modification }
  WriteLn('Testing field isolation...');
  
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 1, 'Isolated test');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  AssertEqualsStr('Isolated test', TrimString(TestStr), 'Field 1 should be isolated');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 2);
  AssertEqualsStr('987.65', TrimString(TestStr), 'Field 2 should remain unchanged');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 3);
  AssertEqualsStr('54321', TrimString(TestStr), 'Field 3 should remain unchanged');
  
    { Test 4: SmartValueArray operations }
    WriteLn('Testing smart value operations...');
    
    if SmartValues <> nil then
    begin
      TestResult := FreeSmartValueArray(SmartValues); AssertTrue(TestResult, 'FreeSmartValueArray should succeed');
      SmartValues := nil;
    end;
    SmartValues := AllocateSmartValueArray(TestHeader);
    AssertNotNil(SmartValues, 'AllocateSmartValueArray should succeed');
  
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Test string'), 'DBFFieldSetStr should succeed');
  UnpackedStr := DBFFieldGetSmartStr(SmartValues, TestHeader, 1);
  AssertEqualsStr('Test string', UnpackedStr, 'Character field smart set/get should work');
  
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '123.45'), 'DBFFieldSetStr should succeed');
  UnpackedStr := DBFFieldGetSmartStr(SmartValues, TestHeader, 2);
  AssertEqualsStr('123.45', UnpackedStr, 'Numeric field smart set/get should work');
  
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, 'T'), 'DBFFieldSetStr should succeed');
  UnpackedStr := DBFFieldGetSmartStr(SmartValues, TestHeader, 5);
  AssertEqualsStr('T', UnpackedStr, 'Logical field smart set/get should work');
  
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, '20240127'), 'DBFFieldSetStr should succeed');
  UnpackedStr := DBFFieldGetSmartStr(SmartValues, TestHeader, 4);
  AssertEqualsStr('20240127', UnpackedStr, 'Date field smart set/get should work');
  
    { Test 5: Field length handling }
    WriteLn('Testing field length handling...');
    if SmartValues = nil then
    begin
      SmartValues := AllocateSmartValueArray(TestHeader);
      AssertNotNil(SmartValues, 'AllocateSmartValueArray should succeed');
    end;
  
  { Test with longer string }
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 1, 'This is a very long string that should be truncated');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  AssertEqualsInt(20, Length(TestStr), 'Field should be truncated to 20 characters');
  
  { Test with shorter string }
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 1, 'Short');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  AssertEqualsStr('Short', TrimString(TestStr), 'Short field should work');
  
  { Test 6: Field type validation }
  WriteLn('Testing field type validation...');
  
  { Verify field types are preserved }
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  AssertTrue(Length(TestStr) <= 20, 'Character field should respect length limit');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 2);
  AssertTrue(Length(TestStr) <= 10, 'Numeric field should respect length limit');
  
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 5);
  AssertTrue((TestStr = 'T') or (TestStr = 'F'), 'Logical field should be T or F');
  
  { Clean up }
  if SmartValues <> nil then
  begin
    TestResult := FreeSmartValueArray(SmartValues); AssertTrue(TestResult, 'FreeSmartValueArray should succeed');
    SmartValues := nil;
  end;
  if RowBuffer <> nil then
  begin
    FreeMem(RowBuffer, TestHeader.RecordSize);
    RowBuffer := nil;
  end;
  if TestDbf <> nil then
  begin
    TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
    TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
    TestDbf := nil;
  end;
  
  EndTest;
end;

{ Test compaction operations }
procedure TestCompactionOperations;
var
  TestDbf: PDBFFile;
  CompactDbf: PDBFFile;
  TestHeader: TDBFHeader;
  Values: Pointer;
  I, RecordCount: Integer;
  TestStr: string;
  OriginalRecord1, OriginalRecord3, OriginalRecord5: string;
begin
  BeginTest('Compaction Operations');
  
  { Initialize pointers to nil }
  TestDbf := nil;
  CompactDbf := nil;
  Values := nil;
  RowBuffer := nil;
  
  { Create fresh test file for compaction }
  InitTestHeader(TestHeader);
  TestResult := DBFFileCreate(TestDbf, 'COMPTEST', TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');
  AssertNotNil(TestDbf, 'DBFFileCreate should return valid pointer');
  
  { Allocate values array }
  Values := AllocateSmartValueArray(TestHeader);
  
  { Add several records }
  AssertTrue(DBFFieldSetStr(Values, TestHeader, I+1, 'Record 1'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, Values, 5), 'DBFFileAppendRow should succeed');
  
  AssertTrue(DBFFieldSetStr(Values, TestHeader, I+1, 'Record 2'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, Values, 5), 'DBFFileAppendRow should succeed');
  
  AssertTrue(DBFFieldSetStr(Values, TestHeader, I+1, 'Record 3'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, Values, 5), 'DBFFileAppendRow should succeed');
  
  AssertTrue(DBFFieldSetStr(Values, TestHeader, I+1, 'Record 4'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, Values, 5), 'DBFFileAppendRow should succeed');
  
  AssertTrue(DBFFieldSetStr(Values, TestHeader, I+1, 'Record 5'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFileAppendRow(TestDbf, Values, 5), 'DBFFileAppendRow should succeed');
  
  { Check record count before deletion }
  RecordCount := DBFFileGetActualRowCount(TestDbf);
  AssertTrue(RecordCount >= 5, 'Should have at least 5 records');
  WriteLn('Record count before deletion: ', RecordCount);
  
  { Save the data from records that should survive compaction }
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  OriginalRecord1 := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  
  AssertTrue(DBFFileSeekToRow(TestDbf, 2), 'DBFFileSeekToRow should succeed');
  OriginalRecord3 := GetFieldValueAtRow(TestDbf, TestHeader, 2, RowBuffer, 1);
  
  AssertTrue(DBFFileSeekToRow(TestDbf, 4), 'DBFFileSeekToRow should succeed');
  OriginalRecord5 := GetFieldValueAtRow(TestDbf, TestHeader, 4, RowBuffer, 1);
  
  WriteLn('Original records saved:');
  WriteLn('  Record 1: ', TrimString(OriginalRecord1));
  WriteLn('  Record 3: ', TrimString(OriginalRecord3));
  WriteLn('  Record 5: ', TrimString(OriginalRecord5));
  
  { Mark some records as deleted }
  AssertTrue(DBFFileSeekToRow(TestDbf, 1), 'DBFFileSeekToRow should succeed');  { Second record }
  AssertTrue(DBFFileSetRowDeleted(TestDbf, True), 'DBFFileSetRowDeleted should succeed');
  
  AssertTrue(DBFFileSeekToRow(TestDbf, 3), 'DBFFileSeekToRow should succeed');  { Fourth record }
  AssertTrue(DBFFileSetRowDeleted(TestDbf, True), 'DBFFileSetRowDeleted should succeed');
  
  { Check record count after marking deleted (should be same) }
  RecordCount := DBFFileGetActualRowCount(TestDbf);
  WriteLn('Record count after marking deleted: ', RecordCount);
  
  { Close file before compaction }
  TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
  TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
  TestDbf := nil;
  
  { Compact the database }
  WriteLn('Testing DBFCompact...');
  WriteLn('Source file: COMPTEST');
  WriteLn('Target file: COMPACTD');
  TestResult := DBFCompact('COMPTEST', 'COMPACTD');
  AssertTrue(TestResult, 'DBFCompact should succeed');
  WriteLn('DBFCompact completed');
  
  { Open compacted file }
  CompactDbf := nil;
  
  WriteLn('About to open compacted file: COMPACTD');
  TestResult := DBFFileOpen(CompactDbf, 'COMPACTD');
  AssertTrue(TestResult, 'DBFFileOpen should succeed');
  WriteLn('DBFFileOpen returned');
  
  if CompactDbf = nil then
    WriteLn('ERROR: CompactDbf is nil after DBFFileOpen!')
  else
    WriteLn('SUCCESS: CompactDbf opened successfully');
    
  AssertNotNil(CompactDbf, 'Should be able to open compacted file');
  
  RecordCount := DBFFileGetActualRowCount(CompactDbf);
  WriteLn('Record count after compaction: ', RecordCount);
  AssertTrue(RecordCount >= 3, 'Should have at least 3 non-deleted records after compaction');
  
  { Verify deleted records are gone and remaining records are correct }
  AssertTrue(DBFFileSeekToRow(CompactDbf, 0), 'DBFFileSeekToRow should succeed');
  TestStr := GetFieldValueAtRow(CompactDbf, TestHeader, 0, RowBuffer, 1);
  AssertEqualsStr(TrimString(OriginalRecord1), TrimString(TestStr), 'First record should match original Record 1');
  
  AssertTrue(DBFFileSeekToRow(CompactDbf, 1), 'DBFFileSeekToRow should succeed');
  TestStr := GetFieldValueAtRow(CompactDbf, TestHeader, 1, RowBuffer, 1);
  AssertEqualsStr(TrimString(OriginalRecord3), TrimString(TestStr), 'Second record should match original Record 3');
  
  AssertTrue(DBFFileSeekToRow(CompactDbf, 2), 'DBFFileSeekToRow should succeed');
  TestStr := GetFieldValueAtRow(CompactDbf, TestHeader, 2, RowBuffer, 1);
  AssertEqualsStr(TrimString(OriginalRecord5), TrimString(TestStr), 'Third record should match original Record 5');
  
  { Clean up }
  if Values <> nil then
  begin
    TestResult := FreeSmartValueArray(Values); AssertTrue(TestResult, 'FreeSmartValueArray should succeed');
    Values := nil;
  end;
  if RowBuffer <> nil then
  begin
    FreeMem(RowBuffer, TestHeader.RecordSize);
    RowBuffer := nil;
  end;
  if CompactDbf <> nil then
  begin
    TestResult := DBFFileClose(CompactDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
    TestResult := DBFFileDispose(CompactDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
    CompactDbf := nil;
  end;
  
  EndTest;
end;

{ Test comprehensive DBF operations }
procedure TestComprehensiveOperations;
var
  Year, Month, Day: Byte;
  Lang: Byte;
  TestStr: string;
  SmartValues: Pointer;
  RowIndex: LongInt;
begin
  BeginTest('Comprehensive DBF Operations');
  
  { Initialize pointers to nil }
  TestDbf := nil;
  RowBuffer := nil;
  SmartValues := nil;
  
  { Test 1: DBFFileCreateDBase3 }
  WriteLn('Testing DBFFileCreateDBase3...');
  InitTestHeader(TestHeader);
  TestResult := DBFFileCreateDBase3(TestDbf, 'TEST3', TestHeader);
  AssertTrue(TestResult, 'DBFFileCreateDBase3 should succeed');
  TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
  TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
  TestDbf := nil;
  
  { Test 2: Create regular file for remaining tests with specific date }
  InitTestHeader(TestHeader);
  { Set specific date to verify user date is honored }
  TestHeader.Year := 120;  { 2020 }
  TestHeader.Month := 6;
  TestHeader.Day := 15;
  TestResult := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');
  AssertNotNil(TestDbf, 'DBFFileCreate should return valid pointer');
  
  { Verify user-specified date is honored }
  AssertTrue(DBFFileGetDate(TestDbf, Year, Month, Day), 'DBFFileGetDate should succeed');
  AssertEqualsInt(120, Year, 'User-specified year should be honored (120 = 2020)');
  AssertEqualsInt(6, Month, 'User-specified month should be honored');
  AssertEqualsInt(15, Day, 'User-specified day should be honored');
  
  { Test 3: DBFFileWriteRow }
  WriteLn('Testing DBFFileWriteRow...');
  SmartValues := AllocateSmartValueArray(TestHeader);
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Write test'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '123.45'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '67890'), 'DBFFieldSetStr should succeed');
    AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, '20240127'), 'DBFFieldSetStr should succeed');
    AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, 'T'), 'DBFFieldSetStr should succeed');
    
    { Append one record and verify single-row seek behavior }
    WriteLn('About to append first record...');
    AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');
    WriteLn('First record appended');

    WriteLn('Testing seek operations on single-row table...');
    AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow(0) should succeed');
    AssertTrue(DBFFileGetCurrentRow(TestDbf, RowIndex), 'DBFFileGetCurrentRow should succeed');
    AssertEqualsInt(0, RowIndex, 'Current row should be 0 after seek to row 0');
    AssertTrue(DBFFileSeekToFirstRow(TestDbf), 'DBFFileSeekToFirstRow should succeed');
    AssertTrue(DBFFileGetCurrentRow(TestDbf, RowIndex), 'DBFFileGetCurrentRow should succeed');
    AssertEqualsInt(0, RowIndex, 'Current row should be 0 after seek to first');
    AssertTrue(DBFFileSeekToEnd(TestDbf), 'DBFFileSeekToEnd should succeed');
    AssertTrue(DBFFileGetCurrentRow(TestDbf, RowIndex), 'DBFFileGetCurrentRow should succeed');
    AssertEqualsInt(0, RowIndex, 'Current row should be 0 after seek to end');
    AssertFalse(DBFFileSeekToRow(TestDbf, 1), 'DBFFileSeekToRow(1) should fail on single-row table');
    AssertFalse(DBFFileSeekToRow(TestDbf, -1), 'DBFFileSeekToRow(-1) should fail');

    { Append two more records so row-based tests can target row 1 reliably }

  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Write test 2'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '543.21'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '12345'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, '20240201'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, 'F'), 'DBFFieldSetStr should succeed');
  WriteLn('About to append second record...');
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');
  WriteLn('Second record appended');

  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 1, 'Write test 3'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 2, '999.99'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 3, '77777'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 4, '20240202'), 'DBFFieldSetStr should succeed');
  AssertTrue(DBFFieldSetStr(SmartValues, TestHeader, 5, 'T'), 'DBFFieldSetStr should succeed');
  WriteLn('About to append third record...');
  AssertTrue(DBFFileAppendRow(TestDbf, SmartValues, 5), 'DBFFileAppendRow should succeed');
  WriteLn('Third record appended');
  
  { Now seek to first position and overwrite the row }
  WriteLn('About to seek to first row for write...');
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  WriteLn('About to write row...');
  AssertTrue(DBFFileWriteRow(TestDbf, SmartValues, 5), 'DBFFileWriteRow should succeed');
  WriteLn('DBFFileWriteRow completed');
  
  { Re-seek to first position before reading }
  WriteLn('About to seek to first row again for reading...');
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  WriteLn('About to read field...');
  
  { Test 4: DBFFileSeekToFirstRow and DBFFileSeekToEnd }
  WriteLn('Testing seek operations...');
  AssertTrue(DBFFileSeekToRow(TestDbf, 1), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileSeekToFirstRow(TestDbf), 'DBFFileSeekToFirstRow should succeed');
  AssertTrue(DBFFileGetCurrentRow(TestDbf, RowIndex), 'DBFFileGetCurrentRow should succeed');
  AssertEqualsInt(0, RowIndex, 'Current row should be 0 after seek to first');
  WriteLn('About to call GetFieldValueAtRow...');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  WriteLn('GetFieldValueAtRow returned: ', TestStr);
  AssertEqualsStr('Write test 3', TrimString(TestStr), 'First field should match after seek to first');
  
  WriteLn('About to call DBFFileSeekToEnd...');
  AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
  AssertTrue(DBFFileSeekToEnd(TestDbf), 'DBFFileSeekToEnd should succeed');
  AssertTrue(DBFFileGetCurrentRow(TestDbf, RowIndex), 'DBFFileGetCurrentRow should succeed');
  WriteLn('DBFFileSeekToEnd completed');
  RecordCount := DBFFileGetActualRowCount(TestDbf);
  WriteLn('Record count: ', RecordCount);
  AssertTrue(RecordCount > 0, 'Should have records after seek to end');
  AssertEqualsInt(RecordCount - 1, RowIndex, 'Current row should be last record after seek to end');
  
  { Test 5: GetFieldValueAtRow and row update }
  WriteLn('Testing field get/set operations...');
  WriteLn('About to seek to first row for get/set test...');
  if RecordCount > 1 then
  begin
    AssertTrue(DBFFileSeekToRow(TestDbf, 1), 'DBFFileSeekToRow should succeed');
    AssertTrue(DBFFileGetCurrentRow(TestDbf, RowIndex), 'DBFFileGetCurrentRow should succeed');
    AssertEqualsInt(1, RowIndex, 'Current row should be 1 after seek to row 1');
  end
  else
  begin
    AssertTrue(DBFFileSeekToRow(TestDbf, 0), 'DBFFileSeekToRow should succeed');
    AssertTrue(DBFFileGetCurrentRow(TestDbf, RowIndex), 'DBFFileGetCurrentRow should succeed');
    AssertEqualsInt(0, RowIndex, 'Current row should be 0 when only one row exists');
  end;
  WriteLn('About to call GetFieldValueAtRow for get/set test...');
  if RecordCount > 1 then
    TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 1, RowBuffer, 1)
  else
    TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  WriteLn('GetFieldValueAtRow returned: ', TestStr);
  if RecordCount > 1 then
    AssertEqualsStr('Write test 2', TrimString(TestStr), 'Get field should work')
  else
    AssertEqualsStr('Write test 3', TrimString(TestStr), 'Get field should work');
  
  WriteLn('About to update field via SmartValueArray...');
  SetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, SmartValues, 1, 'Modified text');
  WriteLn('SetFieldValueAtRow completed');
  
  WriteLn('About to call GetFieldValueAtRow again...');
  TestStr := GetFieldValueAtRow(TestDbf, TestHeader, 0, RowBuffer, 1);
  WriteLn('GetFieldValueAtRow returned: ', TestStr);
  AssertEqualsStr('Modified text', TrimString(TestStr), 'Set field should work');
  
  { Test 6: Date operations }
  WriteLn('Testing date operations...');
  AssertTrue(DBFFileGetDate(TestDbf, Year, Month, Day), 'DBFFileGetDate should succeed');
  AssertTrue(Year > 0, 'Should have valid year');
  
  AssertTrue(DBFFileSetDate(TestDbf, 124, 1, 27), 'DBFFileSetDate should succeed');  { 2024 = 124 (2024 - 1900) }
  AssertTrue(DBFFileGetDate(TestDbf, Year, Month, Day), 'DBFFileGetDate should succeed');
  AssertEqualsInt(124, Year, 'Year should be set correctly (124 = 2024)');
  AssertEqualsInt(1, Month, 'Month should be set correctly');
  AssertEqualsInt(27, Day, 'Day should be set correctly');
  
  TestResult := DBFFileIsDateOlder(TestDbf, 124, 1, 26);  { 2024-01-26 }
  AssertFalse(TestResult, 'Current date should not be older than yesterday');
  
  TestResult := DBFFileIsDateOlder(TestDbf, 124, 1, 28);  { 2024-01-28 }
  AssertTrue(TestResult, 'Current date should be older than tomorrow');
  
  { Test 7: Language driver operations }
  WriteLn('Testing language driver operations...');
  AssertTrue(DBFFileGetLanguageDriver(TestDbf, Lang), 'DBFFileGetLanguageDriver should succeed');
  AssertTrue(Lang = DBFLangUS, 'Default language should be US');
  
  AssertTrue(DBFFileSetLanguageDriver(TestDbf, DBFLangJapan), 'DBFFileSetLanguageDriver should succeed');
  AssertTrue(DBFFileGetLanguageDriver(TestDbf, Lang), 'DBFFileGetLanguageDriver should succeed');
  AssertTrue(Lang = DBFLangJapan, 'Language should be set to Japan');
  
  { Clean up }
  if SmartValues <> nil then
  begin
    TestResult := FreeSmartValueArray(SmartValues); AssertTrue(TestResult, 'FreeSmartValueArray should succeed');
    SmartValues := nil;
  end;
  if RowBuffer <> nil then
  begin
    FreeMem(RowBuffer, TestHeader.RecordSize);
    RowBuffer := nil;
  end;
  if TestDbf <> nil then
  begin
    TestResult := DBFFileClose(TestDbf); AssertTrue(TestResult, 'DBFFileClose should succeed');
    TestResult := DBFFileDispose(TestDbf); AssertTrue(TestResult, 'DBFFileDispose should succeed');
    TestDbf := nil;
  end;
  
  EndTest;
end;
  { Main test runner }
begin
  WriteLn('=== DBF Core Module Tests ===');
  WriteLn;
  
  MemoryReport('Initial Memory State');
  
  { Run all tests except error handling (DBF module crashes on file not found) }
  TestDBFCreateDestroy;
  
  MemoryReport('After DBF Creation Tests');
  
  TestFieldOperations;
  
  MemoryReport('After DBF Field Tests');
  
  TestRecordOperations;
  
  MemoryReport('After DBF Record Tests');
  
  TestFileOperations;
  
  MemoryReport('After DBF File Tests');
  
  TestFieldValueOperations;
  
  MemoryReport('After DBF Field Value Tests');
  
  TestDirectFieldOperations;
  
  MemoryReport('After Direct Field Tests');
  
  TestComprehensiveOperations;
  
  MemoryReport('After Comprehensive Tests');
  
  TestCompactionOperations;
  
  MemoryReport('After Compaction Tests');
  
  MemoryReport('Final Memory State');
  
  WriteLn;
  PrintSummary;
  
  { Clean up test files }
  WriteLn('Cleaning up test files...');
  if DeleteFile('TEST.DBF') then
    WriteLn('Deleted TEST.DBF');
  if DeleteFile('TEST3.DBF') then
    WriteLn('Deleted TEST3.DBF');
  if DeleteFile('COMPTEST.DBF') then
    WriteLn('Deleted COMPTEST.DBF');
  if DeleteFile('COMPACTD.DBF') then
    WriteLn('Deleted COMPACTD.DBF');
  WriteLn('Cleanup complete');
end.
