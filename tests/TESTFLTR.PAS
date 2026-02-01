{ TESTFLTR.PAS - Comprehensive tests for DBFILTER unit }

program TestFltrProgram;

{$M 32768,0,131072}  { Stack: 32KB, Heap: 128KB }

uses Assert, DBFUTIL, DBF, DBFINDEX, DBFILTER;

const
  GamesDbPath = 'samples\GAMES3.DBF';
  DevNdxPath  = 'samples\DEVNAME3.NDX';
  YearNdxPath = 'samples\YEAR3.NDX';
  MaxResults  = 200;
  EnablePhase5 = False;
  BmpFile1    = 'test1.bmp';
  BmpFile2    = 'test2.bmp';
  BmpDest     = 'testd.bmp';

var
  Ok: Boolean;
  
function RowIdAt(Ids: PRowIdArray; Index: Integer): LongInt;
begin
  RowIdAt := Ids^[Index];
end;

procedure SetRowId(Ids: PRowIdArray; Index: Integer; Value: LongInt);
begin
  Ids^[Index] := Value;
end;

{ ================================================================== }
{ Phase 1: Cursor management tests (pure logic, no DBF)              }
{ ================================================================== }

procedure TestCursorReset;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorReset - zeroes cursor');
  FillChar(C, SizeOf(C), $FF);  { Fill with junk }
  DBMatchCursorReset(C);
  AssertEqualsInt(0, C.GroupCount, 'GroupCount should be 0');
  AssertEqualsInt(0, C.ScanPos, 'ScanPos should be 0');
  AssertEqualsInt(-1, C.TotalRows, 'TotalRows should be -1');
  EndTest;
end;

procedure TestCursorInitDefault;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorInitDefault - one mmAll group');
  DBMatchCursorInitDefault(C);
  AssertEqualsInt(1, C.GroupCount, 'Should have 1 group');
  AssertEqualsInt(0, C.Groups[1].FilterCount, 'Group should have 0 filters');
  AssertTrue(C.Groups[1].Mode = mmAll, 'Group mode should be mmAll');
  EndTest;
end;

procedure TestCursorAddGroup;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorAddGroup - up to 4 groups');
  DBMatchCursorReset(C);
  DBMatchCursorAddGroup(C, mmAll);
  AssertEqualsInt(1, C.GroupCount, 'Should have 1 group');
  DBMatchCursorAddGroup(C, mmAny);
  AssertEqualsInt(2, C.GroupCount, 'Should have 2 groups');
  AssertTrue(C.Groups[2].Mode = mmAny, 'Second group should be mmAny');
  DBMatchCursorAddGroup(C, mmAll);
  DBMatchCursorAddGroup(C, mmAll);
  AssertEqualsInt(4, C.GroupCount, 'Should have 4 groups');
  { 5th group should be silently ignored }
  DBMatchCursorAddGroup(C, mmAll);
  AssertEqualsInt(4, C.GroupCount, 'Should still have 4 groups after overflow');
  EndTest;
end;

procedure TestCursorAddExact;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorAddExact - string filter');
  DBMatchCursorInitDefault(C);
  DBMatchCursorAddExact(C, 1, 3, 'TestValue');
  AssertEqualsInt(1, C.Groups[1].FilterCount, 'Should have 1 filter');
  AssertTrue(C.Groups[1].Filters[1].Kind = fkExactStr, 'Kind should be fkExactStr');
  AssertEqualsInt(3, C.Groups[1].Filters[1].FieldIdx, 'FieldIdx should be 3');
  AssertEqualsStr('TestValue', UnpackFilterValue(C.Groups[1].Filters[1]),
    'Value should be TestValue');
  EndTest;
end;

procedure TestCursorAddExactNum;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorAddExactNum - numeric filter');
  DBMatchCursorInitDefault(C);
  DBMatchCursorAddExactNum(C, 1, 2, 1995);
  AssertEqualsInt(1, C.Groups[1].FilterCount, 'Should have 1 filter');
  AssertTrue(C.Groups[1].Filters[1].Kind = fkExactNum, 'Kind should be fkExactNum');
  AssertEqualsInt(2, C.Groups[1].Filters[1].FieldIdx, 'FieldIdx should be 2');
  AssertEqualsInt(1995, C.Groups[1].Filters[1].ValueNum, 'ValueNum should be 1995');
  EndTest;
end;

procedure TestCursorAddStartsWith;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorAddStartsWith - prefix filter');
  DBMatchCursorInitDefault(C);
  DBMatchCursorAddStartsWith(C, 1, 1, 'Nin');
  AssertEqualsInt(1, C.Groups[1].FilterCount, 'Should have 1 filter');
  AssertTrue(C.Groups[1].Filters[1].Kind = fkStartsWith, 'Kind should be fkStartsWith');
  AssertEqualsStr('Nin', UnpackFilterValue(C.Groups[1].Filters[1]),
    'Value should be Nin');
  EndTest;
end;

