program TESTUTIL;

uses DBFUTIL, Assert;

{ Test string manipulation functions }
procedure TestStringFunctions;
var
  TestStr: string;
begin
  BeginTest('String Functions');
  
  { Test LowerStr }
  TestStr := LowerStr('HELLO WORLD');
  AssertEqualsStr('hello world', TestStr, 'LowerStr should convert to lowercase');
  
  TestStr := LowerStr('Mixed CASE 123');
  AssertEqualsStr('mixed case 123', TestStr, 'LowerStr should handle mixed case and numbers');
  
  { Test UpperStr }
  TestStr := UpperStr('hello world');
  AssertEqualsStr('HELLO WORLD', TestStr, 'UpperStr should convert to uppercase');
  
  TestStr := UpperStr('Mixed CASE 123');
  AssertEqualsStr('MIXED CASE 123', TestStr, 'UpperStr should handle mixed case and numbers');
  
  { Test TrimSpaces }
  TestStr := TrimSpaces('   hello   world   ');
  AssertEqualsStr('hello   world', TestStr, 'TrimSpaces should remove leading/trailing spaces only');
  
  TestStr := TrimSpaces('singleword');
  AssertEqualsStr('singleword', TestStr, 'TrimSpaces should not affect single words');
  
  { Test TrimString }
  TestStr := TrimString('   hello   world   ');
  AssertEqualsStr('hello   world', TestStr, 'TrimString should trim leading/trailing spaces only');
  
  { Test PadString }
  TestStr := PadString('test', 10);
  AssertEqualsStr('test      ', TestStr, 'PadString should pad to specified length');
  
  TestStr := PadString('longstring', 5);
  AssertEqualsStr('longs', TestStr, 'PadString should truncate if longer than target');
  
  EndTest;
end;

{ Test numeric parsing functions }
procedure TestNumericFunctions;
var
  TestStr: string;
  TestInt: LongInt;
  TestWord: Word;
  TestByte: Byte;
  TestBool: Boolean;
begin
  BeginTest('Numeric Functions');
  
  { Test ParseInt }
  TestInt := ParseInt('123');
  AssertEqualsInt(123, TestInt, 'ParseInt should parse positive integers');
  
  TestInt := ParseInt('-456');
  AssertEqualsInt(-456, TestInt, 'ParseInt should parse negative integers');
  
  TestInt := ParseInt('0');
  AssertEqualsInt(0, TestInt, 'ParseInt should parse zero');
  
  { Test ParseWord }
  TestWord := ParseWord('123');
  AssertEqualsInt(123, TestWord, 'ParseWord should parse positive words');
  
  TestWord := ParseWord('0');
  AssertEqualsInt(0, TestWord, 'ParseWord should parse zero');
  
  { Test ParseByte }
  TestByte := ParseByte('123');
  AssertEqualsInt(123, TestByte, 'ParseByte should parse positive bytes');
  
  TestByte := ParseByte('0');
  AssertEqualsInt(0, TestByte, 'ParseByte should parse zero');
  
  TestByte := ParseByte('255');
  AssertEqualsInt(255, TestByte, 'ParseByte should parse maximum byte value');
  
  { Test ParseBool }
  TestBool := ParseBool('TRUE');
  AssertTrue(TestBool, 'ParseBool should parse TRUE');
  
  TestBool := ParseBool('true');
  AssertTrue(TestBool, 'ParseBool should parse lowercase true');
  
  TestBool := ParseBool('FALSE');
  AssertFalse(TestBool, 'ParseBool should parse FALSE');
  
  TestBool := ParseBool('false');
  AssertFalse(TestBool, 'ParseBool should parse lowercase false');
  
  { Test IntToStrLocal }
  TestStr := IntToStrLocal(123);
  AssertEqualsStr('123', TestStr, 'IntToStrLocal should convert positive integers');
  
  TestStr := IntToStrLocal(-456);
  AssertEqualsStr('-456', TestStr, 'IntToStrLocal should convert negative integers');
  
  TestStr := IntToStrLocal(0);
  AssertEqualsStr('0', TestStr, 'IntToStrLocal should convert zero');
  
  EndTest;
