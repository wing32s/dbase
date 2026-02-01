{ TESTFIND.PAS - Comprehensive tests for DBFFind search functions }

program TestFindProgram;

{$M 32768,0,98304}  { Stack: 32KB, Heap: 96KB }

uses Assert, DBFUTIL, DBF, DBFFind;

const
  TestFileName = 'TFIND';
  MaxResults = 16;

var
  TestDbf: PDBFFile;
  TestHeader: TDBFHeader;
  SmartValues: Pointer;
  RowBuffer: Pointer;
  TestResult: Boolean;
  RowIds: PRowIdArray;
  Count: Integer;
  ScanPos: LongInt;
  I: Integer;

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

procedure InitFindHeader(var Header: TDBFHeader);
begin
  FillChar(Header, SizeOf(Header), 0);
  Header.Version := $04;
  Header.TableFlags := 0;
  Header.LanguageDriver := DBFLangUS;
  Header.FieldCount := 4;

  { Field 1: NAME - character for exact/starts-with }
  SetField(Header, 1, 'NAME', 'C', 20, 0);
  { Field 2: AGE - numeric for exact num search }
  SetField(Header, 2, 'AGE', 'N', 8, 0);
  { Field 3: MIN_VAL - numeric for range min }
  SetField(Header, 3, 'MIN_VAL', 'N', 8, 0);
  { Field 4: MAX_VAL - numeric for range max }
  SetField(Header, 4, 'MAX_VAL', 'N', 8, 0);

  ComputeHeaderSizes(Header);
end;

procedure AppendRow(var Dbf: PDBFFile; var Header: TDBFHeader;
  var Values: Pointer; Name, Age, MinV, MaxV: string);
begin
  AssertTrue(DBFFieldSetStr(Values, Header, 1, Name), 'SetStr NAME');
  AssertTrue(DBFFieldSetStr(Values, Header, 2, Age), 'SetStr AGE');
  AssertTrue(DBFFieldSetStr(Values, Header, 3, MinV), 'SetStr MIN_VAL');
  AssertTrue(DBFFieldSetStr(Values, Header, 4, MaxV), 'SetStr MAX_VAL');
  AssertTrue(DBFFileAppendRow(Dbf, Values, 4), 'AppendRow');
end;

procedure CreateTestDatabase;
begin
  TestDbf := nil;
  SmartValues := nil;
  RowBuffer := nil;

  InitFindHeader(TestHeader);
  TestResult := DBFFileCreate(TestDbf, TestFileName, TestHeader);
  AssertTrue(TestResult, 'DBFFileCreate should succeed');

  SmartValues := AllocateSmartValueArray(TestHeader);
  AssertNotNil(SmartValues, 'AllocateSmartValueArray should succeed');

  { Row 0: Alice, 25, 10..50 }
  AppendRow(TestDbf, TestHeader, SmartValues, 'Alice', '25', '10', '50');
  { Row 1: Bob, 30, 20..60 }
  AppendRow(TestDbf, TestHeader, SmartValues, 'Bob', '30', '20', '60');
  { Row 2: Alice, 25, 30..70 }
  AppendRow(TestDbf, TestHeader, SmartValues, 'Alice', '25', '30', '70');
  { Row 3: Charlie, 35, 40..80 }
  AppendRow(TestDbf, TestHeader, SmartValues, 'Charlie', '35', '40', '80');
  { Row 4: Alice, 40, 50..90 }
  AppendRow(TestDbf, TestHeader, SmartValues, 'Alice', '40', '50', '90');
  { Row 5: Bob, 25, 100..200 }
  AppendRow(TestDbf, TestHeader, SmartValues, 'Bob', '25', '100', '200');
  { Row 6: David, 30, 0..0 }
  AppendRow(TestDbf, TestHeader, SmartValues, 'David', '30', '0', '0');
  { Row 7: Alex, 45, 10..100 }
  AppendRow(TestDbf, TestHeader, SmartValues, 'Alex', '45', '10', '100');