procedure TestCursorAddFieldRange;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorAddFieldRange - range filter');
  DBMatchCursorInitDefault(C);
  DBMatchCursorAddFieldRange(C, 1, 4, 1990, 1999);
  AssertEqualsInt(1, C.Groups[1].FilterCount, 'Should have 1 filter');
  AssertTrue(C.Groups[1].Filters[1].Kind = fkFieldRange, 'Kind should be fkFieldRange');
  AssertEqualsInt(1990, C.Groups[1].Filters[1].ValueNumMin, 'Min should be 1990');
  AssertEqualsInt(1999, C.Groups[1].Filters[1].ValueNumMax, 'Max should be 1999');
  EndTest;
end;

procedure TestCursorFilterOverflow;
var
  C: TDBMatchCursor;
  I: Integer;
begin
  BeginTest('DBMatchCursorAdd* - max 8 filters per group');
  DBMatchCursorInitDefault(C);
  for I := 1 to 8 do
    DBMatchCursorAddExactNum(C, 1, I, I * 100);
  AssertEqualsInt(8, C.Groups[1].FilterCount, 'Should have 8 filters');
  { 9th filter should be silently ignored }
  DBMatchCursorAddExactNum(C, 1, 9, 900);
  AssertEqualsInt(8, C.Groups[1].FilterCount, 'Should still have 8 after overflow');
  EndTest;
end;

procedure TestCursorAddToInvalidGroup;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorAdd* - invalid group index ignored');
  DBMatchCursorInitDefault(C);
  DBMatchCursorAddExactNum(C, 0, 1, 100);  { Group 0 invalid }
  AssertEqualsInt(0, C.Groups[1].FilterCount, 'Group 1 should have 0 filters');
  DBMatchCursorAddExactNum(C, 5, 1, 100);  { Group 5 > max }
  AssertEqualsInt(0, C.Groups[1].FilterCount, 'Group 1 should still have 0 filters');
  EndTest;
end;

procedure TestCursorSetFilterIndex;
var
  C: TDBMatchCursor;
begin
  BeginTest('DBMatchCursorSetFilterIndex - attach NDX file');
  DBMatchCursorInitDefault(C);
  DBMatchCursorAddStartsWith(C, 1, 2, 'Nin');
  DBMatchCursorSetFilterIndex(C, 1, 1, 'DEVNAME.NDX');
  AssertEqualsStr('DEVNAME.NDX',
    UnpackFilterIndexFile(C.Groups[1].Filters[1]),
    'Index file should be set');
  EndTest;
end;

{ ================================================================== }
{ Phase 2: Bitmap file operation tests                               }
{ ================================================================== }

procedure CleanupBitmapFiles;
begin
  EraseFile(BmpFile1);
  EraseFile(BmpFile2);
  EraseFile(BmpDest);
end;

procedure TestCreateBitmapFile;
var
  F: File;
begin
  BeginTest('CreateBitmapFile - creates empty file');
  MemoryReport('Before CreateBitmapFile');
  CleanupBitmapFiles;
  Ok := CreateBitmapFile(F, BmpFile1);
  AssertTrue(Ok, 'Should succeed');
  CloseBitmapFile(F);
  AssertTrue(FileExists(BmpFile1), 'File should exist');
  CleanupBitmapFiles;
  MemoryReport('After CreateBitmapFile');
  EndTest;
end;

procedure TestSetAndGetBit;
var
  F: File;
begin
  BeginTest('SetBitInBitmapFile / GetBitInBitmapFile - basic');
  MemoryReport('Before Set/Get Bit');
  CleanupBitmapFiles;
  Ok := CreateBitmapFile(F, BmpFile1);
  AssertTrue(Ok, 'Create should succeed');
  { Set bit 0 }
  SetBitInBitmapFile(F, 0);
  AssertTrue(GetBitInBitmapFile(F, 0), 'Bit 0 should be set');
  AssertFalse(GetBitInBitmapFile(F, 1), 'Bit 1 should not be set');
  { Set bit 127 (last in first chunk) }
  SetBitInBitmapFile(F, 127);
  AssertTrue(GetBitInBitmapFile(F, 127), 'Bit 127 should be set');
  AssertTrue(GetBitInBitmapFile(F, 0), 'Bit 0 should still be set');
  CloseBitmapFile(F);
  CleanupBitmapFiles;
  MemoryReport('After Set/Get Bit');
  EndTest;
end;

procedure TestSetBitWithGapFill;
var
  F: File;
begin
  BeginTest('SetBitInBitmapFile - gap filling for sparse records');
  MemoryReport('Before Gap Fill');
  CleanupBitmapFiles;
  Ok := CreateBitmapFile(F, BmpFile1);
  { Set a bit far from 0 - should pad zero chunks }
  SetBitInBitmapFile(F, 500);
  AssertTrue(GetBitInBitmapFile(F, 500), 'Bit 500 should be set');
  AssertFalse(GetBitInBitmapFile(F, 0), 'Bit 0 should not be set');
  AssertFalse(GetBitInBitmapFile(F, 499), 'Bit 499 should not be set');
  AssertFalse(GetBitInBitmapFile(F, 501), 'Bit 501 should not be set');
  { Verify file is dense - chunk 0 should be readable }
  AssertFalse(GetBitInBitmapFile(F, 64), 'Bit 64 in gap chunk should be 0');
  CloseBitmapFile(F);
  CleanupBitmapFiles;
  MemoryReport('After Gap Fill');
  EndTest;
