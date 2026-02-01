{ TESTHEAP.PAS - Comprehensive tests for DBHEAP heap map functions }

program TestHeapProgram;

{$M 32768,0,131072}  { Stack: 32KB, Heap: 128KB }

uses Assert, DBFUTIL, DBF, DBHEAP;

const
  LargeDbPath = 'samples\LARGEDB.DBF';
  MaxResults  = 4000;

var
  Ok: Boolean;

{ ================================================================== }
{ Phase 1: In-memory tests (no DBF required)                          }
{ ================================================================== }

{ ------------------------------------------------------------------ }
{ CalculateHeapLayout tests                                           }
{ ------------------------------------------------------------------ }

procedure TestLayoutSingleWord;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - single Word field');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftWord;
  Ok := CalculateHeapLayout(Specs, 1, 16);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(0, Specs[1].HeapOffset, 'Word at offset 0');
  EndTest;
end;

procedure TestLayoutSingleLongInt;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - single LongInt field');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftLongInt;
  Ok := CalculateHeapLayout(Specs, 1, 16);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(0, Specs[1].HeapOffset, 'LongInt at offset 0');
  EndTest;
end;

procedure TestLayoutWordAlignment;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - Word alignment after Byte');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftByte;
  Specs[2].DBFFieldIdx := 2;
  Specs[2].HeapFieldType := hftWord;
  Ok := CalculateHeapLayout(Specs, 2, 16);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(0, Specs[1].HeapOffset, 'Byte at offset 0');
  AssertEqualsInt(2, Specs[2].HeapOffset, 'Word aligned to offset 2');
  EndTest;
end;

procedure TestLayoutLongIntAlignment;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - LongInt alignment after Byte');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftByte;
  Specs[2].DBFFieldIdx := 2;
  Specs[2].HeapFieldType := hftLongInt;
  Ok := CalculateHeapLayout(Specs, 2, 16);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(0, Specs[1].HeapOffset, 'Byte at offset 0');
  AssertEqualsInt(4, Specs[2].HeapOffset, 'LongInt aligned to offset 4');
  EndTest;
end;

procedure TestLayoutBitFlagsSharing;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - BitFlags share same byte');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftBitFlags;
  Specs[1].BitMask := $01;
  Specs[2].DBFFieldIdx := 2;
  Specs[2].HeapFieldType := hftBitFlags;
  Specs[2].BitMask := $02;
  Specs[3].DBFFieldIdx := 3;
  Specs[3].HeapFieldType := hftBitFlags;
  Specs[3].BitMask := $04;
  Ok := CalculateHeapLayout(Specs, 3, 8);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(Specs[1].HeapOffset, Specs[2].HeapOffset,
    'Flag 1 and 2 share offset');
  AssertEqualsInt(Specs[1].HeapOffset, Specs[3].HeapOffset,
    'Flag 1 and 3 share offset');
  EndTest;
end;

procedure TestLayoutNibblePairing;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - two Nibbles share one byte');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftNibble;
  Specs[2].DBFFieldIdx := 2;
  Specs[2].HeapFieldType := hftNibble;
  Ok := CalculateHeapLayout(Specs, 2, 8);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(Specs[1].HeapOffset, Specs[2].HeapOffset,
    'Nibbles share same byte');
  AssertEqualsInt(0, Specs[1].NibbleShift, 'First nibble is low');
  AssertEqualsInt(4, Specs[2].NibbleShift, 'Second nibble is high');
  EndTest;
end;

procedure TestLayoutThreeNibbles;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - three Nibbles use two bytes');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftNibble;
  Specs[2].DBFFieldIdx := 2;
  Specs[2].HeapFieldType := hftNibble;
  Specs[3].DBFFieldIdx := 3;
  Specs[3].HeapFieldType := hftNibble;
  Ok := CalculateHeapLayout(Specs, 3, 8);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(Specs[1].HeapOffset, Specs[2].HeapOffset,
    'First two nibbles share byte');
  AssertTrue(Specs[3].HeapOffset > Specs[1].HeapOffset,
    'Third nibble in next byte');
  AssertEqualsInt(0, Specs[3].NibbleShift, 'Third nibble is low');
  EndTest;
end;

