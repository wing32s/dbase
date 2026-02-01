unit MemoPage;

{ Word-wrap and pagination for memo fields }
{ Returns padded fixed-width lines for easy display }

interface

uses DBFMEMO;

const
  MP_MAX_LINE_WIDTH = 80;
  MP_MAX_LINES_PER_PAGE = 50;
  MP_READ_BUF_SIZE = 1024;

type
  TPageBuffer = array[0..MP_MAX_LINES_PER_PAGE - 1, 0..MP_MAX_LINE_WIDTH - 1] of Char;

  TMemoPage = record
    Memo: PDBFMemo;             { Memo handle }
    StartBlock: LongInt;        { Memo start block }
    MemoLen: LongInt;           { Total memo length in bytes }
    LineWidth: Byte;            { App-defined chars per line }
    LinesPerPage: Byte;         { App-defined lines per page }
    TotalLines: Word;           { Calculated wrapped line count }
    CurrentPage: Word;          { Current page number (0-based) }
    TotalPages: Word;           { Calculated page count }
  end;

{ Initialize viewer for a memo field - counts total lines }
function MPInit(var MP: TMemoPage;
                Memo: PDBFMemo;
                StartBlock: LongInt;
                LineWidth, LinesPerPage: Byte): Boolean;

{ Get current page into padded buffer, returns lines filled }
function MPGetPage(var MP: TMemoPage; var Buf: TPageBuffer): Byte;

{ Navigation - returns True if page changed }
function MPPageDown(var MP: TMemoPage): Boolean;
function MPPageUp(var MP: TMemoPage): Boolean;
function MPGotoPage(var MP: TMemoPage; PageNum: Word): Boolean;

{ Info }
function MPGetCurrentPage(var MP: TMemoPage): Word;
function MPGetTotalPages(var MP: TMemoPage): Word;
function MPGetTotalLines(var MP: TMemoPage): Word;

implementation

{ Count total wrapped lines - single pass through memo }
{ Uses word-wrap: breaks at spaces when possible }
function CountLines(var MP: TMemoPage): Word;
var
  Buf: array[0..MP_READ_BUF_SIZE - 1] of Char;
  FilePos: LongInt;
  BufLen, BufPos: Word;
  LineLen: Byte;
  LastSpaceLen: Byte;      { LineLen at last space }
  CharsAfterSpace: Byte;   { Characters after last space }
  Count: Word;
  C: Char;
  ReadLen: Word;
  Done: Boolean;
  SkipLF: Boolean;
begin
  Count := 0;
  FilePos := 0;
  LineLen := 0;
  LastSpaceLen := 0;
  CharsAfterSpace := 0;
  Done := False;
  SkipLF := False;

  while (FilePos < MP.MemoLen) and (not Done) do
  begin
    { Calculate read length }
    BufLen := MP_READ_BUF_SIZE;
    if FilePos + BufLen > MP.MemoLen then
      BufLen := MP.MemoLen - FilePos;

    { Read chunk }
    if not DBFMemoReadChunkM(MP.Memo, MP.StartBlock,
                            FilePos, Buf, BufLen, ReadLen) then
      Done := True
    else if ReadLen = 0 then
      Done := True
    else
    begin
      { Scan chunk for line breaks }
      for BufPos := 0 to ReadLen - 1 do
      begin
        C := Buf[BufPos];

        { Skip LF after CR }
        if SkipLF then
        begin
          SkipLF := False;
          if C = #10 then
          begin
            { Skip this character }
          end
          else
          begin
            { Process normally below }
            if C = #13 then
            begin
              Inc(Count);
              LineLen := 0;
              LastSpaceLen := 0;
              CharsAfterSpace := 0;
              SkipLF := True;
            end
            else if C = ' ' then
            begin
              Inc(LineLen);
              LastSpaceLen := LineLen;
              CharsAfterSpace := 0;
              if LineLen >= MP.LineWidth then
              begin
                Inc(Count);
                LineLen := 0;
                LastSpaceLen := 0;
              end;
            end
            else
            begin
              Inc(LineLen);
              Inc(CharsAfterSpace);
              if LineLen >= MP.LineWidth then
              begin
                Inc(Count);
                if (LastSpaceLen > 0) and (CharsAfterSpace < MP.LineWidth) then
                  LineLen := CharsAfterSpace
                else
                  LineLen := 0;
                LastSpaceLen := 0;
                CharsAfterSpace := LineLen;
              end;
            end;
          end;
        end
        else if C = #13 then
        begin
          Inc(Count);
          LineLen := 0;
          LastSpaceLen := 0;
          CharsAfterSpace := 0;
          SkipLF := True;
        end
        else if C = #10 then
        begin
          Inc(Count);
          LineLen := 0;
          LastSpaceLen := 0;
          CharsAfterSpace := 0;
        end
        else if C = ' ' then
        begin
          Inc(LineLen);
          LastSpaceLen := LineLen;
          CharsAfterSpace := 0;
          if LineLen >= MP.LineWidth then
          begin
            Inc(Count);
            LineLen := 0;
            LastSpaceLen := 0;
          end;
        end
        else
        begin
          Inc(LineLen);
          Inc(CharsAfterSpace);
          if LineLen >= MP.LineWidth then
          begin
            Inc(Count);
            { Word wrap: carry over characters after last space }
            if (LastSpaceLen > 0) and (CharsAfterSpace < MP.LineWidth) then
              LineLen := CharsAfterSpace
            else
              LineLen := 0;  { No space or word too long - hard break }
            LastSpaceLen := 0;
            CharsAfterSpace := LineLen;
          end;
        end;
      end;

      Inc(FilePos, ReadLen);
    end;
  end;

  { Count final partial line }
  if LineLen > 0 then
    Inc(Count);

  { At least one line if memo has content }
  if (Count = 0) and (MP.MemoLen > 0) then
    Count := 1;

  CountLines := Count;