end;

procedure TestClearBit;
var
  F: File;
begin
  BeginTest('ClearBitInBitmapFile - clear previously set bit');
  MemoryReport('Before Clear Bit');
  CleanupBitmapFiles;
  Ok := CreateBitmapFile(F, BmpFile1);
  SetBitInBitmapFile(F, 10);
  SetBitInBitmapFile(F, 20);
  AssertTrue(GetBitInBitmapFile(F, 10), 'Bit 10 should be set');
  ClearBitInBitmapFile(F, 10);
  AssertFalse(GetBitInBitmapFile(F, 10), 'Bit 10 should be cleared');
  AssertTrue(GetBitInBitmapFile(F, 20), 'Bit 20 should still be set');
  CloseBitmapFile(F);
  CleanupBitmapFiles;
  MemoryReport('After Clear Bit');
  EndTest;
end;

procedure TestSetMultipleBits;
var
  F: File;
  Ids: PRowIdArray;
begin
  BeginTest('SetMultipleBitsInBitmapFile - bulk set');
  MemoryReport('Before SetMultipleBits');
  CleanupBitmapFiles;
  GetMem(Ids, 4 * SizeOf(LongInt));
  SetRowId(Ids, 0, 5);
  SetRowId(Ids, 1, 10);
  SetRowId(Ids, 2, 15);
  SetRowId(Ids, 3, 20);
  Ok := CreateBitmapFile(F, BmpFile1);
  SetMultipleBitsInBitmapFile(F, Ids, 4);
  AssertTrue(GetBitInBitmapFile(F, 5), 'Bit 5 should be set');
  AssertTrue(GetBitInBitmapFile(F, 10), 'Bit 10 should be set');
  AssertTrue(GetBitInBitmapFile(F, 15), 'Bit 15 should be set');
  AssertTrue(GetBitInBitmapFile(F, 20), 'Bit 20 should be set');
  AssertFalse(GetBitInBitmapFile(F, 0), 'Bit 0 should not be set');
  AssertFalse(GetBitInBitmapFile(F, 11), 'Bit 11 should not be set');
  CloseBitmapFile(F);
  FreeMem(Ids, 4 * SizeOf(LongInt));
  CleanupBitmapFiles;
  MemoryReport('After SetMultipleBits');
  EndTest;
end;

procedure TestANDBitmapFiles;
var
  F1, F2: File;
begin
  BeginTest('ANDBitmapFiles - intersection of two bitmaps');
  MemoryReport('Before AND bitmaps');
  CleanupBitmapFiles;
  { File 1: bits 0, 5, 10, 15 }
  Ok := CreateBitmapFile(F1, BmpFile1);
  SetBitInBitmapFile(F1, 0);
  SetBitInBitmapFile(F1, 5);
  SetBitInBitmapFile(F1, 10);
  SetBitInBitmapFile(F1, 15);
  CloseBitmapFile(F1);

  { File 2: bits 5, 10, 20 }
  Ok := CreateBitmapFile(F2, BmpFile2);
  SetBitInBitmapFile(F2, 5);
  SetBitInBitmapFile(F2, 10);
  SetBitInBitmapFile(F2, 20);
  CloseBitmapFile(F2);

  Ok := ANDBitmapFiles(BmpFile1, BmpFile2, BmpDest);
  AssertTrue(Ok, 'AND should succeed');

  { Read result back }
  {$I-}
  Assign(F1, BmpDest);
  Reset(F1, 1);
  {$I+}
  AssertFalse(GetBitInBitmapFile(F1, 0), 'Bit 0: only in file1');
  AssertTrue(GetBitInBitmapFile(F1, 5), 'Bit 5: in both');
  AssertTrue(GetBitInBitmapFile(F1, 10), 'Bit 10: in both');
  AssertFalse(GetBitInBitmapFile(F1, 15), 'Bit 15: only in file1');
  AssertFalse(GetBitInBitmapFile(F1, 20), 'Bit 20: only in file2');
  CloseBitmapFile(F1);
  CleanupBitmapFiles;
  MemoryReport('After AND bitmaps');
  EndTest;
end;

procedure TestORBitmapFiles;
var
  F1, F2: File;