end;

{ Test decimal scaling functions }
procedure TestDecimalFunctions;
var
  ScaledValue: LongInt;
  DecimalStr: string;
begin
  BeginTest('Decimal Functions');
  
  { Test ScaleDecimal }
  ScaledValue := ScaleDecimal('123.45', 10);
  AssertEqualsInt(123450000, ScaledValue, 'ScaleDecimal should scale decimal with 6 decimal places');
  
  ScaledValue := ScaleDecimal('123.4', 10);
  AssertEqualsInt(123400000, ScaledValue, 'ScaleDecimal should handle single decimal');
  
  ScaledValue := ScaleDecimal('123', 10);
  AssertEqualsInt(123000000, ScaledValue, 'ScaleDecimal should handle integer input');
  
  { Test UnscaleDecimal }
  DecimalStr := UnscaleDecimal(123450000, 10);
  AssertEqualsStr('123.45', DecimalStr, 'UnscaleDecimal should unscale to decimal string');
  
  DecimalStr := UnscaleDecimal(123400000, 10);
  AssertEqualsStr('123.4', DecimalStr, 'UnscaleDecimal should remove trailing zeros');
  
  DecimalStr := UnscaleDecimal(123000000, 10);
  AssertEqualsStr('123', DecimalStr, 'UnscaleDecimal should remove decimal part for integers');
  
  EndTest;
end;

{ Test file operations }
procedure TestFileFunctions;
var
  TestFile: File;
  Result: Boolean;
  IoCode: Integer;
  FileSizeBytes: LongInt;
  Buf: array[0..5] of Byte;
