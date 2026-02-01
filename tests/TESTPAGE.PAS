{ TESTPAGE.PAS - Comprehensive tests for MemoPage pagination functions }

program TestPageProgram;

{$M 32768,0,98304}  { Stack: 32KB, Heap: 96KB }

uses Assert, DBFUTIL, DBFMemo, MemoPage;

const
  TestMemoFile = 'TPAGE';

var
  Memo: PDBFMemo;
  MP: TMemoPage;
  Buf: TPageBuffer;
  Block1, Block2, Block3, Block4, Block5, Block6: LongInt;
  LinesUsed: Byte;
  Ok: Boolean;

{ Helper: extract line from page buffer, right-trimmed }
function ExtractLine(var B: TPageBuffer; LineIdx: Byte; Width: Byte): string;
var
  S: string;
  I: Byte;
  Last: Integer;
begin
  Last := -1;
  for I := 0 to Width - 1 do
    if B[LineIdx, I] <> ' ' then
      Last := I;
  S := '';
  if Last >= 0 then
    for I := 0 to Last do
      S := S + B[LineIdx, I];
  ExtractLine := S;
end;

{ Helper: check that a line is all spaces }
function IsBlankLine(var B: TPageBuffer; LineIdx: Byte; Width: Byte): Boolean;
var
  I: Byte;
begin
  IsBlankLine := True;
  for I := 0 to Width - 1 do
    if B[LineIdx, I] <> ' ' then
    begin
      IsBlankLine := False;
      Exit;
    end;
end;

{ ------------------------------------------------------------------ }
{ Setup and teardown                                                  }
{ ------------------------------------------------------------------ }

procedure SetupMemoFile;
var
  Memo2Text, Memo4Text: string;
begin
  Memo := nil;
  Ok := DBFMemoCreate(Memo, TestMemoFile);
  if not Ok then
  begin
    WriteLn('FATAL: Cannot create test memo file');
    Halt(1);
  end;

  { Memo 1: Short single-line text }
  Ok := DBFMemoWriteM(Memo, 1, 'Hello World', Block1);

  { Memo 2: Multi-line text with CR/LF }
  Memo2Text := 'Line one' + #13#10 + 'Line two' + #13#10 + 'Line three';
  Ok := DBFMemoWriteM(Memo, 1, Memo2Text, Block2);

  { Memo 3: Long text for word-wrap testing at width 20 }
  { 'The quick brown fox jumps over the lazy dog' = 43 chars }
  Ok := DBFMemoWriteM(Memo, 1,
    'The quick brown fox jumps over the lazy dog', Block3);

  { Memo 4: Multi-page text (12 lines, LinesPerPage=4 gives 3 pages) }
  Memo4Text := 'L01' + #13#10 + 'L02' + #13#10 + 'L03' + #13#10 +
               'L04' + #13#10 + 'L05' + #13#10 + 'L06' + #13#10 +
               'L07' + #13#10 + 'L08' + #13#10 + 'L09' + #13#10 +
               'L10' + #13#10 + 'L11' + #13#10 + 'L12';
  Ok := DBFMemoWriteM(Memo, 1, Memo4Text, Block4);

  { Memo 5: Empty text }
  Ok := DBFMemoWriteM(Memo, 1, '', Block5);

  { Memo 6: No-space text for hard wrap at width 5 }
  { 'ABCDEFGHIJKLMNO' = 15 chars, 3 lines of 5 at width 5 }
  Ok := DBFMemoWriteM(Memo, 1, 'ABCDEFGHIJKLMNO', Block6);

  WriteLn('Setup: B1=', Block1, ' B2=', Block2, ' B3=', Block3,
          ' B4=', Block4, ' B5=', Block5, ' B6=', Block6);
end;

procedure CleanupMemoFile;
begin
  if Memo <> nil then
  begin
    Ok := DBFMemoClose(Memo);
    Ok := DBFMemoDispose(Memo);
  end;