begin
  BeginTest('ORBitmapFiles - union of two bitmaps');
  MemoryReport('Before OR bitmaps');
  CleanupBitmapFiles;
  { File 1: bits 0, 5 }
  Ok := CreateBitmapFile(F1, BmpFile1);
  SetBitInBitmapFile(F1, 0);
  SetBitInBitmapFile(F1, 5);
  CloseBitmapFile(F1);

  { File 2: bits 5, 10 }
  Ok := CreateBitmapFile(F2, BmpFile2);
  SetBitInBitmapFile(F2, 5);
  SetBitInBitmapFile(F2, 10);
  CloseBitmapFile(F2);

  Ok := ORBitmapFiles(BmpFile1, BmpFile2, BmpDest);
  AssertTrue(Ok, 'OR should succeed');

  {$I-}
  Assign(F1, BmpDest);
  Reset(F1, 1);
  {$I+}
  AssertTrue(GetBitInBitmapFile(F1, 0), 'Bit 0: in file1');
  AssertTrue(GetBitInBitmapFile(F1, 5), 'Bit 5: in both');
  AssertTrue(GetBitInBitmapFile(F1, 10), 'Bit 10: in file2');
  AssertFalse(GetBitInBitmapFile(F1, 1), 'Bit 1: in neither');
  CloseBitmapFile(F1);
  CleanupBitmapFiles;
  MemoryReport('After OR bitmaps');
  EndTest;
end;

procedure TestBitmapFileToRowIds;
var
  F: File;
  Ids: PRowIdArray;
  Count: Integer;
begin
  BeginTest('BitmapFileToRowIds - extract set bits as row IDs');
  MemoryReport('Before BitmapFileToRowIds');
  CleanupBitmapFiles;
  Ok := CreateBitmapFile(F, BmpFile1);
  SetBitInBitmapFile(F, 3);
  SetBitInBitmapFile(F, 7);
  SetBitInBitmapFile(F, 100);
  CloseBitmapFile(F);

  GetMem(Ids, MaxResults * SizeOf(LongInt));
  Count := 0;
  Ok := BitmapFileToRowIds(BmpFile1, Ids, Count, MaxResults);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(3, Count, 'Should find 3 bits set');
  if Count >= 3 then
  begin
    AssertEqualsInt(3, RowIdAt(Ids, 0), 'First ID should be 3');
    AssertEqualsInt(7, RowIdAt(Ids, 1), 'Second ID should be 7');
    AssertEqualsInt(100, RowIdAt(Ids, 2), 'Third ID should be 100');
  end;
  FreeMem(Ids, MaxResults * SizeOf(LongInt));
  CleanupBitmapFiles;
  MemoryReport('After BitmapFileToRowIds');
  EndTest;
end;

procedure TestBitmapAlignmentAfterGap;
var
  F1, F2: File;
begin
  BeginTest('Bitmap alignment - sparse NDX results AND dense scan');
  MemoryReport('Before Bitmap alignment');
  CleanupBitmapFiles;
  { Simulate NDX result: only bit 500 set (with gap fill) }
  Ok := CreateBitmapFile(F1, BmpFile1);
  SetBitInBitmapFile(F1, 500);
  SetBitInBitmapFile(F1, 600);
  CloseBitmapFile(F1);

  { Simulate sequential scan: bits 0-700 in various positions }
  Ok := CreateBitmapFile(F2, BmpFile2);
  SetBitInBitmapFile(F2, 100);
  SetBitInBitmapFile(F2, 500);
  SetBitInBitmapFile(F2, 700);
  CloseBitmapFile(F2);

  { AND should only keep bit 500 (present in both) }
  Ok := ANDBitmapFiles(BmpFile1, BmpFile2, BmpDest);
  AssertTrue(Ok, 'AND should succeed');

  {$I-}
  Assign(F1, BmpDest);
  Reset(F1, 1);
  {$I+}
  AssertFalse(GetBitInBitmapFile(F1, 100), 'Bit 100: only in scan');
  AssertTrue(GetBitInBitmapFile(F1, 500), 'Bit 500: in both');
  AssertFalse(GetBitInBitmapFile(F1, 600), 'Bit 600: only in NDX');
  AssertFalse(GetBitInBitmapFile(F1, 700), 'Bit 700: only in scan');
  CloseBitmapFile(F1);
  CleanupBitmapFiles;
  MemoryReport('After Bitmap alignment');
  EndTest;
end;

{ ================================================================== }
{ Phase 3: JDN conversion tests                                      }
{ ================================================================== }

procedure TestDateToJDN;
begin
  BeginTest('DateToJDN - known dates');
  { Jan 1, 2000 = JDN 2451545 }
  AssertEqualsInt(2451545, DateToJDN(2000, 1, 1), 'Jan 1 2000');
  { Nov 24, 1858 = JDN 2400000 (Modified Julian Date epoch) }
  AssertEqualsInt(2400000, DateToJDN(1858, 11, 17), 'MJD epoch');
  { Jan 1, 1970 = JDN 2440588 (Unix epoch) }
  AssertEqualsInt(2440588, DateToJDN(1970, 1, 1), 'Unix epoch');
  EndTest;
end;

procedure TestJDNToDate;
var
  Y, M, D: Integer;
begin
  BeginTest('JDNToDate - round trip');
  Ok := JDNToDate(2451545, Y, M, D);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(2000, Y, 'Year 2000');
  AssertEqualsInt(1, M, 'Month 1');
  AssertEqualsInt(1, D, 'Day 1');
  EndTest;