end;

procedure DestroyTestDatabase;
begin
  if SmartValues <> nil then
  begin
    TestResult := FreeSmartValueArray(SmartValues);
    AssertTrue(TestResult, 'FreeSmartValueArray should succeed');
    SmartValues := nil;
  end;
  if RowBuffer <> nil then
  begin
    FreeMem(RowBuffer, TestHeader.RecordSize);
    RowBuffer := nil;
  end;
  if TestDbf <> nil then
  begin
    TestResult := DBFFileClose(TestDbf);
    AssertTrue(TestResult, 'DBFFileClose should succeed');
    TestResult := DBFFileDispose(TestDbf);
    AssertTrue(TestResult, 'DBFFileDispose should succeed');
    TestDbf := nil;
  end;
end;

{ ---------------------------------------------------------------- }
{  FindRowsExact tests                                             }
{ ---------------------------------------------------------------- }

procedure TestExactNilDbf;
var
  NilDbf: PDBFFile;
begin
  BeginTest('FindRowsExact - nil Dbf returns False');
  NilDbf := nil;
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(NilDbf, 1, 'Alice',
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for nil Dbf');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

procedure TestExactNilRowIds;
begin
  BeginTest('FindRowsExact - nil RowIds returns False');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Alice',
    nil, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for nil RowIds');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

procedure TestExactZeroMaxCount;
begin
  BeginTest('FindRowsExact - zero MaxCount returns False');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Alice',
    RowIds, 0, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for MaxCount=0');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

procedure TestExactInvalidField;
begin
  BeginTest('FindRowsExact - invalid FieldIdx returns False');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 0, 'Alice',
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for FieldIdx=0');
  AssertEqualsInt(0, Count, 'Count should be 0');

  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 99, 'Alice',
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for FieldIdx=99');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

procedure TestExactFindAlice;
begin
  BeginTest('FindRowsExact - find Alice returns 3 rows');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Alice',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(3, Count, 'Should find 3 Alice rows');
  AssertEqualsInt(0, RowIdAt(RowIds, 0), 'First match at row 0');
  AssertEqualsInt(2, RowIdAt(RowIds, 1), 'Second match at row 2');
  AssertEqualsInt(4, RowIdAt(RowIds, 2), 'Third match at row 4');
  AssertEqualsInt(8, ScanPos, 'ScanPos should be total rows');
  EndTest;
end;

procedure TestExactFindBob;
begin
  BeginTest('FindRowsExact - find Bob returns 2 rows');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Bob',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(2, Count, 'Should find 2 Bob rows');
  AssertEqualsInt(1, RowIdAt(RowIds, 0), 'First match at row 1');
  AssertEqualsInt(5, RowIdAt(RowIds, 1), 'Second match at row 5');
  EndTest;
end;

procedure TestExactNoMatch;
begin
  BeginTest('FindRowsExact - no match returns 0 count');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Nobody',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 rows');
  EndTest;
end;

procedure TestExactCaseInsensitive;
begin
  BeginTest('FindRowsExact - case insensitive');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'alice',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(3, Count, 'Should find 3 rows case-insensitively');

  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'ALICE',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(3, Count, 'Should find 3 rows with upper case');
  EndTest;
end;

procedure TestExactMaxCountLimit;
begin
  BeginTest('FindRowsExact - MaxCount limits results');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Alice',
    RowIds, 2, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed with limited buffer');
  AssertEqualsInt(2, Count, 'Should return only 2 results');
  AssertEqualsInt(0, RowIdAt(RowIds, 0), 'First match at row 0');
  AssertEqualsInt(2, RowIdAt(RowIds, 1), 'Second match at row 2');
  AssertTrue(ScanPos > 2, 'ScanPos should advance past last match');
  EndTest;
end;

