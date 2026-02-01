{ TESTIDX.PAS - Comprehensive tests for DBFINDEX module }

program TestIdxProgram;

{$N+}
{$M 32768,0,131072}  { Stack: 32KB, Heap: 128KB }

uses Assert, DBFUTIL, DBFINDEX;

const
  MaxResults = 500;
  SamplesDir = 'samples\';

  { Character index files }
  CharNdx  = SamplesDir + 'DEVNAME3.NDX';
  TitleNdx = SamplesDir + 'TITLE3.NDX';
  UpperNdx = SamplesDir + 'DEVNAMEU.NDX';

  { Numeric index file }
  YearNdx = SamplesDir + 'YEAR3.NDX';

  { Date index file }
  DateNdx = SamplesDir + 'DATEADD3.NDX';

var
  RowIds: PRowIdArray;
  Count: Integer;
  LongCount: LongInt;
  TestResult: Boolean;
  I: Integer;

function RowIdAt(Ids: PRowIdArray; Index: Integer): LongInt;
begin
  RowIdAt := Ids^[Index];
end;

{ ================================================================ }
{  FindCharacterExact tests                                        }
{ ================================================================ }

procedure TestCharExactNilRowIds;
begin
  BeginTest('FindCharacterExact - nil RowIds returns False');
  Count := 0;
  TestResult := FindCharacterExact(CharNdx, 'test', nil, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for nil RowIds');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

procedure TestCharExactZeroMaxCount;
begin
  BeginTest('FindCharacterExact - zero MaxCount returns False');
  Count := 0;
  TestResult := FindCharacterExact(CharNdx, 'test', RowIds, 0, Count);
  AssertFalse(TestResult, 'Should return False for MaxCount=0');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

procedure TestCharExactBadFile;
begin
  BeginTest('FindCharacterExact - bad file returns False');
  Count := 0;
  TestResult := FindCharacterExact('NOEXIST.NDX', 'test', RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for missing file');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

procedure TestCharExactKnownMatch;
begin
  BeginTest('FindCharacterExact - known exact match');
  Count := 0;
  TestResult := FindCharacterExact(CharNdx,
    'Quicksilver Software, Inc.', RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count > 0, 'Should find at least 1 match');
  AssertTrue(RowIdAt(RowIds, 0) > 0, 'Record number should be positive');
  EndTest;
end;

procedure TestCharExactNoMatch;
begin
  BeginTest('FindCharacterExact - no match returns 0 count');
  Count := 0;
  TestResult := FindCharacterExact(CharNdx,
    'ZZZZZ_NONEXISTENT_COMPANY', RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 matches');
  EndTest;
end;

procedure TestCharExactMaxCountLimit;
begin
  BeginTest('FindCharacterExact - MaxCount limits results');
  { First find with large buffer to get full count }
  Count := 0;
  TestResult := FindCharacterExact(CharNdx,
    'Quicksilver Software, Inc.', RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Full search should succeed');

  { Now limit to 1 fewer than total (if multiple) or just 1 }
  Count := 0;
  TestResult := FindCharacterExact(CharNdx,
    'Quicksilver Software, Inc.', RowIds, 1, Count);
  AssertTrue(TestResult, 'Limited search should succeed');
  AssertTrue(Count <= 1, 'Should return at most 1 result');
  EndTest;
end;

{ ================================================================ }
{  FindCharacterBegins tests                                       }
{ ================================================================ }

procedure TestCharBeginsNilRowIds;
begin
  BeginTest('FindCharacterBegins - nil RowIds returns False');
  Count := 0;
  TestResult := FindCharacterBegins(CharNdx, 'test', nil, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for nil RowIds');
  EndTest;
end;

procedure TestCharBeginsZeroMaxCount;
begin
  BeginTest('FindCharacterBegins - zero MaxCount returns False');
  Count := 0;
  TestResult := FindCharacterBegins(CharNdx, 'test', RowIds, 0, Count);
  AssertFalse(TestResult, 'Should return False for MaxCount=0');
  EndTest;
end;

procedure TestCharBeginsBadFile;
begin
  BeginTest('FindCharacterBegins - bad file returns False');
  Count := 0;
  TestResult := FindCharacterBegins('NOEXIST.NDX', 'test',
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for missing file');
  EndTest;
end;

procedure TestCharBeginsCosmi;
begin
  BeginTest('FindCharacterBegins - prefix Cosmi finds 2+');
  Count := 0;
  TestResult := FindCharacterBegins(CharNdx, 'Cosmi',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count >= 2, 'Should find at least 2 matches for Cosmi');
  WriteLn('  Found ', Count, ' matches for prefix Cosmi');
  EndTest;
end;

procedure TestCharBeginsKing;
begin
  BeginTest('FindCharacterBegins - prefix King finds 5+');
  Count := 0;
  TestResult := FindCharacterBegins(TitleNdx, 'King',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count >= 5, 'Should find at least 5 matches for King');
  WriteLn('  Found ', Count, ' matches for prefix King');
  EndTest;
end;

procedure TestCharBeginsSIE;
begin
  BeginTest('FindCharacterBegins - prefix SIE (upper index) finds 3+');
  Count := 0;
  TestResult := FindCharacterBegins(UpperNdx, 'SIE',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count >= 3, 'Should find at least 3 matches for SIE');
  WriteLn('  Found ', Count, ' matches for prefix SIE');
  EndTest;
end;

procedure TestCharBeginsNoMatch;
begin
  BeginTest('FindCharacterBegins - no match returns 0 count');
  Count := 0;
  TestResult := FindCharacterBegins(CharNdx, 'ZZZZZ',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 matches');
  EndTest;
end;

procedure TestCharBeginsMaxCountLimit;
begin
  BeginTest('FindCharacterBegins - MaxCount limits results');
  Count := 0;
  TestResult := FindCharacterBegins(TitleNdx, 'King',
    RowIds, 2, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count <= 2, 'Should return at most 2 results');
  AssertTrue(Count > 0, 'Should find at least 1 result');
  EndTest;
end;

procedure TestCharBeginsAllRecords;
begin
  BeginTest('FindCharacterBegins - single letter finds many');
  Count := 0;
  TestResult := FindCharacterBegins(CharNdx, 'A',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count > 0, 'Should find records starting with A');
  WriteLn('  Found ', Count, ' matches starting with A');
  EndTest;
end;

{ ================================================================ }
{  FindNumberExact tests                                           }
{ ================================================================ }

procedure TestNumExactNilRowIds;
begin
  BeginTest('FindNumberExact - nil RowIds returns False');
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 1981, nil, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for nil RowIds');
  EndTest;
end;

procedure TestNumExactZeroMaxCount;
begin
  BeginTest('FindNumberExact - zero MaxCount returns False');
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 1981, RowIds, 0, Count);
  AssertFalse(TestResult, 'Should return False for MaxCount=0');
  EndTest;
end;

procedure TestNumExactBadFile;
begin
  BeginTest('FindNumberExact - bad file returns False');
  Count := 0;
  TestResult := FindNumberExact('NOEXIST.NDX', 1981,
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for missing file');
  EndTest;
end;

procedure TestNumExact1981;
begin
  BeginTest('FindNumberExact - year 1981 finds 25');
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 1981,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(25, Count, 'Should find 25 records for year 1981');
  { Verify all record IDs are positive }
  for I := 0 to Count - 1 do
    AssertTrue(RowIdAt(RowIds, I) > 0, 'Record ID should be positive');
  EndTest;
end;

procedure TestNumExactNoMatch;
begin
  BeginTest('FindNumberExact - no match');
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 9999,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 records for year 9999');
  EndTest;
end;

procedure TestNumExactMaxCountLimit;
begin
  BeginTest('FindNumberExact - MaxCount limits results');
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 1981, RowIds, 5, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(5, Count, 'Should return exactly 5 results');
  EndTest;
end;

procedure TestNumExactMultipleYears;
begin
  BeginTest('FindNumberExact - verify multiple year counts');
  { 1982 = 124 }
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 1982,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed for 1982');
  AssertEqualsInt(124, Count, 'Should find 124 records for year 1982');

  { 1983 = 165 }
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 1983,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed for 1983');
  AssertEqualsInt(165, Count, 'Should find 165 records for year 1983');

  { 1984 = 160 }
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 1984,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed for 1984');
  AssertEqualsInt(160, Count, 'Should find 160 records for year 1984');
  EndTest;
end;

{ ================================================================ }
{  FindNumberRange tests                                           }
{ ================================================================ }

procedure TestNumRangeNilRowIds;
begin
  BeginTest('FindNumberRange - nil RowIds returns False');
  Count := 0;
  TestResult := FindNumberRange(YearNdx, 1980, 1985,
    nil, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for nil RowIds');
  EndTest;
end;

procedure TestNumRangeZeroMaxCount;
begin
  BeginTest('FindNumberRange - zero MaxCount returns False');
  Count := 0;
  TestResult := FindNumberRange(YearNdx, 1980, 1985,
    RowIds, 0, Count);
  AssertFalse(TestResult, 'Should return False for MaxCount=0');
  EndTest;
end;

procedure TestNumRangeBadFile;
begin
  BeginTest('FindNumberRange - bad file returns False');
  Count := 0;
  TestResult := FindNumberRange('NOEXIST.NDX', 1980, 1985,
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for missing file');
  EndTest;
end;

procedure TestNumRangeInverted;
begin
  BeginTest('FindNumberRange - min > max returns False');
  Count := 0;
  TestResult := FindNumberRange(YearNdx, 1985, 1980,
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False when min > max');
  EndTest;
end;

procedure TestNumRange1982to1984;
begin
  BeginTest('FindNumberRange - years 1982-1984 finds 449');
  Count := 0;
  TestResult := FindNumberRange(YearNdx, 1982, 1984,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(449, Count, 'Should find 449 records in 1982-1984');
  EndTest;
end;

procedure TestNumRangeSingleYear;
begin
  BeginTest('FindNumberRange - single year range equals exact');
  { Range [1981, 1981] should equal exact 1981 }
  Count := 0;
  TestResult := FindNumberRange(YearNdx, 1981, 1981,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(25, Count, 'Range [1981,1981] should find 25');
  EndTest;
end;

procedure TestNumRangeNoMatch;
begin
  BeginTest('FindNumberRange - no match');
  Count := 0;
  TestResult := FindNumberRange(YearNdx, 8000, 9000,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 records');
  EndTest;
end;

procedure TestNumRangeMaxCountLimit;
begin
  BeginTest('FindNumberRange - MaxCount limits results');
  Count := 0;
  TestResult := FindNumberRange(YearNdx, 1982, 1984,
    RowIds, 10, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(10, Count, 'Should return exactly 10 results');
  EndTest;
end;

{ ================================================================ }
{  CountNumberExact tests                                          }
{ ================================================================ }

procedure TestCountNumExactBadFile;
begin
  BeginTest('CountNumberExact - bad file returns False');
  LongCount := 0;
  TestResult := CountNumberExact('NOEXIST.NDX', 1981, LongCount);
  AssertFalse(TestResult, 'Should return False for missing file');
  AssertEqualsInt(0, LongCount, 'Count should be 0');
  EndTest;
end;

procedure TestCountNumExact1981;
begin
  BeginTest('CountNumberExact - year 1981 count is 25');
  LongCount := 0;
  TestResult := CountNumberExact(YearNdx, 1981, LongCount);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(25, LongCount, 'Should count 25 for year 1981');
  EndTest;
end;

procedure TestCountNumExact1982;
begin
  BeginTest('CountNumberExact - year 1982 count is 124');
  LongCount := 0;
  TestResult := CountNumberExact(YearNdx, 1982, LongCount);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(124, LongCount, 'Should count 124 for year 1982');
  EndTest;
end;

procedure TestCountNumExact1983;
begin
  BeginTest('CountNumberExact - year 1983 count is 165');
  LongCount := 0;
  TestResult := CountNumberExact(YearNdx, 1983, LongCount);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(165, LongCount, 'Should count 165 for year 1983');
  EndTest;
end;

procedure TestCountNumExact1984;
begin
  BeginTest('CountNumberExact - year 1984 count is 160');
  LongCount := 0;
  TestResult := CountNumberExact(YearNdx, 1984, LongCount);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(160, LongCount, 'Should count 160 for year 1984');
  EndTest;
end;

procedure TestCountNumExactNoMatch;
begin
  BeginTest('CountNumberExact - no match returns 0');
  LongCount := 0;
  TestResult := CountNumberExact(YearNdx, 9999, LongCount);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, LongCount, 'Should count 0 for year 9999');
  EndTest;
end;

procedure TestCountNumExactConsistency;
begin
  BeginTest('CountNumberExact - consistent with FindNumberExact');
  { CountNumberExact should match FindNumberExact count }
  Count := 0;
  TestResult := FindNumberExact(YearNdx, 1981,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Find should succeed');

  LongCount := 0;
  TestResult := CountNumberExact(YearNdx, 1981, LongCount);
  AssertTrue(TestResult, 'Count should succeed');

  AssertEqualsInt(Count, LongCount,
    'Count and Find should return same number');
  EndTest;
end;

{ ================================================================ }
{  CountNumberRange tests                                          }
{ ================================================================ }

procedure TestCountNumRangeBadFile;
begin
  BeginTest('CountNumberRange - bad file returns False');
  LongCount := 0;
  TestResult := CountNumberRange('NOEXIST.NDX', 1980, 1985, LongCount);
  AssertFalse(TestResult, 'Should return False for missing file');
  EndTest;
end;

procedure TestCountNumRangeInverted;
begin
  BeginTest('CountNumberRange - min > max returns False');
  LongCount := 0;
  TestResult := CountNumberRange(YearNdx, 1985, 1980, LongCount);
  AssertFalse(TestResult, 'Should return False when min > max');
  EndTest;
end;

procedure TestCountNumRange1982to1984;
begin
  BeginTest('CountNumberRange - years 1982-1984 count is 449');
  LongCount := 0;
  TestResult := CountNumberRange(YearNdx, 1982, 1984, LongCount);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(449, LongCount, 'Should count 449 for 1982-1984');
  EndTest;
end;

procedure TestCountNumRangeSingleYear;
begin
  BeginTest('CountNumberRange - single year range');
  LongCount := 0;
  TestResult := CountNumberRange(YearNdx, 1981, 1981, LongCount);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(25, LongCount, 'Range [1981,1981] should count 25');
  EndTest;
end;

procedure TestCountNumRangeNoMatch;
begin
  BeginTest('CountNumberRange - no match returns 0');
  LongCount := 0;
  TestResult := CountNumberRange(YearNdx, 8000, 9000, LongCount);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, LongCount, 'Should count 0');
  EndTest;
end;

procedure TestCountNumRangeConsistency;
begin
  BeginTest('CountNumberRange - consistent with FindNumberRange');
  Count := 0;
  TestResult := FindNumberRange(YearNdx, 1982, 1984,
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Find should succeed');

  LongCount := 0;
  TestResult := CountNumberRange(YearNdx, 1982, 1984, LongCount);
  AssertTrue(TestResult, 'Count should succeed');

  AssertEqualsInt(Count, LongCount,
    'Count and Find should return same number');
  EndTest;
end;

{ ================================================================ }
{  FindDateExact tests                                             }
{ ================================================================ }

procedure TestDateExactNilRowIds;
begin
  BeginTest('FindDateExact - nil RowIds returns False');
  Count := 0;
  TestResult := FindDateExact(DateNdx, '2022-08-25',
    nil, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for nil RowIds');
  EndTest;
end;

procedure TestDateExactBadFile;
begin
  BeginTest('FindDateExact - bad file returns False');
  Count := 0;
  TestResult := FindDateExact('NOEXIST.NDX', '2022-08-25',
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for missing file');
  EndTest;
end;

procedure TestDateExactBadDateFormat;
begin
  BeginTest('FindDateExact - bad date format returns False');
  Count := 0;
  TestResult := FindDateExact(DateNdx, 'not-a-date',
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for bad date');
  AssertEqualsInt(0, Count, 'Count should be 0');
  EndTest;
end;

procedure TestDateExactKnownDate;
begin
  BeginTest('FindDateExact - 2022-08-25 finds 20+');
  Count := 0;
  TestResult := FindDateExact(DateNdx, '2022-08-25',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count >= 20, 'Should find at least 20 for 2022-08-25');
  WriteLn('  Found ', Count, ' matches for 2022-08-25');
  EndTest;
end;

procedure TestDateExactYYYYMMDD;
begin
  BeginTest('FindDateExact - YYYYMMDD format works');
  Count := 0;
  TestResult := FindDateExact(DateNdx, '20220825',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed with YYYYMMDD format');
  AssertTrue(Count >= 20, 'Should find at least 20');
  WriteLn('  Found ', Count, ' matches for 20220825');
  EndTest;
end;

procedure TestDateExactFormatConsistency;
var
  Count1, Count2: Integer;
begin
  BeginTest('FindDateExact - both date formats give same result');
  Count1 := 0;
  TestResult := FindDateExact(DateNdx, '2022-08-25',
    RowIds, MaxResults, Count1);
  AssertTrue(TestResult, 'Dash format should succeed');

  Count2 := 0;
  TestResult := FindDateExact(DateNdx, '20220825',
    RowIds, MaxResults, Count2);
  AssertTrue(TestResult, 'Compact format should succeed');

  AssertEqualsInt(Count1, Count2,
    'Both date formats should return same count');
  EndTest;
end;

procedure TestDateExactNoMatch;
begin
  BeginTest('FindDateExact - far future date finds 0');
  Count := 0;
  TestResult := FindDateExact(DateNdx, '2099-12-31',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 records');
  EndTest;
end;

procedure TestDateExactMaxCountLimit;
begin
  BeginTest('FindDateExact - MaxCount limits results');
  Count := 0;
  TestResult := FindDateExact(DateNdx, '2022-08-25',
    RowIds, 5, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count <= 5, 'Should return at most 5 results');
  AssertTrue(Count > 0, 'Should find at least 1 result');
  EndTest;
end;

{ ================================================================ }
{  FindDateRange tests                                             }
{ ================================================================ }

procedure TestDateRangeNilRowIds;
begin
  BeginTest('FindDateRange - nil RowIds returns False');
  Count := 0;
  TestResult := FindDateRange(DateNdx, '2022-08-01', '2022-08-30',
    nil, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for nil RowIds');
  EndTest;
end;

procedure TestDateRangeBadFile;
begin
  BeginTest('FindDateRange - bad file returns False');
  Count := 0;
  TestResult := FindDateRange('NOEXIST.NDX', '2022-08-01', '2022-08-30',
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for missing file');
  EndTest;
end;

procedure TestDateRangeBadStartDate;
begin
  BeginTest('FindDateRange - bad start date returns False');
  Count := 0;
  TestResult := FindDateRange(DateNdx, 'bad', '2022-08-30',
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for bad start date');
  EndTest;
end;

procedure TestDateRangeBadEndDate;
begin
  BeginTest('FindDateRange - bad end date returns False');
  Count := 0;
  TestResult := FindDateRange(DateNdx, '2022-08-01', 'bad',
    RowIds, MaxResults, Count);
  AssertFalse(TestResult, 'Should return False for bad end date');
  EndTest;
end;

procedure TestDateRangeAugust;
begin
  BeginTest('FindDateRange - August 2022 finds 200+');
  Count := 0;
  TestResult := FindDateRange(DateNdx, '2022-08-01', '2022-08-30',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count >= 200, 'Should find at least 200 in Aug 2022');
  WriteLn('  Found ', Count, ' matches in Aug 2022 range');
  EndTest;
end;

procedure TestDateRangeSwapped;
begin
  BeginTest('FindDateRange - swapped dates auto-corrected');
  { FindDateRange swaps if start > end }
  Count := 0;
  TestResult := FindDateRange(DateNdx, '2022-08-30', '2022-08-01',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed with swapped dates');
  AssertTrue(Count >= 200, 'Should find at least 200 even swapped');
  EndTest;
end;

procedure TestDateRangeSingleDay;
begin
  BeginTest('FindDateRange - single day range equals exact');
  { Range from same day to same day should equal exact match }
  Count := 0;
  TestResult := FindDateRange(DateNdx, '2022-08-25', '2022-08-25',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertTrue(Count >= 20, 'Single day range should find 20+');
  WriteLn('  Found ', Count, ' matches for single day range');
  EndTest;
end;

procedure TestDateRangeNoMatch;
begin
  BeginTest('FindDateRange - no match');
  Count := 0;
  TestResult := FindDateRange(DateNdx, '2099-01-01', '2099-12-31',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, Count, 'Should find 0 records');
  EndTest;
end;

procedure TestDateRangeMaxCountLimit;
begin
  BeginTest('FindDateRange - MaxCount limits results');
  Count := 0;
  TestResult := FindDateRange(DateNdx, '2022-08-01', '2022-08-30',
    RowIds, 10, Count);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(10, Count, 'Should return exactly 10 results');
  EndTest;
end;

{ ================================================================ }
{  CountDateExact tests                                            }
{ ================================================================ }

procedure TestCountDateExactBadFile;
begin
  BeginTest('CountDateExact - bad file returns False');
  LongCount := 0;
  TestResult := CountDateExact('NOEXIST.NDX', '2022-08-25', LongCount);
  AssertFalse(TestResult, 'Should return False for missing file');
  EndTest;
end;

procedure TestCountDateExactBadDate;
begin
  BeginTest('CountDateExact - bad date returns False');
  LongCount := 0;
  TestResult := CountDateExact(DateNdx, 'bad-date', LongCount);
  AssertFalse(TestResult, 'Should return False for bad date');
  AssertEqualsInt(0, LongCount, 'Count should be 0');
  EndTest;
end;

procedure TestCountDateExactKnown;
begin
  BeginTest('CountDateExact - 2022-08-25 count is 292');
  LongCount := 0;
  TestResult := CountDateExact(DateNdx, '2022-08-25', LongCount);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(292, LongCount, 'Should count 292 for 2022-08-25');
  EndTest;
end;

procedure TestCountDateExactNoMatch;
begin
  BeginTest('CountDateExact - far future date count is 0');
  LongCount := 0;
  TestResult := CountDateExact(DateNdx, '2099-12-31', LongCount);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, LongCount, 'Should count 0');
  EndTest;
end;

procedure TestCountDateExactConsistency;
begin
  BeginTest('CountDateExact - YYYYMMDD same as YYYY-MM-DD');
  LongCount := 0;
  TestResult := CountDateExact(DateNdx, '2022-08-25', LongCount);
  AssertTrue(TestResult, 'Dash format should succeed');
  AssertEqualsInt(292, LongCount, 'Dash format should count 292');

  LongCount := 0;
  TestResult := CountDateExact(DateNdx, '20220825', LongCount);
  AssertTrue(TestResult, 'Compact format should succeed');
  AssertEqualsInt(292, LongCount, 'Compact format should count 292');
  EndTest;
end;

{ ================================================================ }
{  CountDateRange tests                                            }
{ ================================================================ }

procedure TestCountDateRangeBadFile;
begin
  BeginTest('CountDateRange - bad file returns False');
  LongCount := 0;
  TestResult := CountDateRange('NOEXIST.NDX',
    '2022-08-01', '2022-08-30', LongCount);
  AssertFalse(TestResult, 'Should return False for missing file');
  EndTest;
end;

procedure TestCountDateRangeBadStart;
begin
  BeginTest('CountDateRange - bad start date returns False');
  LongCount := 0;
  TestResult := CountDateRange(DateNdx, 'bad', '2022-08-30', LongCount);
  AssertFalse(TestResult, 'Should return False for bad start date');
  EndTest;
end;

procedure TestCountDateRangeBadEnd;
begin
  BeginTest('CountDateRange - bad end date returns False');
  LongCount := 0;
  TestResult := CountDateRange(DateNdx, '2022-08-01', 'bad', LongCount);
  AssertFalse(TestResult, 'Should return False for bad end date');
  EndTest;
end;

procedure TestCountDateRangeAugust;
begin
  BeginTest('CountDateRange - Aug 2022 count is 295');
  LongCount := 0;
  TestResult := CountDateRange(DateNdx,
    '2022-08-01', '2022-08-30', LongCount);
  AssertTrue(TestResult, 'Should succeed');
  AssertEqualsInt(295, LongCount, 'Should count 295 for Aug 2022');
  EndTest;
end;

procedure TestCountDateRangeNoMatch;
begin
  BeginTest('CountDateRange - no match returns 0');
  LongCount := 0;
  TestResult := CountDateRange(DateNdx,
    '2099-01-01', '2099-12-31', LongCount);
  AssertTrue(TestResult, 'Should succeed even with no matches');
  AssertEqualsInt(0, LongCount, 'Should count 0');
  EndTest;
end;

procedure TestCountDateRangeSwapped;
begin
  BeginTest('CountDateRange - swapped dates auto-corrected');
  LongCount := 0;
  TestResult := CountDateRange(DateNdx,
    '2022-08-30', '2022-08-01', LongCount);
  AssertTrue(TestResult, 'Should succeed with swapped dates');
  AssertEqualsInt(295, LongCount,
    'Should count 295 even with swapped dates');
  EndTest;
end;

procedure TestCountDateRangeConsistency;
begin
  BeginTest('CountDateRange - consistent with FindDateRange');
  Count := 0;
  TestResult := FindDateRange(DateNdx, '2022-08-01', '2022-08-30',
    RowIds, MaxResults, Count);
  AssertTrue(TestResult, 'Find should succeed');

  LongCount := 0;
  TestResult := CountDateRange(DateNdx,
    '2022-08-01', '2022-08-30', LongCount);
  AssertTrue(TestResult, 'Count should succeed');

  AssertEqualsInt(Count, LongCount,
    'Count and Find should return same number');
  EndTest;
end;

{ ================================================================ }
{  Main test runner                                                }
{ ================================================================ }

begin
  WriteLn('=== DBFINDEX Module Tests ===');
  WriteLn;

  MemoryReport('Initial Memory State');

  { Allocate result buffer }
  GetMem(RowIds, MaxResults * SizeOf(LongInt));

  { --- FindCharacterExact --- }
  WriteLn('--- FindCharacterExact ---');
  TestCharExactNilRowIds;
  TestCharExactZeroMaxCount;
  TestCharExactBadFile;
  TestCharExactKnownMatch;
  TestCharExactNoMatch;
  TestCharExactMaxCountLimit;

  MemoryReport('After FindCharacterExact Tests');

  { --- FindCharacterBegins --- }
  WriteLn('--- FindCharacterBegins ---');
  TestCharBeginsNilRowIds;
  TestCharBeginsZeroMaxCount;
  TestCharBeginsBadFile;
  TestCharBeginsCosmi;
  TestCharBeginsKing;
  TestCharBeginsSIE;
  TestCharBeginsNoMatch;
  TestCharBeginsMaxCountLimit;
  TestCharBeginsAllRecords;

  MemoryReport('After FindCharacterBegins Tests');

  { --- FindNumberExact --- }
  WriteLn('--- FindNumberExact ---');
  TestNumExactNilRowIds;
  TestNumExactZeroMaxCount;
  TestNumExactBadFile;
  TestNumExact1981;
  TestNumExactNoMatch;
  TestNumExactMaxCountLimit;
  TestNumExactMultipleYears;

  MemoryReport('After FindNumberExact Tests');

  { --- FindNumberRange --- }
  WriteLn('--- FindNumberRange ---');
  TestNumRangeNilRowIds;
  TestNumRangeZeroMaxCount;
  TestNumRangeBadFile;
  TestNumRangeInverted;
  TestNumRange1982to1984;
  TestNumRangeSingleYear;
  TestNumRangeNoMatch;
  TestNumRangeMaxCountLimit;

  MemoryReport('After FindNumberRange Tests');

  { --- CountNumberExact --- }
  WriteLn('--- CountNumberExact ---');
  TestCountNumExactBadFile;
  TestCountNumExact1981;
  TestCountNumExact1982;
  TestCountNumExact1983;
  TestCountNumExact1984;
  TestCountNumExactNoMatch;
  TestCountNumExactConsistency;

  MemoryReport('After CountNumberExact Tests');

  { --- CountNumberRange --- }
  WriteLn('--- CountNumberRange ---');
  TestCountNumRangeBadFile;
  TestCountNumRangeInverted;
  TestCountNumRange1982to1984;
  TestCountNumRangeSingleYear;
  TestCountNumRangeNoMatch;
  TestCountNumRangeConsistency;

  MemoryReport('After CountNumberRange Tests');

  { --- FindDateExact --- }
  WriteLn('--- FindDateExact ---');
  TestDateExactNilRowIds;
  TestDateExactBadFile;
  TestDateExactBadDateFormat;
  TestDateExactKnownDate;
  TestDateExactYYYYMMDD;
  TestDateExactFormatConsistency;
  TestDateExactNoMatch;
  TestDateExactMaxCountLimit;

  MemoryReport('After FindDateExact Tests');

  { --- FindDateRange --- }
  WriteLn('--- FindDateRange ---');
  TestDateRangeNilRowIds;
  TestDateRangeBadFile;
  TestDateRangeBadStartDate;
  TestDateRangeBadEndDate;
  TestDateRangeAugust;
  TestDateRangeSwapped;
  TestDateRangeSingleDay;
  TestDateRangeNoMatch;
  TestDateRangeMaxCountLimit;

  MemoryReport('After FindDateRange Tests');

  { --- CountDateExact --- }
  WriteLn('--- CountDateExact ---');
  TestCountDateExactBadFile;
  TestCountDateExactBadDate;
  TestCountDateExactKnown;
  TestCountDateExactNoMatch;
  TestCountDateExactConsistency;

  MemoryReport('After CountDateExact Tests');

  { --- CountDateRange --- }
  WriteLn('--- CountDateRange ---');
  TestCountDateRangeBadFile;
  TestCountDateRangeBadStart;
  TestCountDateRangeBadEnd;
  TestCountDateRangeAugust;
  TestCountDateRangeNoMatch;
  TestCountDateRangeSwapped;
  TestCountDateRangeConsistency;

  MemoryReport('Final Memory State');

  FreeMem(RowIds, MaxResults * SizeOf(LongInt));

  WriteLn;
  PrintSummary;
end.