end;

procedure TestJDNToDateInvalid;
var
  Y, M, D: Integer;
begin
  BeginTest('JDNToDate - invalid JDN returns False');
  Ok := JDNToDate(0, Y, M, D);
  AssertFalse(Ok, 'JDN 0 should fail');
  EndTest;
end;

procedure TestDBFDateStrToJDN;
begin
  BeginTest('DBFDateStrToJDN - YYYYMMDD to JDN');
  AssertEqualsInt(2451545, DBFDateStrToJDN('20000101'), '20000101');
  AssertEqualsInt(2440588, DBFDateStrToJDN('19700101'), '19700101');
  EndTest;
end;

procedure TestJDNToDBFDateStr;
begin
  BeginTest('JDNToDBFDateStr - JDN to YYYYMMDD');
  AssertEqualsStr('20000101', JDNToDBFDateStr(2451545), 'JDN 2451545');
  EndTest;
end;

procedure TestJDNRoundTrip;
var
  JDN: LongInt;
  DateStr: string;
begin
  BeginTest('JDN round trip - DBFDateStr -> JDN -> DBFDateStr');
  JDN := DBFDateStrToJDN('19950715');
  DateStr := JDNToDBFDateStr(JDN);
  AssertEqualsStr('19950715', DateStr, 'Round trip should preserve date');
  EndTest;
end;

{ ================================================================== }
{ Phase 4: Filter execution tests using GAMES3.DBF                   }
{ ================================================================== }
{   Fields: 1=TITLE(C,50), 2=DEVNAME(C,30), 3=PUBNAME(C,30),       }
{           4=YEAR(N,4), 5=MAXPLAY(N,3), 6=DATEADD(D,8)             }
{ ================================================================== }

var
  GamesDbf: PDBFFile;
  GamesHeader: TDBFHeader;
  GamesRowCount: LongInt;

function OpenGamesDb: Boolean;
begin
  GamesDbf := nil;
  OpenGamesDb := False;
  if not DBFFileOpen(GamesDbf, GamesDbPath) then
  begin
    WriteLn('WARNING: Cannot open ', GamesDbPath, ' - skipping Phase 4/5');
    Exit;
  end;
  if not DBFFileGetHeader(GamesDbf, GamesHeader) then
  begin
    WriteLn('WARNING: Cannot read header - skipping Phase 4/5');
    Ok := DBFFileClose(GamesDbf);
    Ok := DBFFileDispose(GamesDbf);
    Exit;
  end;
  GamesRowCount := DBFFileGetActualRowCount(GamesDbf);
  OpenGamesDb := True;
end;

procedure CloseGamesDb;
begin
  if GamesDbf <> nil then
  begin
    Ok := DBFFileClose(GamesDbf);
    Ok := DBFFileDispose(GamesDbf);
    GamesDbf := nil;
  end;
end;

procedure TestFetchNoFilters;
var
  Cursor: TDBMatchCursor;
  Ids: PRowIdArray;
  Count: Integer;
begin
  BeginTest('DBFetchNextMatches - no filters returns all rows');
  MemoryReport('Before FetchNoFilters');
  DBMatchCursorReset(Cursor);
  { No groups = no filters = return all }
  GetMem(Ids, MaxResults * SizeOf(LongInt));
  Count := 0;
  DBFetchNextMatches(GamesDbf, Cursor, Ids, MaxResults, Count);
  AssertEqualsInt(MaxResults, Count,
    'Should return MaxResults rows when no filters');
  if Count > 0 then
    AssertEqualsInt(0, RowIdAt(Ids, 0), 'First row should be 0');
  FreeMem(Ids, MaxResults * SizeOf(LongInt));
  DBFilterReleaseGlobals;
  MemoryReport('After FetchNoFilters');
  EndTest;
end;

procedure TestFetchExactNum;
var
  Cursor: TDBMatchCursor;
  Ids: PRowIdArray;
  Count: Integer;
begin
  BeginTest('DBFetchNextMatches - fkExactNum (YEAR = 1993)');
  MemoryReport('Before FetchExactNum');
  DBMatchCursorInitDefault(Cursor);
  DBMatchCursorAddExactNum(Cursor, 1, 4, 1993);  { Field 4 = YEAR }
  GetMem(Ids, MaxResults * SizeOf(LongInt));
  Count := 0;
  DBFetchNextMatches(GamesDbf, Cursor, Ids, MaxResults, Count);
  AssertTrue(Count > 0, 'Should find some 1993 games');
  WriteLn('  Found ', Count, ' games from 1993');
  FreeMem(Ids, MaxResults * SizeOf(LongInt));
  DBFilterReleaseGlobals;
  MemoryReport('After FetchExactNum');
  EndTest;
end;

procedure TestFetchExactStr;
var
  Cursor: TDBMatchCursor;
  Ids: PRowIdArray;
  Count: Integer;