end;

{ ================================================================== }
{ MPInit tests                                                        }
{ ================================================================== }

procedure TestInitValidShort;
begin
  BeginTest('MPInit valid short text');
  Ok := MPInit(MP, Memo, Block1, 40, 10);
  AssertTrue(Ok, 'Should succeed for valid short text');
  AssertEqualsInt(1, MPGetTotalLines(MP), 'TotalLines should be 1');
  AssertEqualsInt(1, MPGetTotalPages(MP), 'TotalPages should be 1');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'CurrentPage should be 0');
  EndTest;
end;

procedure TestInitValidMultiLine;
begin
  BeginTest('MPInit valid multi-line text');
  Ok := MPInit(MP, Memo, Block2, 40, 10);
  AssertTrue(Ok, 'Should succeed for multi-line text');
  AssertEqualsInt(3, MPGetTotalLines(MP), 'TotalLines should be 3');
  AssertEqualsInt(1, MPGetTotalPages(MP), '3 lines / 10 per page = 1 page');
  EndTest;
end;

procedure TestInitWordWrap;
begin
  BeginTest('MPInit word-wrap text width 20');
  Ok := MPInit(MP, Memo, Block3, 20, 10);
  AssertTrue(Ok, 'Should succeed for word-wrap text');
  AssertEqualsInt(3, MPGetTotalLines(MP), '43 chars at width 20 = 3 lines');
  AssertEqualsInt(1, MPGetTotalPages(MP), '3 lines / 10 per page = 1 page');
  EndTest;
end;

procedure TestInitMultiPage;
begin
  BeginTest('MPInit multi-page text');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Should succeed for multi-page text');
  AssertEqualsInt(12, MPGetTotalLines(MP), 'TotalLines should be 12');
  AssertEqualsInt(3, MPGetTotalPages(MP), '12 lines / 4 per page = 3 pages');
  EndTest;
end;

procedure TestInitEmptyMemo;
begin
  BeginTest('MPInit empty memo');
  Ok := MPInit(MP, Memo, Block5, 40, 10);
  AssertTrue(Ok, 'Should succeed for empty memo');
  AssertEqualsInt(0, MPGetTotalLines(MP), 'Empty memo = 0 lines');
  AssertEqualsInt(1, MPGetTotalPages(MP), 'Empty memo still has 1 page');
  EndTest;
end;

procedure TestInitHardWrap;
begin
  BeginTest('MPInit hard-wrap no-space text');
  Ok := MPInit(MP, Memo, Block6, 5, 10);
  AssertTrue(Ok, 'Should succeed for hard-wrap text');
  AssertEqualsInt(3, MPGetTotalLines(MP), '15 chars / 5 width = 3 lines');
  AssertEqualsInt(1, MPGetTotalPages(MP), '3 lines / 10 per page = 1 page');
  EndTest;
end;

procedure TestInitZeroLineWidth;
begin
  BeginTest('MPInit zero LineWidth');
  Ok := MPInit(MP, Memo, Block1, 0, 10);
  AssertFalse(Ok, 'Should fail with zero LineWidth');
  EndTest;
end;

procedure TestInitZeroLinesPerPage;
begin
  BeginTest('MPInit zero LinesPerPage');
  Ok := MPInit(MP, Memo, Block1, 40, 0);
  AssertFalse(Ok, 'Should fail with zero LinesPerPage');
  EndTest;
end;

procedure TestInitExcessiveLineWidth;
begin
  BeginTest('MPInit LineWidth exceeds MAX');
  Ok := MPInit(MP, Memo, Block1, MP_MAX_LINE_WIDTH + 1, 10);
  AssertFalse(Ok, 'Should fail with LineWidth > MAX');
  EndTest;
end;

procedure TestInitExcessiveLinesPerPage;
begin
  BeginTest('MPInit LinesPerPage exceeds MAX');
  Ok := MPInit(MP, Memo, Block1, 40, MP_MAX_LINES_PER_PAGE + 1);
  AssertFalse(Ok, 'Should fail with LinesPerPage > MAX');
  EndTest;