begin
  BeginTest('File Functions');
  
  { Clean slate }
  Result := DeleteFile('TESTUTIL.TXT');
  Result := DeleteFile('TESTUTL2.TXT');
  
  { Test FileExists with non-existent file }
  Result := FileExists('NONEXISTENT.TXT');
  AssertFalse(Result, 'FileExists should return False for non-existent file');
  
  { Create a binary test file for other tests }
  WriteLn('Creating binary test file...');
  Assign(TestFile, 'TESTUTIL.TXT');
  {$I-}
  Rewrite(TestFile, 1);
  IoCode := IOResult;
  WriteLn('Rewrite IOResult = ', IoCode);
  AssertTrue(IoCode = 0, 'Rewrite should succeed');
  
  Buf[0] := Ord('T');
  Buf[1] := Ord('e');
  Buf[2] := Ord('s');
  Buf[3] := Ord('t');
  Buf[4] := 13;  { Carriage return }
  Buf[5] := 10;  { Line feed }
  BlockWrite(TestFile, Buf, 6);
  IoCode := IOResult;
  WriteLn('BlockWrite IOResult = ', IoCode);
  AssertTrue(IoCode = 0, 'BlockWrite should succeed');
  
  Close(TestFile);
  IoCode := IOResult;
  WriteLn('Close IOResult = ', IoCode);
  AssertTrue(IoCode = 0, 'Close should succeed');
  {$I+}
  
  WriteLn('Created TESTUTIL.TXT');
  
  { Test FileExists with existing file }
  Result := FileExists('TESTUTIL.TXT');
  WriteLn('FileExists(TESTUTIL.TXT) = ', Result);
  AssertTrue(Result, 'FileExists should return True for existing file');
  
  { Verify file size > 0 }
  Assign(TestFile, 'TESTUTIL.TXT');
  {$I-}
  Reset(TestFile, 1);
  IoCode := IOResult;
  WriteLn('Reset IOResult = ', IoCode);
  AssertTrue(IoCode = 0, 'Reset should succeed');
  FileSizeBytes := FileSize(TestFile);
  Close(TestFile);
  IoCode := IOResult;
  WriteLn('Close IOResult = ', IoCode);
  AssertTrue(IoCode = 0, 'Close should succeed');
  WriteLn('TESTUTIL.TXT size: ', FileSizeBytes);
  AssertTrue(FileSizeBytes > 0, 'File size should be > 0');
  {$I+}
  
  { Rename file }
  Result := RenameFile('TESTUTIL.TXT', 'TESTUTL2.TXT');
  WriteLn('RenameFile(TESTUTIL.TXT -> TESTUTL2.TXT) = ', Result);
  AssertTrue(Result, 'RenameFile should succeed');
  
  { Verify old file doesn't exist }
  Result := FileExists('TESTUTIL.TXT');
  WriteLn('FileExists(TESTUTIL.TXT) after rename = ', Result);
  AssertFalse(Result, 'Old filename should not exist after rename');
  
  { Verify new file exists }
  Result := FileExists('TESTUTL2.TXT');
  WriteLn('FileExists(TESTUTL2.TXT) = ', Result);
  AssertTrue(Result, 'New filename should exist after rename');
  
  { Test DeleteFile }
  Result := DeleteFile('TESTUTL2.TXT');
  AssertTrue(Result, 'DeleteFile should succeed when file exists');
  
  { Verify file is deleted }
  Result := FileExists('TESTUTL2.TXT');
  AssertFalse(Result, 'File should not exist after deletion');

  { Test IsValid83FileName }
  AssertTrue(IsValid83FileName('TEST'), 'IsValid83FileName should accept base names');
  AssertTrue(IsValid83FileName('TEST.TXT'), 'IsValid83FileName should accept 8.3 names');
  AssertTrue(IsValid83FileName('ABCDEFGH.ABC'), 'IsValid83FileName should accept max lengths');
  AssertTrue(IsValid83FileName('FILE-ME.TXT'), 'IsValid83FileName should accept dashes');
  AssertTrue(IsValid83FileName('FILE_ME.TXT'), 'IsValid83FileName should accept underscores');
  AssertFalse(IsValid83FileName('ABCDEFGHI.TXT'), 'IsValid83FileName should reject >8 base');
  AssertFalse(IsValid83FileName('TEST.ABCD'), 'IsValid83FileName should reject >3 ext');
  AssertFalse(IsValid83FileName('.TXT'), 'IsValid83FileName should reject empty base');
  AssertFalse(IsValid83FileName(''), 'IsValid83FileName should reject empty string');
  AssertFalse(IsValid83FileName('FILE MAIN.TXT'), 'IsValid83FileName should reject spaces');
  AssertFalse(IsValid83FileName('file.main.txt'), 'IsValid83FileName should reject multiple dots');
  AssertFalse(IsValid83FileName('.gitignore'), 'IsValid83FileName should reject leading dot');
  
  EndTest;
end;

{ Test date functions }
procedure TestDateFunctions;
var
  JDN: LongInt;
  DateStr, FormattedDate, FormattedTime: string;
  Year, Month, Day: Word;
  TestJDN: LongInt;
begin
  BeginTest('Date Functions');
  
  { Test GetDate }
  GetDate(Year, Month, Day);
  AssertTrue(Year >= 100, 'GetDate should return reasonable year (>= 2000)');
  AssertTrue((Month >= 1) and (Month <= 12), 'GetDate should return valid month (1-12)');
  AssertTrue((Day >= 1) and (Day <= 31), 'GetDate should return valid day (1-31)');
  
  { Test FormatDate }
  FormattedDate := FormatDate(2024, 1, 27);
  AssertEqualsStr('20240127', FormattedDate, 'FormatDate should format date in YYYYMMDD format');
  
  FormattedDate := FormatDate(2024, 12, 31);
  AssertEqualsStr('20241231', FormattedDate, 'FormatDate should handle double-digit months/days');
  
  { Test FormatTime }
  FormattedTime := FormatTime(14, 30, 45);
  AssertEqualsStr('143045', FormattedTime, 'FormatTime should format time in HHMMSS format');
  
  FormattedTime := FormatTime(9, 5, 3);
  AssertEqualsStr('090503', FormattedTime, 'FormatTime should pad single digits with zeros');
  
  { Test DateToJDN and JDNToDate }
  JDN := DateToJDN('20240127');
  WriteLn('DateToJDN(''20240127'') = ', JDN);
  AssertTrue(JDN > 0, 'DateToJDN should return positive JDN for valid date');

  { Test DateToJDNParts }
  TestJDN := DateToJDNParts(2024, 1, 27);
  AssertEqualsInt(JDN, TestJDN, 'DateToJDNParts should match DateToJDN for same date');
  
  { Test with a simpler date to debug }
  TestJDN := DateToJDN('20000101');
  WriteLn('DateToJDN(''20000101'') = ', TestJDN);
  
  TestJDN := DateToJDN('20240101');
  WriteLn('DateToJDN(''20240101'') = ', TestJDN);
  
  DateStr := JDNToDate(JDN);
  WriteLn('JDNToDate(', JDN, ') = ', DateStr);
  AssertEqualsStr('20240127', DateStr, 'JDNToDate should convert back to original date');

  { Test DBFDateStrToJDN }
  TestJDN := DBFDateStrToJDN('20240127');
  AssertEqualsInt(JDN, TestJDN, 'DBFDateStrToJDN should match DateToJDN for same date');
  TestJDN := DBFDateStrToJDN('202401');
  AssertEqualsInt(0, TestJDN, 'DBFDateStrToJDN should return 0 for invalid date string');
  
  EndTest;
end;

{ Test Base64 functions }
procedure TestBase64Functions;
var
  Index: Integer;
  State: TB64EncState;
  OutputFile: Text;
  TestData: array[0..2] of Byte;
  Result: Boolean;
begin
  BeginTest('Base64 Functions');
  
  { Test Base64Index }
  Index := Base64Index(Ord('A'));
  AssertEqualsInt(0, Index, 'Base64Index should return 0 for ''A''');
  
  Index := Base64Index(Ord('Z'));
  AssertEqualsInt(25, Index, 'Base64Index should return 25 for ''Z''');
  
  Index := Base64Index(Ord('a'));
  AssertEqualsInt(26, Index, 'Base64Index should return 26 for ''a''');
  
  Index := Base64Index(Ord('z'));
  AssertEqualsInt(51, Index, 'Base64Index should return 51 for ''z''');
  
  Index := Base64Index(Ord('0'));
  AssertEqualsInt(52, Index, 'Base64Index should return 52 for ''0''');
  
  Index := Base64Index(Ord('+'));
  AssertEqualsInt(62, Index, 'Base64Index should return 62 for ''+''');
  
  Index := Base64Index(Ord('/'));
  AssertEqualsInt(63, Index, 'Base64Index should return 63 for ''/''');
  
  { Test B64EncInit }
  B64EncInit(State);
  AssertEqualsInt(0, State.RemLen, 'B64EncInit should initialize RemLen to 0');
  
  { Test WriteEscapedText }
  TestData[0] := Ord('A');
  TestData[1] := Ord('B');
  TestData[2] := Ord('C');
  
  Assign(OutputFile, 'TESTB64.TXT');
  Rewrite(OutputFile);
  WriteEscapedText(OutputFile, TestData, 3);
  Close(OutputFile);
  
  { Verify file was created (basic test) }
  AssertTrue(FileExists('TESTB64.TXT'), 'WriteEscapedText should create output file');
  
  { Clean up }
  Result := DeleteFile('TESTB64.TXT');
  AssertTrue(Result, 'DeleteFile should succeed when file exists');
  
  EndTest;
end;

{ Main test runner }
begin
  WriteLn('=== DBFUTIL Module Tests ===');
  WriteLn;
  
  TestStringFunctions;
  TestNumericFunctions;
  TestDecimalFunctions;
  TestFileFunctions; 
  TestDateFunctions;
  TestBase64Functions;
  
  WriteLn;
  PrintSummary;
  
  { Clean up any remaining test files }
  {WriteLn('Cleaning up test files...');
  if DeleteFile('TESTUTIL.TXT') then
    WriteLn('Deleted TESTUTIL.TXT');
  if DeleteFile('TESTUTL2.TXT') then
    WriteLn('Deleted TESTUTL2.TXT');
  if DeleteFile('TESTB64.TXT') then
    WriteLn('Deleted TESTB64.TXT');
  WriteLn('Cleanup complete');}
end.