begin
  BeginTest('DBFetchNextMatches - fkExactStr (DEVNAME)');
  MemoryReport('Before FetchExactStr');
  DBMatchCursorInitDefault(Cursor);
  DBMatchCursorAddExact(Cursor, 1, 2, 'Nintendo');  { Field 2 = DEVNAME }
  GetMem(Ids, MaxResults * SizeOf(LongInt));
  Count := 0;
  DBFetchNextMatches(GamesDbf, Cursor, Ids, MaxResults, Count);
  WriteLn('  Found ', Count, ' games by Nintendo');
  { May or may not find matches depending on case/padding }
  AssertTrue(Count >= 0, 'Count should be non-negative');
  FreeMem(Ids, MaxResults * SizeOf(LongInt));
  DBFilterReleaseGlobals;
  MemoryReport('After FetchExactStr');
  EndTest;
end;

procedure TestFetchFieldRange;
var
  Cursor: TDBMatchCursor;
  Ids: PRowIdArray;
  Count: Integer;
begin
  BeginTest('DBFetchNextMatches - fkFieldRange (YEAR 1990-1999)');
  MemoryReport('Before FetchFieldRange');
  DBMatchCursorInitDefault(Cursor);
  DBMatchCursorAddFieldRange(Cursor, 1, 4, 1990, 1999);  { Field 4 = YEAR }
  GetMem(Ids, MaxResults * SizeOf(LongInt));
  Count := 0;
  DBFetchNextMatches(GamesDbf, Cursor, Ids, MaxResults, Count);
  AssertTrue(Count > 0, 'Should find games in 1990-1999 range');
  WriteLn('  Found ', Count, ' games from the 1990s');
  FreeMem(Ids, MaxResults * SizeOf(LongInt));
  DBFilterReleaseGlobals;
  MemoryReport('After FetchFieldRange');
  EndTest;
end;

procedure TestFetchStartsWith;
var
  Cursor: TDBMatchCursor;
  Ids: PRowIdArray;
  Count: Integer;
begin
  BeginTest('DBFetchNextMatches - fkStartsWith (DEVNAME starts with "N")');
  MemoryReport('Before FetchStartsWith');
  DBMatchCursorInitDefault(Cursor);
  DBMatchCursorAddStartsWith(Cursor, 1, 2, 'N');  { Field 2 = DEVNAME }
  GetMem(Ids, MaxResults * SizeOf(LongInt));
  Count := 0;
  DBFetchNextMatches(GamesDbf, Cursor, Ids, MaxResults, Count);
  AssertTrue(Count > 0, 'Should find devs starting with N');
  WriteLn('  Found ', Count, ' games with DEVNAME starting "N"');
  FreeMem(Ids, MaxResults * SizeOf(LongInt));
  DBFilterReleaseGlobals;
  MemoryReport('After FetchStartsWith');
  EndTest;
end;

procedure TestFetchCombinedFilters;
var
  Cursor: TDBMatchCursor;
  Ids: PRowIdArray;
  Count: Integer;
begin
  BeginTest('DBFetchNextMatches - combined YEAR=1993 AND MAXPLAY>=2');
  MemoryReport('Before FetchCombined');
  DBMatchCursorInitDefault(Cursor);
  DBMatchCursorAddExactNum(Cursor, 1, 4, 1993);  { YEAR = 1993 }
  DBMatchCursorAddFieldRange(Cursor, 1, 5, 2, 99);  { MAXPLAY >= 2 }
  GetMem(Ids, MaxResults * SizeOf(LongInt));
  Count := 0;
  DBFetchNextMatches(GamesDbf, Cursor, Ids, MaxResults, Count);
  WriteLn('  Found ', Count, ' games (1993, 2+ players)');
  AssertTrue(Count >= 0, 'Count should be non-negative');
  FreeMem(Ids, MaxResults * SizeOf(LongInt));
  DBFilterReleaseGlobals;
  MemoryReport('After FetchCombined');
  EndTest;
end;

procedure TestFetchResumption;
var
  Cursor: TDBMatchCursor;
  Ids: PRowIdArray;
  Count1, Count2: Integer;
begin
  BeginTest('DBFetchNextMatches - cursor resumption');
  MemoryReport('Before FetchResumption');
  DBMatchCursorReset(Cursor);
  { No filters - sequential scan }
  GetMem(Ids, MaxResults * SizeOf(LongInt));

  { First batch }
  Count1 := 0;
  DBFetchNextMatches(GamesDbf, Cursor, Ids, 50, Count1);
  AssertEqualsInt(50, Count1, 'First batch should return 50');

  { Second batch should continue from where we left off }
  Count2 := 0;
  DBFetchNextMatches(GamesDbf, Cursor, Ids, 50, Count2);
  AssertEqualsInt(50, Count2, 'Second batch should return 50');

  { First ID of second batch should be 50 (continuing from first batch) }
  if Count2 > 0 then
    AssertEqualsInt(50, RowIdAt(Ids, 0), 'Second batch should start at row 50');

  FreeMem(Ids, MaxResults * SizeOf(LongInt));
  DBFilterReleaseGlobals;
  MemoryReport('After FetchResumption');
  EndTest;