procedure TestExactScanPosContinuation;
begin
  BeginTest('FindRowsExact - ScanPos continuation');
  { First batch: get first 2 }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Alice',
    RowIds, 2, Count, ScanPos);
  AssertTrue(TestResult, 'First batch should succeed');
  AssertEqualsInt(2, Count, 'First batch: 2 results');

  { Second batch: continue from ScanPos }
  Count := 0;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Alice',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Second batch should succeed');
  AssertEqualsInt(1, Count, 'Second batch: 1 remaining result');
  AssertEqualsInt(4, RowIdAt(RowIds, 0), 'Remaining match at row 4');
  EndTest;
end;

procedure TestExactNegativeScanPos;
begin
  BeginTest('FindRowsExact - negative ScanPos corrected to 0');
  Count := 0;
  ScanPos := -5;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Alice',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed with negative ScanPos');
  AssertEqualsInt(3, Count, 'Should find all 3 Alice rows');
  EndTest;
end;

procedure TestExactScanPosBeyondEnd;
begin
  BeginTest('FindRowsExact - ScanPos beyond end returns False');
  Count := 0;
  ScanPos := 9999;
  TestResult := DBFFileFindRowsExact(TestDbf, 1, 'Alice',
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False when ScanPos past end');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

{ ---------------------------------------------------------------- }
{  FindRowsExactNum tests                                          }
{ ---------------------------------------------------------------- }

procedure TestExactNumNilDbf;
var
  NilDbf: PDBFFile;
begin
  BeginTest('FindRowsExactNum - nil Dbf returns False');
  NilDbf := nil;
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExactNum(NilDbf, 2, 25,
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for nil Dbf');
  EndTest;
end;

procedure TestExactNumInvalidField;
begin
  BeginTest('FindRowsExactNum - invalid FieldIdx returns False');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExactNum(TestDbf, 0, 25,
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for FieldIdx=0');

  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExactNum(TestDbf, 99, 25,
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for FieldIdx=99');
  EndTest;
end;

procedure TestExactNumFind25;
begin
  BeginTest('FindRowsExactNum - find AGE=25 should find 3 rows');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExactNum(TestDbf, 2, 25,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(3, Count, 'Should find 3 rows with AGE=25');
  AssertEqualsInt(0, RowIdAt(RowIds, 0), 'Row 0 has AGE=25');
  AssertEqualsInt(2, RowIdAt(RowIds, 1), 'Row 2 has AGE=25');
  AssertEqualsInt(5, RowIdAt(RowIds, 2), 'Row 5 has AGE=25');
  EndTest;
end;

procedure TestExactNumFind30;
begin
  BeginTest('FindRowsExactNum - find AGE=30 should find 2 rows');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExactNum(TestDbf, 2, 30,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(2, Count, 'Should find 2 rows with AGE=30');
  AssertEqualsInt(1, RowIdAt(RowIds, 0), 'Row 1 has AGE=30');
  AssertEqualsInt(6, RowIdAt(RowIds, 1), 'Row 6 has AGE=30');
  EndTest;
end;

procedure TestExactNumNoMatch;
begin
  BeginTest('FindRowsExactNum - no match');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExactNum(TestDbf, 2, 99,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 rows');
  EndTest;
end;

procedure TestExactNumMaxCountLimit;
begin
  BeginTest('FindRowsExactNum - MaxCount limits results');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExactNum(TestDbf, 2, 25,
    RowIds, 1, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(1, Count, 'Should return only 1 result');
  AssertEqualsInt(0, RowIdAt(RowIds, 0), 'First match at row 0');
  AssertTrue(ScanPos > 0, 'ScanPos should advance');
  EndTest;
end;

procedure TestExactNumContinuation;
begin
  BeginTest('FindRowsExactNum - ScanPos continuation');
  { First: get 1 }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsExactNum(TestDbf, 2, 25,
    RowIds, 1, Count, ScanPos);
  AssertTrue(TestResult, 'First batch should succeed');
  AssertEqualsInt(1, Count, 'First batch: 1 result');

  { Second: continue }
  Count := 0;
  TestResult := DBFFileFindRowsExactNum(TestDbf, 2, 25,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Second batch should succeed');
  AssertEqualsInt(2, Count, 'Second batch: 2 remaining');
  AssertEqualsInt(2, RowIdAt(RowIds, 0), 'Match at row 2');
  AssertEqualsInt(5, RowIdAt(RowIds, 1), 'Match at row 5');
  EndTest;
end;

{ ---------------------------------------------------------------- }
{  FindRowsInRangeNum tests                                        }
{ ---------------------------------------------------------------- }

procedure TestRangeNilDbf;
var
  NilDbf: PDBFFile;
begin
  BeginTest('FindRowsInRangeNum - nil Dbf returns False');
  NilDbf := nil;
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(NilDbf, 3, 4, 55,
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for nil Dbf');
  EndTest;
end;

procedure TestRangeInvalidFields;
begin
  BeginTest('FindRowsInRangeNum - invalid field indices');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 0, 4, 55,
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for FieldIdxMin=0');

  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 3, 0, 55,
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for FieldIdxMax=0');

  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 99, 4, 55,
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for FieldIdxMin=99');
  EndTest;
end;

procedure TestRangeFindValue55;
begin
  BeginTest('FindRowsInRangeNum - value 55 in range should find 5');
  { Row 0: 10..50  -> no (55>50)
    Row 1: 20..60  -> yes
    Row 2: 30..70  -> yes
    Row 3: 40..80  -> yes
    Row 4: 50..90  -> yes
    Row 5: 100..200 -> no (55<100)
    Row 6: 0..0    -> skipped (both zero)
    Row 7: 10..100 -> yes }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 3, 4, 55,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(5, Count, 'Should find 5 rows in range');
  AssertEqualsInt(1, RowIdAt(RowIds, 0), 'Row 1 in range');
  AssertEqualsInt(2, RowIdAt(RowIds, 1), 'Row 2 in range');
  AssertEqualsInt(3, RowIdAt(RowIds, 2), 'Row 3 in range');
  AssertEqualsInt(4, RowIdAt(RowIds, 3), 'Row 4 in range');
  AssertEqualsInt(7, RowIdAt(RowIds, 4), 'Row 7 in range');
  EndTest;
end;

procedure TestRangeBoundaryExact;
begin
  BeginTest('FindRowsInRangeNum - boundary values');
  { Value=10 should match rows with min<=10<=max }
  { Row 0: 10..50  -> yes (10>=10)
    Row 7: 10..100 -> yes (10>=10) }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 3, 4, 10,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(2, Count, 'Should find 2 rows at boundary');
  AssertEqualsInt(0, RowIdAt(RowIds, 0), 'Row 0 at boundary');
  AssertEqualsInt(7, RowIdAt(RowIds, 1), 'Row 7 at boundary');

  { Value=200 should match only row 5: 100..200 }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 3, 4, 200,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(1, Count, 'Should find 1 row at upper boundary');
  AssertEqualsInt(5, RowIdAt(RowIds, 0), 'Row 5 at upper boundary');
  EndTest;
end;

procedure TestRangeNoMatch;
begin
  BeginTest('FindRowsInRangeNum - no match');
  { Value=999 should match nothing }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 3, 4, 999,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 rows');
  EndTest;
end;

procedure TestRangeMaxCountLimit;
begin
  BeginTest('FindRowsInRangeNum - MaxCount limits results');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 3, 4, 55,
    RowIds, 2, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(2, Count, 'Should return only 2 results');
  AssertTrue(ScanPos > 0, 'ScanPos should advance');
  EndTest;
end;

procedure TestRangeContinuation;
begin
  BeginTest('FindRowsInRangeNum - ScanPos continuation');
  { First batch: 2 results }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 3, 4, 55,
    RowIds, 2, Count, ScanPos);
  AssertTrue(TestResult, 'First batch should succeed');
  AssertEqualsInt(2, Count, 'First batch: 2 results');

  { Second batch: continue }
  Count := 0;
  TestResult := DBFFileFindRowsInRangeNum(TestDbf, 3, 4, 55,
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Second batch should succeed');
  AssertEqualsInt(3, Count, 'Second batch: 3 remaining');
  EndTest;
end;

{ ---------------------------------------------------------------- }
{  FindRowsStartsWith tests                                        }
{ ---------------------------------------------------------------- }

procedure TestStartsWithNilDbf;
var
  NilDbf: PDBFFile;
begin
  BeginTest('FindRowsStartsWith - nil Dbf returns False');
  NilDbf := nil;
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(NilDbf, 1, 'Al',
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for nil Dbf');
  EndTest;
end;

procedure TestStartsWithNilRowIds;
begin
  BeginTest('FindRowsStartsWith - nil RowIds returns False');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'Al',
    nil, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for nil RowIds');
  EndTest;
end;

procedure TestStartsWithEmptyPrefix;
begin
  BeginTest('FindRowsStartsWith - empty prefix returns False');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, '',
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for empty prefix');

  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, '   ',
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for whitespace prefix');
  EndTest;
end;

procedure TestStartsWithInvalidField;
begin
  BeginTest('FindRowsStartsWith - invalid FieldIdx returns False');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 0, 'Al',
    RowIds, MaxResults, Count, ScanPos);
  AssertFalse(TestResult, 'Should return False for FieldIdx=0');
  EndTest;
end;

procedure TestStartsWithAl;
begin
  BeginTest('FindRowsStartsWith - prefix Al matches Alice and Alex');
  { Row 0: Alice -> yes
    Row 2: Alice -> yes
    Row 4: Alice -> yes
    Row 7: Alex  -> yes }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'Al',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(4, Count, 'Should find 4 rows starting with Al');
  AssertEqualsInt(0, RowIdAt(RowIds, 0), 'Row 0: Alice');
  AssertEqualsInt(2, RowIdAt(RowIds, 1), 'Row 2: Alice');
  AssertEqualsInt(4, RowIdAt(RowIds, 2), 'Row 4: Alice');
  AssertEqualsInt(7, RowIdAt(RowIds, 3), 'Row 7: Alex');
  EndTest;
end;

procedure TestStartsWithBo;
begin
  BeginTest('FindRowsStartsWith - prefix Bo matches Bob');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'Bo',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(2, Count, 'Should find 2 rows starting with Bo');
  AssertEqualsInt(1, RowIdAt(RowIds, 0), 'Row 1: Bob');
  AssertEqualsInt(5, RowIdAt(RowIds, 1), 'Row 5: Bob');
  EndTest;
end;

procedure TestStartsWithNoMatch;
begin
  BeginTest('FindRowsStartsWith - no match');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'Zz',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 rows');
  EndTest;
end;

procedure TestStartsWithCaseInsensitive;
begin
  BeginTest('FindRowsStartsWith - case insensitive');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'al',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(4, Count, 'Should find 4 rows case-insensitively');

  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'AL',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(4, Count, 'Should find 4 rows with upper case');
  EndTest;
end;

procedure TestStartsWithMaxCountLimit;
begin
  BeginTest('FindRowsStartsWith - MaxCount limits results');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'Al',
    RowIds, 2, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(2, Count, 'Should return only 2 results');
  AssertTrue(ScanPos > 0, 'ScanPos should advance');
  EndTest;
end;

procedure TestStartsWithContinuation;
begin
  BeginTest('FindRowsStartsWith - ScanPos continuation');
  { First batch: 2 }
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'Al',
    RowIds, 2, Count, ScanPos);
  AssertTrue(TestResult, 'First batch should succeed');
  AssertEqualsInt(2, Count, 'First batch: 2 results');

  { Second batch: continue }
  Count := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'Al',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Second batch should succeed');
  AssertEqualsInt(2, Count, 'Second batch: 2 remaining');
  AssertEqualsInt(4, RowIdAt(RowIds, 0), 'Row 4: Alice');
  AssertEqualsInt(7, RowIdAt(RowIds, 1), 'Row 7: Alex');
  EndTest;
end;

procedure TestStartsWithFullName;
begin
  BeginTest('FindRowsStartsWith - full name as prefix');
  Count := 0;
  ScanPos := 0;
  TestResult := DBFFileFindRowsStartsWith(TestDbf, 1, 'Charlie',
    RowIds, MaxResults, Count, ScanPos);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(1, Count, 'Should find 1 row');
  AssertEqualsInt(3, RowIdAt(RowIds, 0), 'Row 3: Charlie');
  EndTest;
end;

{ ---------------------------------------------------------------- }
{  Main test runner                                                }
{ ---------------------------------------------------------------- }

begin
  WriteLn('=== DBFFind Search Tests ===');
  WriteLn;

  MemoryReport('Initial Memory State');

  { Allocate result buffer }
  GetMem(RowIds, MaxResults * SizeOf(LongInt));

  { Create test database }
  CreateTestDatabase;

  MemoryReport('After Test Database Creation');

  { --- FindRowsExact tests --- }
  WriteLn('--- FindRowsExact ---');
  TestExactNilDbf;
  TestExactNilRowIds;
  TestExactZeroMaxCount;
  TestExactInvalidField;
  TestExactFindAlice;
  TestExactFindBob;
  TestExactNoMatch;
  TestExactCaseInsensitive;
  TestExactMaxCountLimit;
  TestExactScanPosContinuation;
  TestExactNegativeScanPos;
  TestExactScanPosBeyondEnd;

  MemoryReport('After FindRowsExact Tests');

  { --- FindRowsExactNum tests --- }
  WriteLn('--- FindRowsExactNum ---');
  TestExactNumNilDbf;
  TestExactNumInvalidField;
  TestExactNumFind25;
  TestExactNumFind30;
  TestExactNumNoMatch;
  TestExactNumMaxCountLimit;
  TestExactNumContinuation;

  MemoryReport('After FindRowsExactNum Tests');

  { --- FindRowsInRangeNum tests --- }
  WriteLn('--- FindRowsInRangeNum ---');
  TestRangeNilDbf;
  TestRangeInvalidFields;
  TestRangeFindValue55;
  TestRangeBoundaryExact;
  TestRangeNoMatch;
  TestRangeMaxCountLimit;
  TestRangeContinuation;

  MemoryReport('After FindRowsInRangeNum Tests');

  { --- FindRowsStartsWith tests --- }
  WriteLn('--- FindRowsStartsWith ---');
  TestStartsWithNilDbf;
  TestStartsWithNilRowIds;
  TestStartsWithEmptyPrefix;
  TestStartsWithInvalidField;
  TestStartsWithAl;
  TestStartsWithBo;
  TestStartsWithNoMatch;
  TestStartsWithCaseInsensitive;
  TestStartsWithMaxCountLimit;
  TestStartsWithContinuation;
  TestStartsWithFullName;

  MemoryReport('After FindRowsStartsWith Tests');

  { Cleanup }
  DestroyTestDatabase;

  MemoryReport('After Database Cleanup');

  FreeMem(RowIds, MaxResults * SizeOf(LongInt));

  MemoryReport('Final Memory State');

  WriteLn;
  PrintSummary;

  { Clean up test files }
  WriteLn;
  WriteLn('Cleaning up test files...');
  if DeleteFile(TestFileName + '.DBF') then
    WriteLn('Deleted ', TestFileName, '.DBF');
  WriteLn('Cleanup complete');
end.