end;

function MPInit(var MP: TMemoPage;
                Memo: PDBFMemo;
                StartBlock: LongInt;
                LineWidth, LinesPerPage: Byte): Boolean;
var
  MemoType: LongInt;
  MemoLen: LongInt;
begin
  MPInit := False;

  { Validate parameters }
  if (LineWidth = 0) or (LineWidth > MP_MAX_LINE_WIDTH) then Exit;
  if (LinesPerPage = 0) or (LinesPerPage > MP_MAX_LINES_PER_PAGE) then Exit;

  { Get memo info }
  if not DBFMemoGetInfoM(Memo, StartBlock, MemoType, MemoLen) then Exit;

  { Initialize record }
  MP.Memo := Memo;
  MP.StartBlock := StartBlock;
  MP.MemoLen := MemoLen;
  MP.LineWidth := LineWidth;
  MP.LinesPerPage := LinesPerPage;
  MP.CurrentPage := 0;

  { Count total lines }
  MP.TotalLines := CountLines(MP);

  { Calculate pages }
  if MP.TotalLines = 0 then
    MP.TotalPages := 1
  else
    MP.TotalPages := (MP.TotalLines + LinesPerPage - 1) div LinesPerPage;

  MPInit := True;
end;

{ Get page of padded text with word wrap }
function MPGetPage(var MP: TMemoPage; var Buf: TPageBuffer): Byte;
var
  ReadBuf: array[0..MP_READ_BUF_SIZE - 1] of Char;
  LineBuf: array[0..MP_MAX_LINE_WIDTH - 1] of Char;  { Buffer current line }
  FilePos: LongInt;
  ReadLen: Word;
  BufPos: Word;
  TargetLine, CurrentLine: Word;
  LineNum: Byte;
  ColNum: Byte;
  LastSpaceCol: Byte;      { Column of last space }
  C: Char;
  InTarget: Boolean;
  SkipLF: Boolean;
  Done: Boolean;
  I: Byte;
  WrapCol: Byte;