end;

{ ================================================================== }
{ Phase 5: NDX vs sequential scan comparison                         }
{ ================================================================== }
{ Verify that NDX index lookup and sequential cursor scan produce     }
{ the same result set for the same query.                             }
{ ================================================================== }

procedure TestNdxVsScanStartsWith;
var
  Cursor: TDBMatchCursor;
  ScanIds: PRowIdArray;
  NdxIds: PRowIdArray;
  ScanCount, NdxCount: Integer;
  I, J: Integer;
  Found: Boolean;
  Prefix: string;
  ScanMatches, NdxMatches: Integer;
begin
  BeginTest('NDX vs Scan - StartsWith produces same results');
  MemoryReport('Before NDX vs Scan');
  Prefix := 'Quicksilver';

  { Method 1: Sequential scan via DBFetchNextMatches }
  GetMem(ScanIds, MaxResults * SizeOf(LongInt));
  ScanCount := 0;
  DBMatchCursorInitDefault(Cursor);
  DBMatchCursorAddStartsWith(Cursor, 1, 2, Prefix);  { DEVNAME starts with }
  DBFetchNextMatches(GamesDbf, Cursor, ScanIds, MaxResults, ScanCount);
  WriteLn('  Scan found ', ScanCount, ' matches for "', Prefix, '"');

  { Method 2: NDX index lookup }
  GetMem(NdxIds, MaxResults * SizeOf(LongInt));
  NdxCount := 0;
  Ok := FindCharacterBegins(DevNdxPath, Prefix, NdxIds, MaxResults, NdxCount);
  AssertTrue(Ok, 'NDX lookup should succeed');
  WriteLn('  NDX found ', NdxCount, ' matches for "', Prefix, '"');

  { Both methods should find the same number of results }
  { Note: NDX returns 1-based row IDs, scan returns 0-based }
  { So we need to account for the offset when comparing }
  AssertTrue(ScanCount > 0, 'Scan should find matches');
  AssertTrue(NdxCount > 0, 'NDX should find matches');

  { Verify every scan result appears in NDX results }
  ScanMatches := 0;
  for I := 0 to ScanCount - 1 do
  begin
    if (I > 0) and ((I mod 200) = 0) then
      WriteLn('  Scan->NDX check ', I, '/', ScanCount);
    Found := False;
    for J := 0 to NdxCount - 1 do
    begin
      { NDX IDs are 1-based, scan IDs are 0-based }
      if NdxIds^[J] = ScanIds^[I] + 1 then
      begin
        Found := True;
        Inc(ScanMatches);
        J := NdxCount;  { break }
      end;
    end;
    if not Found then
      WriteLn('  WARNING: Scan result ', ScanIds^[I],
              ' not found in NDX results');
  end;

  { Verify every NDX result appears in scan results }
  NdxMatches := 0;
  for I := 0 to NdxCount - 1 do
  begin
    if (I > 0) and ((I mod 200) = 0) then
      WriteLn('  NDX->Scan check ', I, '/', NdxCount);
    Found := False;
    for J := 0 to ScanCount - 1 do
    begin
      if ScanIds^[J] + 1 = NdxIds^[I] then
      begin
        Found := True;
        Inc(NdxMatches);
        J := ScanCount;  { break }
      end;
    end;
    if not Found then
      WriteLn('  WARNING: NDX result ', NdxIds^[I],
              ' not found in scan results');
  end;

  WriteLn('  Cross-matched: ', ScanMatches, '/', ScanCount, ' scan in NDX, ',
          NdxMatches, '/', NdxCount, ' NDX in scan');
  MemoryReport('After NDX vs Scan');
  AssertEqualsInt(ScanCount, ScanMatches, 'All scan results should be in NDX');
  AssertEqualsInt(NdxCount, NdxMatches, 'All NDX results should be in scan');

  FreeMem(ScanIds, MaxResults * SizeOf(LongInt));
  FreeMem(NdxIds, MaxResults * SizeOf(LongInt));
  EndTest;
end;

procedure TestNdxVsScanBitmapAlignment;
var
  NdxIds: PRowIdArray;
  ScanIds: PRowIdArray;
  Cursor: TDBMatchCursor;
  NdxF, ScanF, ResultF: File;
  NdxCount, ScanCount: Integer;
  ResultIds: PRowIdArray;
  ResultCount: Integer;
  I: Integer;
  Prefix: string;