end;

procedure TestInitInvalidBlockZero;
begin
  BeginTest('MPInit StartBlock 0');
  Ok := MPInit(MP, Memo, 0, 40, 10);
  AssertFalse(Ok, 'Should fail with StartBlock 0');
  EndTest;
end;

procedure TestInitInvalidBlockHigh;
begin
  BeginTest('MPInit StartBlock out of range');
  Ok := MPInit(MP, Memo, 9999, 40, 10);
  AssertFalse(Ok, 'Should fail with out-of-range StartBlock');
  EndTest;
end;

procedure TestInitMaxLineWidth;
begin
  BeginTest('MPInit at max LineWidth');
  Ok := MPInit(MP, Memo, Block1, MP_MAX_LINE_WIDTH, 10);
  AssertTrue(Ok, 'Should succeed at max LineWidth');
  EndTest;
end;

procedure TestInitMaxLinesPerPage;
begin
  BeginTest('MPInit at max LinesPerPage');
  Ok := MPInit(MP, Memo, Block1, 40, MP_MAX_LINES_PER_PAGE);
  AssertTrue(Ok, 'Should succeed at max LinesPerPage');
  EndTest;
end;

procedure TestInitDifferentWidths;
var
  Lines40, Lines10: Word;
begin
  BeginTest('MPInit same text different widths');
  Ok := MPInit(MP, Memo, Block3, 40, 10);
  AssertTrue(Ok, 'Init at width 40 should succeed');
  Lines40 := MPGetTotalLines(MP);

  Ok := MPInit(MP, Memo, Block3, 10, 10);
  AssertTrue(Ok, 'Init at width 10 should succeed');
  Lines10 := MPGetTotalLines(MP);

  AssertTrue(Lines10 > Lines40,
    'Width 10 should produce more lines than width 40');
  EndTest;
end;

{ ================================================================== }
{ MPGetPage tests                                                     }
{ ================================================================== }

procedure TestGetPageShortText;
var
  Line: string;