procedure TestLayoutOverflowTarget;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - overflow target record size');
  FillChar(Specs, SizeOf(Specs), 0);
  { 5 LongInts = 20 bytes, won't fit in 16 }
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftLongInt;
  Specs[2].DBFFieldIdx := 2;
  Specs[2].HeapFieldType := hftLongInt;
  Specs[3].DBFFieldIdx := 3;
  Specs[3].HeapFieldType := hftLongInt;
  Specs[4].DBFFieldIdx := 4;
  Specs[4].HeapFieldType := hftLongInt;
  Specs[5].DBFFieldIdx := 5;
  Specs[5].HeapFieldType := hftLongInt;
  Ok := CalculateHeapLayout(Specs, 5, 16);
  AssertFalse(Ok, 'Should fail: 20 bytes > 16 target');
  EndTest;
end;

procedure TestLayoutFiveWords;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - five Words fit in 16 bytes');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;
  Specs[2].DBFFieldIdx := 1;
  Specs[2].HeapFieldType := hftWord;
  Specs[3].DBFFieldIdx := 2;
  Specs[3].HeapFieldType := hftWord;
  Specs[4].DBFFieldIdx := 3;
  Specs[4].HeapFieldType := hftWord;
  Specs[5].DBFFieldIdx := 4;
  Specs[5].HeapFieldType := hftWord;
  Ok := CalculateHeapLayout(Specs, 5, 16);
  AssertTrue(Ok, 'Should succeed: 10 bytes pads to 16');
  AssertEqualsInt(0, Specs[1].HeapOffset, 'Field 1 at 0');
  AssertEqualsInt(2, Specs[2].HeapOffset, 'Field 2 at 2');
  AssertEqualsInt(4, Specs[3].HeapOffset, 'Field 3 at 4');
  AssertEqualsInt(6, Specs[4].HeapOffset, 'Field 4 at 6');
  AssertEqualsInt(8, Specs[5].HeapOffset, 'Field 5 at 8');
  EndTest;
end;

procedure TestLayoutMixedTypes;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - mixed types alignment');
  FillChar(Specs, SizeOf(Specs), 0);
  { Byte(0) + pad(1) + Word(2-3) + LongInt(4-7) = 8, pads to 8 }
  Specs[1].DBFFieldIdx := 1;
  Specs[1].HeapFieldType := hftByte;
  Specs[2].DBFFieldIdx := 2;
  Specs[2].HeapFieldType := hftWord;
  Specs[3].DBFFieldIdx := 3;
  Specs[3].HeapFieldType := hftLongInt;
  Ok := CalculateHeapLayout(Specs, 3, 8);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(0, Specs[1].HeapOffset, 'Byte at 0');
  AssertEqualsInt(2, Specs[2].HeapOffset, 'Word at 2');
  AssertEqualsInt(4, Specs[3].HeapOffset, 'LongInt at 4');
  EndTest;
end;

procedure TestLayoutZeroFields;
var
  Specs: THeapFieldSpecArray;
begin
  BeginTest('Layout - zero fields');
  FillChar(Specs, SizeOf(Specs), 0);
  Ok := CalculateHeapLayout(Specs, 0, 16);
  AssertTrue(Ok, 'Zero fields should succeed (0 bytes pads to 0)');
  EndTest;
end;

{ ------------------------------------------------------------------ }
{ AllocateHeapRecords / FreeHeapRecords tests                         }
{ ------------------------------------------------------------------ }

procedure TestAllocateBasic;
var
  HM: THeapMap;
begin
  BeginTest('Allocate - basic allocation');
  FillChar(HM, SizeOf(HM), 0);
  HM.RecordSize := 16;
  HM.Records := nil;
  Ok := AllocateHeapRecords(HM, 100);
  AssertTrue(Ok, 'Should succeed');
  AssertTrue(HM.Records <> nil, 'Records pointer should be non-nil');
  AssertEqualsInt(100, HM.AllocatedRecords, 'AllocatedRecords = 100');
  Ok := FreeHeapRecords(HM);
  AssertTrue(Ok, 'Free should succeed');
  AssertTrue(HM.Records = nil, 'Records pointer should be nil after free');
  EndTest;
end;

procedure TestAllocateMaxRecords;
var
  HM: THeapMap;
begin
  BeginTest('Allocate - MaxHeapRecords at size 16');
  FillChar(HM, SizeOf(HM), 0);
  HM.RecordSize := 16;
  HM.Records := nil;
  { 4000 * 16 = 64000, under 65535 limit }
  Ok := AllocateHeapRecords(HM, MaxHeapRecords);
  AssertTrue(Ok, 'Should succeed: 4000*16=64000 < 65535');
  AssertTrue(HM.Records <> nil, 'Should allocate');
  Ok := FreeHeapRecords(HM);
  EndTest;
end;

procedure TestAllocateOverflow;
var
  HM: THeapMap;
begin
  BeginTest('Allocate - overflow > 65535 bytes');
  FillChar(HM, SizeOf(HM), 0);
  HM.RecordSize := 32;
  HM.Records := nil;
  { 4000 * 32 = 128000 > 65535 }
  Ok := AllocateHeapRecords(HM, MaxHeapRecords);
  AssertFalse(Ok, 'Should fail: 4000*32 > 65535');
  AssertTrue(HM.Records = nil, 'Records should remain nil');
  EndTest;
end;

procedure TestFreeNilRecords;
var
  HM: THeapMap;
begin
  BeginTest('Free - nil Records is safe');
  FillChar(HM, SizeOf(HM), 0);
  HM.Records := nil;
  Ok := FreeHeapRecords(HM);
  AssertTrue(Ok, 'Free nil should succeed (no-op)');
  EndTest;
end;

procedure TestAllocateZeroInit;
var
  HM: THeapMap;
  P: ^Byte;
  AllZero: Boolean;
  I: Word;
begin
  BeginTest('Allocate - memory is zeroed');
  FillChar(HM, SizeOf(HM), 0);
  HM.RecordSize := 16;
  HM.Records := nil;
  Ok := AllocateHeapRecords(HM, 10);
  AssertTrue(Ok, 'Should succeed');
  AllZero := True;
  for I := 0 to (10 * 16) - 1 do
  begin
    P := @PByteArray(HM.Records)^[I];
    if P^ <> 0 then
      AllZero := False;
  end;
  AssertTrue(AllZero, 'All bytes should be zero');
  Ok := FreeHeapRecords(HM);
  EndTest;
end;

{ ------------------------------------------------------------------ }
{ HeapGet* accessor tests (manually populated heap)                   }
{ ------------------------------------------------------------------ }

var
  TestHM: THeapMap;
  TestSpecs: THeapFieldSpecArray;

{ Build a 16-byte record layout with all field types:
  Field 1: Word      at offset 0  (2 bytes)
  Field 2: Word      at offset 2  (2 bytes)
  Field 3: LongInt   at offset 4  (4 bytes)
  Field 4: BitFlags  at offset 8  (1 byte, mask $01)
  Field 5: BitFlags  at offset 8  (shared, mask $04)
  Field 6: Nibble    at offset 9  (low nibble)
  Field 7: Nibble    at offset 9  (high nibble)
  Field 8: Byte      at offset 10 (1 byte)
  Total: 11 bytes, pads to 16 }
procedure SetupTestHeapMap;
var
  PW: ^Word;
  PL: ^LongInt;
  PB: ^Byte;
begin
  FillChar(TestSpecs, SizeOf(TestSpecs), 0);
  TestSpecs[1].DBFFieldIdx := 1;
  TestSpecs[1].HeapFieldType := hftWord;
  TestSpecs[2].DBFFieldIdx := 2;
  TestSpecs[2].HeapFieldType := hftWord;
  TestSpecs[3].DBFFieldIdx := 3;
  TestSpecs[3].HeapFieldType := hftLongInt;
  TestSpecs[4].DBFFieldIdx := 4;
  TestSpecs[4].HeapFieldType := hftBitFlags;
  TestSpecs[4].BitMask := $01;
  TestSpecs[5].DBFFieldIdx := 5;
  TestSpecs[5].HeapFieldType := hftBitFlags;
  TestSpecs[5].BitMask := $04;
  TestSpecs[6].DBFFieldIdx := 6;
  TestSpecs[6].HeapFieldType := hftNibble;
  TestSpecs[7].DBFFieldIdx := 7;
  TestSpecs[7].HeapFieldType := hftNibble;
  TestSpecs[8].DBFFieldIdx := 8;
  TestSpecs[8].HeapFieldType := hftByte;

  Ok := CalculateHeapLayout(TestSpecs, 8, 16);
  if not Ok then
  begin
    WriteLn('FATAL: Test heap layout failed');
    Halt(1);
  end;

  FillChar(TestHM, SizeOf(TestHM), 0);
  TestHM.RecordSize := 16;
  TestHM.FieldCount := 8;
  TestHM.FieldSpecs := TestSpecs;

  Ok := AllocateHeapRecords(TestHM, 3);
  if not Ok then
  begin
    WriteLn('FATAL: Test heap allocation failed');
    Halt(1);
  end;
  TestHM.RecordCount := 3;

  { Populate record 0: Word=1000, Word=2000, LongInt=100000,
    Bit $01=set, Bit $04=clear, LowNib=5, HighNib=12, Byte=200 }
  PW := @PByteArray(TestHM.Records)^[0 * 16 + 0];
  PW^ := 1000;
  PW := @PByteArray(TestHM.Records)^[0 * 16 + 2];
  PW^ := 2000;
  PL := @PByteArray(TestHM.Records)^[0 * 16 + 4];
  PL^ := 100000;
  PB := @PByteArray(TestHM.Records)^[0 * 16 + 8];
  PB^ := $01;  { bit 0 set, bit 2 clear }
  PB := @PByteArray(TestHM.Records)^[0 * 16 + 9];
  PB^ := (12 shl 4) or 5;  { high=12, low=5 }
  PB := @PByteArray(TestHM.Records)^[0 * 16 + 10];
  PB^ := 200;

  { Populate record 1: Word=0, Word=65535, LongInt=0,
    Bit $01=clear, Bit $04=set, LowNib=0, HighNib=15, Byte=0 }
  PW := @PByteArray(TestHM.Records)^[1 * 16 + 0];
  PW^ := 0;
  PW := @PByteArray(TestHM.Records)^[1 * 16 + 2];
  PW^ := 65535;
  PL := @PByteArray(TestHM.Records)^[1 * 16 + 4];
  PL^ := 0;
  PB := @PByteArray(TestHM.Records)^[1 * 16 + 8];
  PB^ := $04;  { bit 0 clear, bit 2 set }
  PB := @PByteArray(TestHM.Records)^[1 * 16 + 9];
  PB^ := (15 shl 4) or 0;  { high=15, low=0 }
  PB := @PByteArray(TestHM.Records)^[1 * 16 + 10];
  PB^ := 0;

  { Populate record 2: Word=42, Word=999, LongInt=2459842,
    Bit $01=set, Bit $04=set, LowNib=7, HighNib=7, Byte=255 }
  PW := @PByteArray(TestHM.Records)^[2 * 16 + 0];
  PW^ := 42;
  PW := @PByteArray(TestHM.Records)^[2 * 16 + 2];
  PW^ := 999;
  PL := @PByteArray(TestHM.Records)^[2 * 16 + 4];
  PL^ := 2459842;
  PB := @PByteArray(TestHM.Records)^[2 * 16 + 8];
  PB^ := $05;  { bit 0 set, bit 2 set }
  PB := @PByteArray(TestHM.Records)^[2 * 16 + 9];
  PB^ := (7 shl 4) or 7;  { high=7, low=7 }
  PB := @PByteArray(TestHM.Records)^[2 * 16 + 10];
  PB^ := 255;
end;

procedure TeardownTestHeapMap;
begin
  Ok := FreeHeapRecords(TestHM);
end;

procedure TestGetWordValues;
begin
  BeginTest('HeapGetWord - read values');
  AssertEqualsInt(1000, HeapGetWord(TestHM, 0, 1), 'Rec 0 Field 1 = 1000');
  AssertEqualsInt(2000, HeapGetWord(TestHM, 0, 2), 'Rec 0 Field 2 = 2000');
  AssertEqualsInt(0, HeapGetWord(TestHM, 1, 1), 'Rec 1 Field 1 = 0');
  AssertEqualsInt(65535, HeapGetWord(TestHM, 1, 2), 'Rec 1 Field 2 = 65535');
  AssertEqualsInt(42, HeapGetWord(TestHM, 2, 1), 'Rec 2 Field 1 = 42');
  AssertEqualsInt(999, HeapGetWord(TestHM, 2, 2), 'Rec 2 Field 2 = 999');
  EndTest;
end;

procedure TestGetLongIntValues;
begin
  BeginTest('HeapGetLongInt - read values');
  AssertEqualsInt(100000, HeapGetLongInt(TestHM, 0, 3), 'Rec 0 = 100000');
  AssertEqualsInt(0, HeapGetLongInt(TestHM, 1, 3), 'Rec 1 = 0');
  AssertEqualsInt(2459842, HeapGetLongInt(TestHM, 2, 3), 'Rec 2 = 2459842');
  EndTest;
end;

procedure TestGetBitFlagValues;
begin
  BeginTest('HeapGetBitFlag - read flags');
  { Record 0: $01 set, $04 clear }
  AssertTrue(HeapGetBitFlag(TestHM, 0, 4), 'Rec 0 Flag $01 = True');
  AssertFalse(HeapGetBitFlag(TestHM, 0, 5), 'Rec 0 Flag $04 = False');
  { Record 1: $01 clear, $04 set }
  AssertFalse(HeapGetBitFlag(TestHM, 1, 4), 'Rec 1 Flag $01 = False');
  AssertTrue(HeapGetBitFlag(TestHM, 1, 5), 'Rec 1 Flag $04 = True');
  { Record 2: both set }
  AssertTrue(HeapGetBitFlag(TestHM, 2, 4), 'Rec 2 Flag $01 = True');
  AssertTrue(HeapGetBitFlag(TestHM, 2, 5), 'Rec 2 Flag $04 = True');
  EndTest;
end;

procedure TestGetNibbleValues;
begin
  BeginTest('HeapGetNibble - read nibbles');
  { Record 0: low=5, high=12 }
  AssertEqualsInt(5, HeapGetNibble(TestHM, 0, 6), 'Rec 0 LowNib = 5');
  AssertEqualsInt(12, HeapGetNibble(TestHM, 0, 7), 'Rec 0 HighNib = 12');
  { Record 1: low=0, high=15 }
  AssertEqualsInt(0, HeapGetNibble(TestHM, 1, 6), 'Rec 1 LowNib = 0');
  AssertEqualsInt(15, HeapGetNibble(TestHM, 1, 7), 'Rec 1 HighNib = 15');
  { Record 2: low=7, high=7 }
  AssertEqualsInt(7, HeapGetNibble(TestHM, 2, 6), 'Rec 2 LowNib = 7');
  AssertEqualsInt(7, HeapGetNibble(TestHM, 2, 7), 'Rec 2 HighNib = 7');
  EndTest;
end;

procedure TestGetByteValues;
begin
  BeginTest('HeapGetByte - read bytes');
  AssertEqualsInt(200, HeapGetByte(TestHM, 0, 8), 'Rec 0 = 200');
  AssertEqualsInt(0, HeapGetByte(TestHM, 1, 8), 'Rec 1 = 0');
  AssertEqualsInt(255, HeapGetByte(TestHM, 2, 8), 'Rec 2 = 255');
  EndTest;
end;

procedure TestGetOutOfBoundsRecord;
begin
  BeginTest('HeapGet - out of bounds record index');
  AssertEqualsInt(0, HeapGetWord(TestHM, 99, 1), 'OOB record Word = 0');
  AssertEqualsInt(0, HeapGetLongInt(TestHM, 99, 3), 'OOB record LongInt = 0');
  AssertFalse(HeapGetBitFlag(TestHM, 99, 4), 'OOB record BitFlag = False');
  AssertEqualsInt(0, HeapGetNibble(TestHM, 99, 6), 'OOB record Nibble = 0');
  AssertEqualsInt(0, HeapGetByte(TestHM, 99, 8), 'OOB record Byte = 0');
  EndTest;
end;

procedure TestGetOutOfBoundsField;
begin
  BeginTest('HeapGet - out of bounds field index');
  AssertEqualsInt(0, HeapGetWord(TestHM, 0, 0), 'Field 0 Word = 0');
  AssertEqualsInt(0, HeapGetWord(TestHM, 0, 99), 'Field 99 Word = 0');
  AssertEqualsInt(0, HeapGetLongInt(TestHM, 0, 0), 'Field 0 LongInt = 0');
  EndTest;
end;

procedure TestGetWrongType;
begin
  BeginTest('HeapGet - wrong type returns 0/False');
  { Field 1 is Word, not LongInt }
  AssertEqualsInt(0, HeapGetLongInt(TestHM, 0, 1), 'Word field via GetLongInt = 0');
  { Field 3 is LongInt, not Word }
  AssertEqualsInt(0, HeapGetWord(TestHM, 0, 3), 'LongInt field via GetWord = 0');
  { Field 4 is BitFlags, not Byte }
  AssertEqualsInt(0, HeapGetByte(TestHM, 0, 4), 'BitFlags field via GetByte = 0');
  { Field 8 is Byte, not BitFlags }
  AssertFalse(HeapGetBitFlag(TestHM, 0, 8), 'Byte field via GetBitFlag = False');
  EndTest;
end;

{ ================================================================== }
{ Phase 2: DBF-based tests using samples\LARGEDB.DBF                  }
{ ================================================================== }

var
  LargeDbf: PDBFFile;
  LargeHeader: TDBFHeader;
  LargeRowCount: LongInt;
function OpenLargeDb: Boolean;
begin
  LargeDbf := nil;
  OpenLargeDb := False;
  if not DBFFileOpen(LargeDbf, LargeDbPath) then
  begin
    WriteLn('WARNING: Cannot open ', LargeDbPath, ' - skipping Phase 2');
    Exit;
  end;
  if not DBFFileGetHeader(LargeDbf, LargeHeader) then
  begin
    WriteLn('WARNING: Cannot read header - skipping Phase 2');
    Ok := DBFFileClose(LargeDbf);
    Ok := DBFFileDispose(LargeDbf);
    Exit;
  end;
  LargeRowCount := DBFFileGetActualRowCount(LargeDbf);
  OpenLargeDb := True;
end;

procedure CloseLargeDb;
begin
  if LargeDbf <> nil then
  begin
    Ok := DBFFileClose(LargeDbf);
    Ok := DBFFileDispose(LargeDbf);
    LargeDbf := nil;
  end;
end;

{ ------------------------------------------------------------------ }
{ BuildHeapMap tests                                                  }
{ ------------------------------------------------------------------ }

procedure TestBuildHeapMapBasic;
var
  Specs: THeapFieldSpecArray;
  HM: THeapMap;
  YearVal: Word;
begin
  BeginTest('BuildHeapMap - basic load from LARGEDB');
  FillChar(Specs, SizeOf(Specs), 0);
  { Field 1: RecNo as Word }
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;
  { Field 2: YEAR (field 4) as Word }
  Specs[2].DBFFieldIdx := 4;
  Specs[2].HeapFieldType := hftWord;
  { Field 3: MAXPLAY (field 5) as Byte }
  Specs[3].DBFFieldIdx := 5;
  Specs[3].HeapFieldType := hftByte;

  MemoryReport('Before BuildHeapMap basic');
  Ok := BuildHeapMap(LargeDbf, Specs, 3, 8, HM);
  AssertTrue(Ok, 'BuildHeapMap should succeed');
  MemoryReport('After BuildHeapMap basic (heap map live)');
  if LargeRowCount > MaxHeapRecords then
    AssertEqualsInt(MaxHeapRecords, HM.RecordCount,
      'RecordCount capped at MaxHeapRecords')
  else
    AssertEqualsInt(LargeRowCount, HM.RecordCount,
      'RecordCount = total rows');

  { Record 0 should have RecNo = 0 }
  AssertEqualsInt(0, HeapGetWord(HM, 0, 1), 'First record RecNo = 0');

  { Year should be a reasonable value (1970-2100) }
  YearVal := HeapGetWord(HM, 0, 2);
  AssertTrue((YearVal >= 1970) and (YearVal <= 2100),
    'First record Year in reasonable range');

  Ok := FreeHeapRecords(HM);
  MemoryReport('After FreeHeapRecords basic');
  EndTest;
end;

procedure TestBuildHeapMapRecordCount;
var
  Specs: THeapFieldSpecArray;
  HM: THeapMap;
begin
  BeginTest('BuildHeapMap - record count vs DBF size');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;

  MemoryReport('Before BuildHeapMap record count');
  Ok := BuildHeapMap(LargeDbf, Specs, 1, 8, HM);
  AssertTrue(Ok, 'Should succeed');
  MemoryReport('After BuildHeapMap record count (heap map live)');
  AssertTrue(HM.RecordCount > 0, 'Should load some records');
  AssertTrue(HM.RecordCount <= MaxHeapRecords,
    'Should not exceed MaxHeapRecords');
  WriteLn('  Loaded ', HM.RecordCount, ' of ', LargeRowCount, ' records');
  Ok := FreeHeapRecords(HM);
  MemoryReport('After FreeHeapRecords record count');
  EndTest;
end;

procedure TestBuildHeapMapDateJDN;
var
  Specs: THeapFieldSpecArray;
  HM: THeapMap;
  JDN: LongInt;
begin
  BeginTest('BuildHeapMap - date field as JDN LongInt');
  FillChar(Specs, SizeOf(Specs), 0);
  { DATEADD (field 6) as LongInt with JDN conversion }
  Specs[1].DBFFieldIdx := 6;
  Specs[1].HeapFieldType := hftLongInt;
  Specs[1].ConvertToJDN := True;

  MemoryReport('Before BuildHeapMap JDN');
  Ok := BuildHeapMap(LargeDbf, Specs, 1, 8, HM);
  AssertTrue(Ok, 'Should succeed');
  MemoryReport('After BuildHeapMap JDN (heap map live)');
  JDN := HeapGetLongInt(HM, 0, 1);
  { JDN for dates around 2022 should be ~2459xxx }
  AssertTrue(JDN > 2400000, 'JDN should be > 2400000 for modern dates');
  WriteLn('  First record JDN = ', JDN);
  Ok := FreeHeapRecords(HM);
  MemoryReport('After FreeHeapRecords JDN');
  EndTest;
end;

procedure TestBuildHeapMapByteField;
var
  Specs: THeapFieldSpecArray;
  HM: THeapMap;
  MP: Byte;
begin
  BeginTest('BuildHeapMap - MAXPLAY as Byte');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 5;
  Specs[1].HeapFieldType := hftByte;

  Ok := BuildHeapMap(LargeDbf, Specs, 1, 8, HM);
  AssertTrue(Ok, 'Should succeed');
  MP := HeapGetByte(HM, 0, 1);
  AssertTrue(MP <= 255, 'MAXPLAY byte should be <= 255');
  WriteLn('  First record MAXPLAY = ', MP);
  Ok := FreeHeapRecords(HM);
  EndTest;
end;

{ ------------------------------------------------------------------ }
{ Segmented pipeline tests                                            }
{ ------------------------------------------------------------------ }

{ Filter: Year >= 1990 AND Year <= 1999 }
{$F+}
function FilterYear1990s(var HeapMap: THeapMap; RecordIdx: Word): Boolean;
var
  Year: Word;
begin
  Year := HeapGetWord(HeapMap, RecordIdx, 2);
  FilterYear1990s := (Year >= 1990) and (Year <= 1999);
end;

{ Filter: always true (match all) }
function FilterMatchAll(var HeapMap: THeapMap; RecordIdx: Word): Boolean;
begin
  FilterMatchAll := True;
end;

{ Filter: always false (match none) }
function FilterMatchNone(var HeapMap: THeapMap; RecordIdx: Word): Boolean;
begin
  FilterMatchNone := False;
end;
{$F-}

procedure TestSetFilterFunc;
begin
  BeginTest('SetCurrentFilterFunc - set and verify');
  Ok := SetCurrentFilterFunc(FilterYear1990s);
  AssertTrue(Ok, 'Setting valid filter should succeed');
  EndTest;
end;

procedure TestQuerySegmented1990s;
var
  Specs: THeapFieldSpecArray;
  Results: TSegmentedResults;
  I: Integer;
  YearStr: string;
  YearVal: Word;
  RowPtr: Pointer;
  HM: THeapMap;
begin
  BeginTest('QuerySegmented - filter Year 1990-1999');
  MemoryReport('Before 1990s query');
  WriteLn('DBF fields (index:name:type):');
  for I := 1 to LargeHeader.FieldCount do
    WriteLn('  ', I, ': ', LargeHeader.Fields[I].Name, ' (', LargeHeader.Fields[I].FieldType, ')');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;
  Specs[2].DBFFieldIdx := 4;
  Specs[2].HeapFieldType := hftWord;

  if LargeRowCount > 0 then
  begin
    Ok := DBFFileSeekToRow(LargeDbf, 0);
    GetMem(RowPtr, LargeHeader.RecordSize);
    if RowPtr <> nil then
    begin
      Ok := DBFFileReadRow(LargeDbf, RowPtr, LargeHeader.RecordSize);
      YearStr := DBFFieldGetStr(RowPtr, LargeHeader, Specs[2].DBFFieldIdx);
      WriteLn('DBF Year field raw (row 0): "', YearStr, '"');
      FreeMem(RowPtr, LargeHeader.RecordSize);
    end;
  end;

  FillChar(HM, SizeOf(HM), 0);
  Ok := BuildHeapMap(LargeDbf, Specs, 2, 8, HM);
  if Ok then
  begin
    WriteLn('Heap Year samples (first 5 records):');
    for I := 0 to 4 do
    begin
      YearVal := HeapGetWord(HM, I, 2);
      WriteLn('  Heap Year[', I, '] = ', YearVal);
    end;
    Ok := FreeHeapRecords(HM);
  end;

  GetMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  Results.MaxCount := MaxResults;
  Results.Count := 0;
  MemoryReport('After result buffer alloc (1990s)');

  Ok := SetCurrentFilterFunc(FilterYear1990s);
  AssertTrue(Ok, 'Filter set should succeed');

  Ok := QuerySegmented(LargeDbf, Specs, 2, 8, Results);
  MemoryReport('After QuerySegmented 1990s');
  AssertTrue(Ok, 'QuerySegmented should succeed');
  AssertTrue(Results.Count > 0, 'Should find some 1990s games');
  WriteLn('  Found ', Results.Count, ' records with Year 1990-1999');

  { Verify first result is a valid record number }
  if Results.Count > 0 then
    AssertTrue(Results.RecNos^[0] >= 1,
      'First result RecNo should be >= 1');

  FreeMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  MemoryReport('After result buffer free (1990s)');
  EndTest;
end;

procedure TestQuerySegmentedMatchAll;
var
  Specs: THeapFieldSpecArray;
  Results: TSegmentedResults;
begin
  BeginTest('QuerySegmented - match all records');
  MemoryReport('Before match-all query');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;

  GetMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  Results.MaxCount := MaxResults;
  Results.Count := 0;

  Ok := SetCurrentFilterFunc(FilterMatchAll);
  Ok := QuerySegmented(LargeDbf, Specs, 1, 8, Results);
  MemoryReport('After QuerySegmented match-all');
  AssertTrue(Ok, 'Should succeed');
  { Should get MaxResults or total records, whichever is smaller }
  if LargeRowCount >= MaxResults then
    AssertEqualsInt(MaxResults, Results.Count,
      'Match-all should fill result buffer')
  else
    AssertEqualsInt(LargeRowCount, Results.Count,
      'Match-all should return all records');
  WriteLn('  Matched ', Results.Count, ' of ', LargeRowCount, ' records');

  FreeMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  MemoryReport('After result buffer free (match-all)');
  EndTest;
end;

procedure TestQuerySegmentedMatchNone;
var
  Specs: THeapFieldSpecArray;
  Results: TSegmentedResults;
begin
  BeginTest('QuerySegmented - match no records');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;

  GetMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  Results.MaxCount := MaxResults;
  Results.Count := 0;

  Ok := SetCurrentFilterFunc(FilterMatchNone);
  Ok := QuerySegmented(LargeDbf, Specs, 1, 8, Results);
  AssertTrue(Ok, 'Should succeed');
  AssertEqualsInt(0, Results.Count, 'Match-none should return 0 results');

  FreeMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  EndTest;
end;

procedure TestQuerySegmentedNilDbf;
var
  Specs: THeapFieldSpecArray;
  Results: TSegmentedResults;
  NilDbf: PDBFFile;
begin
  BeginTest('QuerySegmented - nil DBF handle');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;

  GetMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  Results.MaxCount := MaxResults;
  Results.Count := 0;

  NilDbf := nil;
  Ok := QuerySegmented(NilDbf, Specs, 1, 8, Results);
  AssertFalse(Ok, 'Should fail with nil DBF');

  FreeMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  EndTest;
end;

procedure TestQuerySegmentedNilResults;
var
  Specs: THeapFieldSpecArray;
  Results: TSegmentedResults;
begin
  BeginTest('QuerySegmented - nil result buffer');
  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;

  Results.RecNos := nil;
  Results.MaxCount := 0;
  Results.Count := 0;

  Ok := SetCurrentFilterFunc(FilterMatchAll);
  Ok := QuerySegmented(LargeDbf, Specs, 1, 8, Results);
  AssertFalse(Ok, 'Should fail with nil result buffer');
  AssertEqualsInt(0, Results.Count, 'Count should remain 0');
  EndTest;
end;

procedure TestQuerySegmentedSegmentation;
var
  Specs: THeapFieldSpecArray;
  Results: TSegmentedResults;
begin
  BeginTest('QuerySegmented - segmentation occurs for large DBF');
  MemoryReport('Before segmentation test');
  AssertTrue(LargeRowCount > MaxHeapRecords,
    'LARGEDB should exceed MaxHeapRecords for this test');
  WriteLn('  LargeDB has ', LargeRowCount,
          ' records (MaxHeapRecords=', MaxHeapRecords, ')');

  FillChar(Specs, SizeOf(Specs), 0);
  Specs[1].DBFFieldIdx := 0;
  Specs[1].HeapFieldType := hftWord;

  GetMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  Results.MaxCount := MaxResults;
  Results.Count := 0;
  MemoryReport('After result buffer alloc (segmentation)');

  Ok := SetCurrentFilterFunc(FilterMatchAll);
  Ok := QuerySegmented(LargeDbf, Specs, 1, 8, Results);
  MemoryReport('After QuerySegmented segmentation');
  AssertTrue(Ok, 'Should succeed');
  { With >4000 records and match-all, results should fill to MaxResults }
  AssertEqualsInt(MaxResults, Results.Count,
    'Should fill result buffer from multi-segment scan');

  FreeMem(Results.RecNos, MaxResults * SizeOf(LongInt));
  MemoryReport('After result buffer free (segmentation)');
  EndTest;
end;

{ ================================================================== }
{ Main program                                                        }
{ ================================================================== }

var
  Phase2Available: Boolean;

begin
  WriteLn('=== TESTHEAP - DBHEAP Unit Tests ===');
  WriteLn;
  ResetAsserts;

  { ---- Phase 1: In-memory tests ---- }
  WriteLn('--- CalculateHeapLayout Tests ---');
  TestLayoutSingleWord;
  TestLayoutSingleLongInt;
  TestLayoutWordAlignment;
  TestLayoutLongIntAlignment;
  TestLayoutBitFlagsSharing;
  TestLayoutNibblePairing;
  TestLayoutThreeNibbles;
  TestLayoutOverflowTarget;
  TestLayoutFiveWords;
  TestLayoutMixedTypes;
  TestLayoutZeroFields;
  MemoryReport('After layout tests');

  WriteLn;
  WriteLn('--- AllocateHeapRecords / FreeHeapRecords Tests ---');
  TestAllocateBasic;
  TestAllocateMaxRecords;
  TestAllocateOverflow;
  TestFreeNilRecords;
  TestAllocateZeroInit;
  MemoryReport('After alloc tests');

  WriteLn;
  WriteLn('--- HeapGet* Accessor Tests ---');
  SetupTestHeapMap;
  TestGetWordValues;
  TestGetLongIntValues;
  TestGetBitFlagValues;
  TestGetNibbleValues;
  TestGetByteValues;
  TestGetOutOfBoundsRecord;
  TestGetOutOfBoundsField;
  TestGetWrongType;
  TeardownTestHeapMap;
  MemoryReport('After accessor tests');

  { ---- Phase 2: DBF-based tests ---- }
  WriteLn;
  WriteLn('--- Phase 2: DBF-based Tests (LARGEDB.DBF) ---');
  Phase2Available := OpenLargeDb;

  if Phase2Available then
  begin
    WriteLn('LARGEDB.DBF opened: ', LargeRowCount, ' records');
    WriteLn;

    WriteLn('--- BuildHeapMap Tests ---');
    TestBuildHeapMapBasic;
    TestBuildHeapMapRecordCount;
    TestBuildHeapMapDateJDN;
    TestBuildHeapMapByteField;
    MemoryReport('After BuildHeapMap tests');

    WriteLn;
    WriteLn('--- Segmented Pipeline Tests ---');
    TestSetFilterFunc;
    TestQuerySegmented1990s;
    TestQuerySegmentedMatchAll;
    TestQuerySegmentedMatchNone;
    TestQuerySegmentedNilDbf;
    TestQuerySegmentedNilResults;
    TestQuerySegmentedSegmentation;
    MemoryReport('After segmented tests');

    CloseLargeDb;
  end
  else
    WriteLn('Phase 2 skipped (LARGEDB.DBF not available)');

  MemoryReport('After cleanup');
  WriteLn;
  PrintSummary;
end.