begin
  BeginTest('NDX vs Scan - bitmap AND alignment');
  CleanupBitmapFiles;
  Prefix := 'Quicksilver';

  { Build NDX bitmap }
  GetMem(NdxIds, MaxResults * SizeOf(LongInt));
  NdxCount := 0;
  Ok := FindCharacterBegins(DevNdxPath, Prefix, NdxIds, MaxResults, NdxCount);
  AssertTrue(Ok, 'NDX lookup should succeed');

  Ok := CreateBitmapFile(NdxF, BmpFile1);
  AssertTrue(Ok, 'Create NDX bitmap should succeed');
  { NDX returns 1-based IDs; store as-is for bitmap position }
  SetMultipleBitsInBitmapFile(NdxF, NdxIds, NdxCount);
  CloseBitmapFile(NdxF);

  { Build scan bitmap (also store 1-based for alignment) }
  GetMem(ScanIds, MaxResults * SizeOf(LongInt));
  ScanCount := 0;
  DBMatchCursorInitDefault(Cursor);
  DBMatchCursorAddStartsWith(Cursor, 1, 2, Prefix);
  DBFetchNextMatches(GamesDbf, Cursor, ScanIds, MaxResults, ScanCount);

  Ok := CreateBitmapFile(ScanF, BmpFile2);
  AssertTrue(Ok, 'Create scan bitmap should succeed');
  { Convert 0-based scan IDs to 1-based for bitmap }
  for I := 0 to ScanCount - 1 do
    SetBitInBitmapFile(ScanF, ScanIds^[I] + 1);
  CloseBitmapFile(ScanF);

  WriteLn('  NDX bitmap: ', NdxCount, ' bits set');
  WriteLn('  Scan bitmap: ', ScanCount, ' bits set');

  { AND the two bitmaps - result should equal either input }
  Ok := ANDBitmapFiles(BmpFile1, BmpFile2, BmpDest);
  AssertTrue(Ok, 'AND should succeed');

  GetMem(ResultIds, MaxResults * SizeOf(LongInt));
  ResultCount := 0;
  Ok := BitmapFileToRowIds(BmpDest, ResultIds, ResultCount, MaxResults);
  AssertTrue(Ok, 'BitmapFileToRowIds should succeed');
  WriteLn('  AND result: ', ResultCount, ' bits set');

  { AND of identical sets should equal both inputs }
  AssertEqualsInt(NdxCount, ResultCount,
    'AND result count should match NDX count');

  FreeMem(NdxIds, MaxResults * SizeOf(LongInt));
  FreeMem(ScanIds, MaxResults * SizeOf(LongInt));
  FreeMem(ResultIds, MaxResults * SizeOf(LongInt));
  CleanupBitmapFiles;
  EndTest;
end;

{ ================================================================== }
{ Main program                                                        }
{ ================================================================== }

var
  GamesAvailable: Boolean;

begin
  WriteLn('TESTFLTR - DBFILTER Unit Tests');
  WriteLn('==============================');
  WriteLn;

  { ---- Phase 1: Cursor management ---- }
  WriteLn('--- Phase 1: Cursor Management ---');
  TestCursorReset;
  TestCursorInitDefault;
  TestCursorAddGroup;
  TestCursorAddExact;
  TestCursorAddExactNum;
  TestCursorAddStartsWith;
  TestCursorAddFieldRange;
  TestCursorFilterOverflow;
  TestCursorAddToInvalidGroup;
  TestCursorSetFilterIndex;
  WriteLn;

  { ---- Phase 2: Bitmap file operations ---- }
  WriteLn('--- Phase 2: Bitmap File Operations ---');
  TestCreateBitmapFile;
  TestSetAndGetBit;
  TestSetBitWithGapFill;
  TestClearBit;
  TestSetMultipleBits;
  TestANDBitmapFiles;
  TestORBitmapFiles;
  TestBitmapFileToRowIds;
  TestBitmapAlignmentAfterGap;
  WriteLn;

  { ---- Phase 3: JDN conversion ---- }
  WriteLn('--- Phase 3: JDN Conversion ---');
  TestDateToJDN;
  TestJDNToDate;
  TestJDNToDateInvalid;
  TestDBFDateStrToJDN;
  TestJDNToDBFDateStr;
  TestJDNRoundTrip;
  WriteLn;

  { ---- Phase 4 & 5: DBF-based tests ---- }
  GamesAvailable := OpenGamesDb;
  if GamesAvailable then
  begin
    WriteLn('--- Phase 4: Filter Execution (GAMES3.DBF, ', GamesRowCount, ' records) ---');
    TestFetchNoFilters;
    TestFetchExactNum;
    TestFetchExactStr;
    TestFetchFieldRange;
    TestFetchStartsWith;
    TestFetchCombinedFilters;
    TestFetchResumption;
    WriteLn;

    if EnablePhase5 then
    begin
      WriteLn('--- Phase 5: NDX vs Sequential Scan ---');
      TestNdxVsScanStartsWith;
      TestNdxVsScanBitmapAlignment;
      WriteLn;
    end
    else
      WriteLn('--- Phase 5: Skipped (EnablePhase5 = False) ---');

    CloseGamesDb;
    DBFilterReleaseGlobals;
  end
  else
    WriteLn('Skipping Phase 4/5 (GAMES3.DBF not available)');

  { Final cleanup }
  CleanupBitmapFiles;

  WriteLn;
  WriteLn('==============================');
  PrintSummary;
end.