begin
  { Clear output buffer with spaces }
  FillChar(Buf, SizeOf(Buf), ' ');

  TargetLine := MP.CurrentPage * MP.LinesPerPage;
  CurrentLine := 0;
  LineNum := 0;
  ColNum := 0;
  LastSpaceCol := 0;
  FilePos := 0;
  InTarget := False;
  SkipLF := False;
  Done := False;
  FillChar(LineBuf, SizeOf(LineBuf), ' ');

  while (FilePos < MP.MemoLen) and (LineNum < MP.LinesPerPage) and (not Done) do
  begin
    { Read chunk }
    if not DBFMemoReadChunkM(MP.Memo, MP.StartBlock,
                            FilePos, ReadBuf, MP_READ_BUF_SIZE, ReadLen) then
      Done := True
    else if ReadLen = 0 then
      Done := True
    else
    begin
      { Process chunk }
      BufPos := 0;
      while (BufPos < ReadLen) and (LineNum < MP.LinesPerPage) do
      begin
        C := ReadBuf[BufPos];

        { Skip LF after CR }
        if SkipLF and (C = #10) then
        begin
          SkipLF := False;
          Inc(BufPos);
        end
        else
        begin
          SkipLF := False;

          { Check if we've reached target range }
          InTarget := (CurrentLine >= TargetLine);

          { Hard line break }
          if C in [#13, #10] then
          begin
            { Output buffered line if in target }
            if InTarget then
            begin
              for I := 0 to ColNum - 1 do
                Buf[LineNum, I] := LineBuf[I];
              Inc(LineNum);
            end;
            Inc(CurrentLine);
            ColNum := 0;
            LastSpaceCol := 0;
            FillChar(LineBuf, SizeOf(LineBuf), ' ');
            if C = #13 then
              SkipLF := True;
            Inc(BufPos);
          end
          else
          begin
            { Buffer the character }
            if ColNum < MP.LineWidth then
            begin
              LineBuf[ColNum] := C;
              if C = ' ' then
                LastSpaceCol := ColNum + 1;  { Position after space }
            end;

            Inc(ColNum);

            { Check for wrap }
            if ColNum >= MP.LineWidth then
            begin
              { Determine wrap point }
              if (LastSpaceCol > 0) and (LastSpaceCol < MP.LineWidth) then
                WrapCol := LastSpaceCol  { Wrap at word boundary }
              else
                WrapCol := MP.LineWidth; { Hard wrap - no space found }

              { Output line up to wrap point if in target }
              if InTarget then
              begin
                for I := 0 to WrapCol - 1 do
                  Buf[LineNum, I] := LineBuf[I];
                Inc(LineNum);
              end;
              Inc(CurrentLine);

              { Carry over remainder to new line buffer }
              if WrapCol < ColNum then
              begin
                for I := 0 to ColNum - WrapCol - 1 do
                  LineBuf[I] := LineBuf[WrapCol + I];
                for I := ColNum - WrapCol to MP_MAX_LINE_WIDTH - 1 do
                  LineBuf[I] := ' ';
                ColNum := ColNum - WrapCol;
              end
              else
              begin
                FillChar(LineBuf, SizeOf(LineBuf), ' ');
                ColNum := 0;
              end;
              LastSpaceCol := 0;

              { Re-check InTarget for carried text }
              InTarget := (CurrentLine >= TargetLine);
            end;

            Inc(BufPos);
          end;
        end;
      end;

      Inc(FilePos, ReadLen);
    end;
  end;

  { Output any remaining buffered content }
  if (ColNum > 0) and InTarget and (LineNum < MP.LinesPerPage) then
  begin
    for I := 0 to ColNum - 1 do
      Buf[LineNum, I] := LineBuf[I];
    Inc(LineNum);
  end;

  { Return actual lines on this page }
  MPGetPage := LineNum;
end;

function MPPageDown(var MP: TMemoPage): Boolean;
begin
  MPPageDown := False;
  if MP.CurrentPage < MP.TotalPages - 1 then
  begin
    Inc(MP.CurrentPage);
    MPPageDown := True;
  end;
end;

function MPPageUp(var MP: TMemoPage): Boolean;
begin
  MPPageUp := False;
  if MP.CurrentPage > 0 then
  begin
    Dec(MP.CurrentPage);
    MPPageUp := True;
  end;
end;

function MPGotoPage(var MP: TMemoPage; PageNum: Word): Boolean;
begin
  MPGotoPage := False;
  if PageNum < MP.TotalPages then
  begin
    MP.CurrentPage := PageNum;
    MPGotoPage := True;
  end;
end;

function MPGetCurrentPage(var MP: TMemoPage): Word;
begin
  MPGetCurrentPage := MP.CurrentPage;
end;

function MPGetTotalPages(var MP: TMemoPage): Word;
begin
  MPGetTotalPages := MP.TotalPages;
end;

function MPGetTotalLines(var MP: TMemoPage): Word;
begin
  MPGetTotalLines := MP.TotalLines;
end;

end.