begin
  BeginTest('MPGetPage short text content');
  Ok := MPInit(MP, Memo, Block1, 40, 10);
  AssertTrue(Ok, 'Init should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertEqualsInt(1, LinesUsed, 'Should fill 1 line');
  Line := ExtractLine(Buf, 0, 40);
  AssertEqualsStr('Hello World', Line, 'Line 0 content');
  EndTest;
end;

procedure TestGetPagePadding;
begin
  BeginTest('MPGetPage padding with spaces');
  Ok := MPInit(MP, Memo, Block1, 40, 10);
  AssertTrue(Ok, 'Init should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertTrue(Buf[0, 39] = ' ', 'Last char of text line should be space');
  AssertTrue(IsBlankLine(Buf, 1, 40), 'Unused line 1 should be blank');
  AssertTrue(IsBlankLine(Buf, 9, 40), 'Last line of page should be blank');
  EndTest;
end;

procedure TestGetPageMultiLine;
begin
  BeginTest('MPGetPage multi-line content');
  Ok := MPInit(MP, Memo, Block2, 40, 10);
  AssertTrue(Ok, 'Init should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertEqualsInt(3, LinesUsed, 'Should fill 3 lines');
  AssertEqualsStr('Line one', ExtractLine(Buf, 0, 40), 'Line 0');
  AssertEqualsStr('Line two', ExtractLine(Buf, 1, 40), 'Line 1');
  AssertEqualsStr('Line three', ExtractLine(Buf, 2, 40), 'Line 2');
  EndTest;
end;

procedure TestGetPageWordWrap;
begin
  BeginTest('MPGetPage word-wrap content');
  Ok := MPInit(MP, Memo, Block3, 20, 10);
  AssertTrue(Ok, 'Init should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertEqualsInt(3, LinesUsed, 'Word-wrap should produce 3 lines');
  AssertTrue(Buf[0, 0] = 'T', 'Line 0 starts with T');
  AssertTrue(Buf[0, 4] = 'q', 'Line 0 col 4 = q');
  AssertEqualsStr('dog', ExtractLine(Buf, 2, 20), 'Last line = dog');
  EndTest;
end;

procedure TestGetPageHardWrap;
begin
  BeginTest('MPGetPage hard-wrap no spaces');
  Ok := MPInit(MP, Memo, Block6, 5, 10);
  AssertTrue(Ok, 'Init should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertEqualsInt(3, LinesUsed, 'Hard-wrap should produce 3 lines');
  AssertEqualsStr('ABCDE', ExtractLine(Buf, 0, 5), 'Line 0 = ABCDE');
  AssertEqualsStr('FGHIJ', ExtractLine(Buf, 1, 5), 'Line 1 = FGHIJ');
  AssertEqualsStr('KLMNO', ExtractLine(Buf, 2, 5), 'Line 2 = KLMNO');
  EndTest;
end;

procedure TestGetPageEmpty;
begin
  BeginTest('MPGetPage empty memo');
  Ok := MPInit(MP, Memo, Block5, 40, 10);
  AssertTrue(Ok, 'Init should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertEqualsInt(0, LinesUsed, 'Empty memo should fill 0 lines');
  AssertTrue(IsBlankLine(Buf, 0, 40), 'Line 0 should be blank');
  EndTest;
end;

procedure TestGetPageFirstOfMulti;
begin
  BeginTest('MPGetPage first page of multi-page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertEqualsInt(4, LinesUsed, 'First page should fill 4 lines');
  AssertEqualsStr('L01', ExtractLine(Buf, 0, 40), 'Page 0, Line 0');
  AssertEqualsStr('L02', ExtractLine(Buf, 1, 40), 'Page 0, Line 1');
  AssertEqualsStr('L03', ExtractLine(Buf, 2, 40), 'Page 0, Line 2');
  AssertEqualsStr('L04', ExtractLine(Buf, 3, 40), 'Page 0, Line 3');
  EndTest;
end;

procedure TestGetPageMiddle;
begin
  BeginTest('MPGetPage middle page content');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 1);
  AssertTrue(Ok, 'GotoPage 1 should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertEqualsInt(4, LinesUsed, 'Middle page should fill 4 lines');
  AssertEqualsStr('L05', ExtractLine(Buf, 0, 40), 'Page 1, Line 0');
  AssertEqualsStr('L06', ExtractLine(Buf, 1, 40), 'Page 1, Line 1');
  AssertEqualsStr('L07', ExtractLine(Buf, 2, 40), 'Page 1, Line 2');
  AssertEqualsStr('L08', ExtractLine(Buf, 3, 40), 'Page 1, Line 3');
  EndTest;
end;

procedure TestGetPageLast;
begin
  BeginTest('MPGetPage last page content');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 2);
  AssertTrue(Ok, 'GotoPage 2 should succeed');
  LinesUsed := MPGetPage(MP, Buf);
  AssertEqualsInt(4, LinesUsed, 'Last page should fill 4 lines');
  AssertEqualsStr('L09', ExtractLine(Buf, 0, 40), 'Page 2, Line 0');
  AssertEqualsStr('L10', ExtractLine(Buf, 1, 40), 'Page 2, Line 1');
  AssertEqualsStr('L11', ExtractLine(Buf, 2, 40), 'Page 2, Line 2');
  AssertEqualsStr('L12', ExtractLine(Buf, 3, 40), 'Page 2, Line 3');
  EndTest;
end;

{ ================================================================== }
{ MPPageDown tests                                                    }
{ ================================================================== }

procedure TestPageDownFromFirst;
begin
  BeginTest('MPPageDown from first page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Start at page 0');
  Ok := MPPageDown(MP);
  AssertTrue(Ok, 'PageDown should succeed from page 0');
  AssertEqualsInt(1, MPGetCurrentPage(MP), 'Now on page 1');
  EndTest;
end;

procedure TestPageDownFromMiddle;
begin
  BeginTest('MPPageDown from middle page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 1);
  Ok := MPPageDown(MP);
  AssertTrue(Ok, 'PageDown should succeed from page 1');
  AssertEqualsInt(2, MPGetCurrentPage(MP), 'Now on page 2');
  EndTest;
end;

procedure TestPageDownFromLast;
begin
  BeginTest('MPPageDown from last page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 2);
  Ok := MPPageDown(MP);
  AssertFalse(Ok, 'PageDown should fail from last page');
  AssertEqualsInt(2, MPGetCurrentPage(MP), 'Should remain on page 2');
  EndTest;
end;

procedure TestPageDownSinglePage;
begin
  BeginTest('MPPageDown on single-page memo');
  Ok := MPInit(MP, Memo, Block1, 40, 10);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPPageDown(MP);
  AssertFalse(Ok, 'PageDown should fail on single-page memo');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Should remain on page 0');
  EndTest;
end;

procedure TestPageDownSequential;
begin
  BeginTest('MPPageDown sequential through all pages');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPPageDown(MP);
  AssertTrue(Ok, 'First PageDown should succeed');
  AssertEqualsInt(1, MPGetCurrentPage(MP), 'After first down: page 1');
  Ok := MPPageDown(MP);
  AssertTrue(Ok, 'Second PageDown should succeed');
  AssertEqualsInt(2, MPGetCurrentPage(MP), 'After second down: page 2');
  Ok := MPPageDown(MP);
  AssertFalse(Ok, 'Third PageDown should fail (at end)');
  AssertEqualsInt(2, MPGetCurrentPage(MP), 'Should remain on page 2');
  EndTest;
end;

{ ================================================================== }
{ MPPageUp tests                                                      }
{ ================================================================== }

procedure TestPageUpFromFirst;
begin
  BeginTest('MPPageUp from first page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPPageUp(MP);
  AssertFalse(Ok, 'PageUp should fail from page 0');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Should remain on page 0');
  EndTest;
end;

procedure TestPageUpFromSecond;
begin
  BeginTest('MPPageUp from second page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 1);
  Ok := MPPageUp(MP);
  AssertTrue(Ok, 'PageUp should succeed from page 1');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Now on page 0');
  EndTest;
end;

procedure TestPageUpFromLast;
begin
  BeginTest('MPPageUp from last page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 2);
  Ok := MPPageUp(MP);
  AssertTrue(Ok, 'PageUp should succeed from page 2');
  AssertEqualsInt(1, MPGetCurrentPage(MP), 'Now on page 1');
  EndTest;
end;

procedure TestPageUpSequential;
begin
  BeginTest('MPPageUp sequential from last to first');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 2);
  Ok := MPPageUp(MP);
  AssertTrue(Ok, 'First PageUp should succeed');
  AssertEqualsInt(1, MPGetCurrentPage(MP), 'After first up: page 1');
  Ok := MPPageUp(MP);
  AssertTrue(Ok, 'Second PageUp should succeed');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'After second up: page 0');
  Ok := MPPageUp(MP);
  AssertFalse(Ok, 'Third PageUp should fail (at start)');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Should remain on page 0');
  EndTest;
end;

procedure TestPageUpDownRoundTrip;
begin
  BeginTest('MPPageDown then MPPageUp round trip');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPPageDown(MP);
  AssertEqualsInt(1, MPGetCurrentPage(MP), 'After down: page 1');
  Ok := MPPageUp(MP);
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'After up: page 0');
  EndTest;
end;

{ ================================================================== }
{ MPGotoPage tests                                                    }
{ ================================================================== }

procedure TestGotoPageValid;
begin
  BeginTest('MPGotoPage valid page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 1);
  AssertTrue(Ok, 'GotoPage 1 should succeed');
  AssertEqualsInt(1, MPGetCurrentPage(MP), 'Should be on page 1');
  EndTest;
end;

procedure TestGotoPageFirst;
begin
  BeginTest('MPGotoPage to page 0');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 2);
  Ok := MPGotoPage(MP, 0);
  AssertTrue(Ok, 'GotoPage 0 should succeed');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Should be on page 0');
  EndTest;
end;

procedure TestGotoPageLast;
begin
  BeginTest('MPGotoPage to last page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 2);
  AssertTrue(Ok, 'GotoPage 2 (last) should succeed');
  AssertEqualsInt(2, MPGetCurrentPage(MP), 'Should be on page 2');
  EndTest;
end;

procedure TestGotoPageOutOfRange;
begin
  BeginTest('MPGotoPage out of range');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 3);
  AssertFalse(Ok, 'GotoPage 3 should fail (only 3 pages: 0-2)');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Should remain on page 0');
  EndTest;
end;

procedure TestGotoPageLargeInvalid;
begin
  BeginTest('MPGotoPage very large page number');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 65535);
  AssertFalse(Ok, 'GotoPage 65535 should fail');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Should remain on page 0');
  EndTest;
end;

procedure TestGotoPageSamePage;
begin
  BeginTest('MPGotoPage to current page');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPGotoPage(MP, 0);
  AssertTrue(Ok, 'GotoPage 0 (current) should succeed');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'Should remain on page 0');
  EndTest;
end;

{ ================================================================== }
{ MPGetCurrentPage / MPGetTotalPages / MPGetTotalLines tests          }
{ ================================================================== }

procedure TestInfoAfterInit;
begin
  BeginTest('Info functions after init');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'CurrentPage = 0 after init');
  AssertEqualsInt(3, MPGetTotalPages(MP), 'TotalPages = 3');
  AssertEqualsInt(12, MPGetTotalLines(MP), 'TotalLines = 12');
  EndTest;
end;

procedure TestInfoAfterNavigation;
begin
  BeginTest('Info functions after navigation');
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  Ok := MPPageDown(MP);
  AssertEqualsInt(1, MPGetCurrentPage(MP), 'CurrentPage = 1 after down');
  AssertEqualsInt(3, MPGetTotalPages(MP), 'TotalPages unchanged');
  AssertEqualsInt(12, MPGetTotalLines(MP), 'TotalLines unchanged');
  EndTest;
end;

procedure TestInfoSinglePage;
begin
  BeginTest('Info functions for single-page memo');
  Ok := MPInit(MP, Memo, Block1, 40, 10);
  AssertTrue(Ok, 'Init should succeed');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'CurrentPage = 0');
  AssertEqualsInt(1, MPGetTotalPages(MP), 'TotalPages = 1');
  AssertEqualsInt(1, MPGetTotalLines(MP), 'TotalLines = 1');
  EndTest;
end;

procedure TestInfoEmptyMemo;
begin
  BeginTest('Info functions for empty memo');
  Ok := MPInit(MP, Memo, Block5, 40, 10);
  AssertTrue(Ok, 'Init should succeed');
  AssertEqualsInt(0, MPGetCurrentPage(MP), 'CurrentPage = 0');
  AssertEqualsInt(1, MPGetTotalPages(MP), 'TotalPages = 1 for empty');
  AssertEqualsInt(0, MPGetTotalLines(MP), 'TotalLines = 0 for empty');
  EndTest;
end;

procedure TestInfoReinitChangesValues;
var
  Lines1, Lines2: Word;
begin
  BeginTest('Re-init with different text changes info');
  Ok := MPInit(MP, Memo, Block1, 40, 10);
  Lines1 := MPGetTotalLines(MP);
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  Lines2 := MPGetTotalLines(MP);
  AssertTrue(Lines2 > Lines1,
    'Different memo should give different TotalLines');
  EndTest;
end;

procedure TestPageCountExactDivision;
begin
  BeginTest('Page count with exact division');
  { 12 lines / 4 per page = exactly 3 pages }
  Ok := MPInit(MP, Memo, Block4, 40, 4);
  AssertTrue(Ok, 'Init should succeed');
  AssertEqualsInt(3, MPGetTotalPages(MP), '12/4 = exactly 3 pages');
  EndTest;
end;

procedure TestPageCountNonExactDivision;
begin
  BeginTest('Page count with non-exact division');
  { 12 lines / 5 per page = 2 full + 2 leftover = 3 pages }
  Ok := MPInit(MP, Memo, Block4, 40, 5);
  AssertTrue(Ok, 'Init should succeed');
  AssertEqualsInt(3, MPGetTotalPages(MP), '12/5 rounds up to 3 pages');
  EndTest;
end;

{ ================================================================== }
{ Main program                                                        }
{ ================================================================== }

begin
  WriteLn('=== TESTPAGE - MemoPage Unit Tests ===');
  WriteLn;
  ResetAsserts;

  SetupMemoFile;
  MemoryReport('After setup');

  { MPInit tests }
  WriteLn;
  WriteLn('--- MPInit Tests ---');
  TestInitValidShort;
  TestInitValidMultiLine;
  TestInitWordWrap;
  TestInitMultiPage;
  TestInitEmptyMemo;
  TestInitHardWrap;
  TestInitZeroLineWidth;
  TestInitZeroLinesPerPage;
  TestInitExcessiveLineWidth;
  TestInitExcessiveLinesPerPage;
  TestInitInvalidBlockZero;
  TestInitInvalidBlockHigh;
  TestInitMaxLineWidth;
  TestInitMaxLinesPerPage;
  TestInitDifferentWidths;
  MemoryReport('After MPInit tests');

  { MPGetPage tests }
  WriteLn;
  WriteLn('--- MPGetPage Tests ---');
  TestGetPageShortText;
  TestGetPagePadding;
  TestGetPageMultiLine;
  TestGetPageWordWrap;
  TestGetPageHardWrap;
  TestGetPageEmpty;
  TestGetPageFirstOfMulti;
  TestGetPageMiddle;
  TestGetPageLast;
  MemoryReport('After MPGetPage tests');

  { MPPageDown tests }
  WriteLn;
  WriteLn('--- MPPageDown Tests ---');
  TestPageDownFromFirst;
  TestPageDownFromMiddle;
  TestPageDownFromLast;
  TestPageDownSinglePage;
  TestPageDownSequential;
  MemoryReport('After MPPageDown tests');

  { MPPageUp tests }
  WriteLn;
  WriteLn('--- MPPageUp Tests ---');
  TestPageUpFromFirst;
  TestPageUpFromSecond;
  TestPageUpFromLast;
  TestPageUpSequential;
  TestPageUpDownRoundTrip;
  MemoryReport('After MPPageUp tests');

  { MPGotoPage tests }
  WriteLn;
  WriteLn('--- MPGotoPage Tests ---');
  TestGotoPageValid;
  TestGotoPageFirst;
  TestGotoPageLast;
  TestGotoPageOutOfRange;
  TestGotoPageLargeInvalid;
  TestGotoPageSamePage;
  MemoryReport('After MPGotoPage tests');

  { Info function tests }
  WriteLn;
  WriteLn('--- Info Function Tests ---');
  TestInfoAfterInit;
  TestInfoAfterNavigation;
  TestInfoSinglePage;
  TestInfoEmptyMemo;
  TestInfoReinitChangesValues;
  TestPageCountExactDivision;
  TestPageCountNonExactDivision;
  MemoryReport('After info tests');

  { Cleanup }
  CleanupMemoFile;
  MemoryReport('After cleanup');

  WriteLn;
  PrintSummary;
end.
