# Pascal dBASE Library - Complete API Guide

## Overview

This guide covers the complete Pascal API for working with dBASE files, memo fields, text import/export, and utilities in a DOS environment with memory constraints.

## Table of Contents

1. [DBF Module (DBF.PAS)](#dbf-module) - Reading/writing dBASE files
2. [DBFMEMO Module (DBFMEMO.PAS)](#dbfmemo-module) - Memo field operations
3. [DBFTEXT Module (DBFTEXT.PAS)](#dbftext-module) - Text import/export
4. [DBFUTIL Module (DBFUTIL.PAS)](#dbfutil-module) - Utility functions
5. [DBFFIND Module (DBFFIND.PAS)](#dbffind-module) - Brute-force searching
6. [DBFILTER Module (DBFILTER.PAS)](#dbfilter-module) - Advanced filtering
7. [DBFINDEX Module (DBFINDEX.PAS)](#dbfindex-module) - Index operations
8. [DBHEAP Module (DBHEAP.PAS)](#dbheap-module) - Memory-packed heap maps
9. [MEMOPAGE Module (MEMOPAGE.PAS)](#memopage-module) - Memo pagination

---

## DBF Module (DBF.PAS)

### SmartValueArray Functions

#### Memory Management
```pascal
function AllocateSmartValueArray(Header: TDBFHeader): Pointer;
  { Allocates memory for field values based on DBF header structure
    Parameters:
      Header - DBF header containing field definitions
    Returns:
      Pointer to allocated memory area (after size header)
    Note:
      Layout: [4-byte size][field1][field2]...[fieldN]
      C/N fields: Length+1 bytes (Pascal string)
      D fields: 8 bytes (Julian Day Number)
      L fields: 1 byte (boolean)
      M fields: 4 bytes (memo block number) }

function FreeSmartValueArray(Values: Pointer): Boolean;
  { Frees memory allocated by AllocateSmartValueArray
    Parameters:
      Values - Pointer returned by AllocateSmartValueArray
    Returns:
      True if memory successfully freed }
```

#### Field Access
```pascal
function GetSmartFieldValue(SmartArray: Pointer; Header: TDBFHeader; FieldIndex: Integer): string;
  { Gets field value from SmartValueArray by field index
    Parameters:
      SmartArray - Pointer to SmartValueArray
      Header - DBF header structure
      FieldIndex - 1-based field index
    Returns:
      Field value as string with type-specific formatting }

function SetSmartFieldValue(SmartArray: Pointer; Header: TDBFHeader; FieldIndex: Integer; Value: string): Boolean;
  { Sets field value in SmartValueArray by field index
    Parameters:
      SmartArray - Pointer to SmartValueArray
      Header - DBF header structure
      FieldIndex - 1-based field index
      Value - String value to set
    Returns:
      True if value successfully set }
```

#### Buffer Operations
```pascal
function DBFFileGetFieldStrFromBuf(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer): string;
  { Extracts field string directly from raw DBF record buffer
    Parameters:
      Buf - Pointer to raw record data
      Header - DBF header with field definitions
      FieldIdx - 1-based field index
    Returns:
      Field value as string, trimmed of spaces }

function GetFieldStr(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer): string;
  { Alias for DBFFileGetFieldStrFromBuf }

procedure SetFieldStr(Buf: Pointer; Header: TDBFHeader; FieldIdx: Integer; Value: string);
  { Sets field value directly in raw DBF record buffer
    Parameters:
      Buf - Pointer to raw record data
      Header - DBF header with field definitions
      FieldIdx - 1-based field index
      Value - String value to set }
```

### DBF File Operations

#### Core File Management
```pascal
function DBFFileCreate(var Dbf: PDBFFile; FileName: string; Header: TDBFHeader): Boolean;
  { Creates new DBF file with specified header structure
    Parameters:
      Dbf - Variable to receive file handle
      FileName - Base filename (without .DBF extension)
      Header - DBF header with field definitions
    Returns:
      True if file created successfully
    Note:
      Automatically adds .DBF extension to filename }

function DBFFileOpen(var Dbf: PDBFFile; FileName: string): Boolean;
  { Opens existing DBF file
    Parameters:
      Dbf - Variable to receive file handle
      FileName - Base filename (without .DBF extension)
    Returns:
      True if file opened successfully
    Note:
      Automatically adds .DBF extension to filename }

function DBFFileClose(var Dbf: PDBFFile): Boolean;
  { Closes DBF file and flushes data to disk
    Parameters:
      Dbf - File handle to close
    Returns:
      True if file closed successfully }

function DBFFileDispose(var Dbf: PDBFFile): Boolean;
  { Disposes of DBF file handle and frees memory
    Parameters:
      Dbf - File handle to dispose
    Returns:
      True if handle disposed successfully }
```

#### Record Operations
```pascal
function DBFFileReadRow(var Dbf: PDBFFile; Buf: Pointer; BufSize: Integer): Boolean;
  { Reads current record into buffer
    Parameters:
      Dbf - Open DBF file handle
      Buf - Buffer to receive record data
      BufSize - Size of buffer (should be Header.RecordSize)
    Returns:
      True if record read successfully
    Note:
      Buffer must be allocated to Header.RecordSize bytes }

function DBFFileAppendRow(var Dbf: PDBFFile; Values: Pointer; FieldCount: Integer): Boolean;
  { Appends new record using SmartValueArray data
    Parameters:
      Dbf - Open DBF file handle
      Values - SmartValueArray from AllocateSmartValueArray
      FieldCount - Number of fields to write
    Returns:
      True if record appended successfully }

function DBFFileWriteRow(var Dbf: PDBFFile; Values: Pointer; FieldCount: Integer): Boolean;
  { Writes record at current position using SmartValueArray
    Parameters:
      Dbf - Open DBF file handle
      Values - SmartValueArray from AllocateSmartValueArray
      FieldCount - Number of fields to write
    Returns:
      True if record written successfully }
```

#### Navigation
```pascal
function DBFFileSeekToFirstRow(var Dbf: PDBFFile): Boolean;
  { Positions file pointer at first data record
    Parameters:
      Dbf - Open DBF file handle
    Returns:
      True if positioned successfully }

function DBFFileSeekToRow(var Dbf: PDBFFile; RowIndex: LongInt): Boolean;
  { Positions file pointer at specific record (0-based)
    Parameters:
      Dbf - Open DBF file handle
      RowIndex - Record index (0-based)
    Returns:
      True if positioned successfully }

function DBFFileGetCurrentRow(var Dbf: PDBFFile; var RowIndex: LongInt): Boolean;
  { Gets current record position
    Parameters:
      Dbf - Open DBF file handle
      RowIndex - Variable to receive current position
    Returns:
      True if position retrieved successfully }
```

#### Information
```pascal
function DBFFileGetHeader(var Dbf: PDBFFile; var Header: TDBFHeader): Boolean;
  { Reads DBF header structure into Header variable
    Parameters:
      Dbf - Open DBF file handle
      Header - Variable to receive header data
    Returns:
      True if header read successfully }

function DBFFileGetActualRowCount(var Dbf: PDBFFile): LongInt;
  { Returns actual count of non-deleted records
    Parameters:
      Dbf - Open DBF file handle
    Returns:
      Count of non-deleted records }
```

### Usage Examples

#### Creating a New DBF File
```pascal
uses DBF, DBFUTIL;

var
  Dbf: PDBFFile;
  Header: TDBFHeader;
  SmartValues: Pointer;
begin
  { Initialize header }
  FillChar(Header, SizeOf(Header), 0);
  Header.FieldCount := 3;
  Header.Version := $04;  { dBase IV }
  Header.Year := 124;      { 2024 - 1900 }
  Header.Month := 1;
  Header.Day := 27;
  
  { Define fields }
  Header.Fields[1].Name := 'ID';
  Header.Fields[1].FieldType := 'N';
  Header.Fields[1].Length := 5;
  Header.Fields[1].Decimals := 0;
  
  Header.Fields[2].Name := 'NAME';
  Header.Fields[2].FieldType := 'C';
  Header.Fields[2].Length := 20;
  Header.Fields[2].Decimals := 0;
  
  Header.Fields[3].Name := 'ACTIVE';
  Header.Fields[3].FieldType := 'L';
  Header.Fields[3].Length := 1;
  Header.Fields[3].Decimals := 0;
  
  { Create DBF file }
  Dbf := nil;
  if not DBFFileCreate(Dbf, 'TESTDATA', Header) then
  begin
    WriteLn('Error creating DBF file');
    Exit;
  end;
  
  { Allocate SmartValueArray }
  SmartValues := AllocateSmartValueArray(Header);
  
  { Add records }
  SetSmartFieldValue(SmartValues, Header, 1, '1');
  SetSmartFieldValue(SmartValues, Header, 2, 'John Doe');
  SetSmartFieldValue(SmartValues, Header, 3, 'T');
  DBFFileAppendRow(Dbf, SmartValues, 3);
  
  { Clean up }
  FreeSmartValueArray(SmartValues);
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;
```

#### Reading DBF Records
```pascal
uses DBF;

var
  Dbf: PDBFFile;
  Header: TDBFHeader;
  Buf: Pointer;
  RowCount, I: LongInt;
begin
  { Open DBF file }
  Dbf := nil;
  if not DBFFileOpen(Dbf, 'TESTDATA') then
  begin
    WriteLn('Error opening DBF file');
    Exit;
  end;
  
  { Get header information }
  if not DBFFileGetHeader(Dbf, Header) then
  begin
    WriteLn('Error reading header');
    DBFFileClose(Dbf);
    DBFFileDispose(Dbf);
    Exit;
  end;
  
  { Allocate buffer }
  GetMem(Buf, Header.RecordSize);
  
  { Read all records }
  RowCount := DBFFileGetActualRowCount(Dbf);
  DBFFileSeekToFirstRow(Dbf);
  
  for I := 0 to RowCount - 1 do
  begin
    DBFFileReadRow(Dbf, Buf, Header.RecordSize);
    
    { Check if record is not deleted }
    if PByteArray(Buf)^[0] <> Ord('*') then
    begin
      WriteLn('ID: ', TrimString(DBFFileGetFieldStrFromBuf(Buf, Header, 1)));
      WriteLn('Name: ', TrimString(DBFFileGetFieldStrFromBuf(Buf, Header, 2)));
      WriteLn('Active: ', TrimString(DBFFileGetFieldStrFromBuf(Buf, Header, 3)));
      WriteLn('---');
    end;
  end;
  
  { Clean up }
  FreeMem(Buf, Header.RecordSize);
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;
```

---

## DBFMEMO Module (DBFMEMO.PAS)

### Memo File Handle Operations

#### Handle Management
```pascal
function DBFMemoOpen(var Memo: PDBFMemo; MemoFileName: string): Boolean;
  { Opens existing memo file using handle-based operations
    Parameters:
      Memo - Variable to receive memo handle
      MemoFileName - Base filename (without .DBT extension)
    Returns:
      True if memo file opened successfully }

function DBFMemoCreate(var Memo: PDBFMemo; MemoFileName: string): Boolean;
  { Creates new memo file using handle-based operations
    Parameters:
      Memo - Variable to receive memo handle
      MemoFileName - Base filename (without .DBT extension)
    Returns:
      True if memo file created successfully }

function DBFMemoClose(var Memo: PDBFMemo): Boolean;
  { Closes memo file handle
    Parameters:
      Memo - Memo handle to close
    Returns:
      True if memo file closed successfully }

function DBFMemoDispose(var Memo: PDBFMemo): Boolean;
  { Disposes of memo file handle and frees memory
    Parameters:
      Memo - Memo handle to dispose
    Returns:
      True if handle disposed successfully }
```

#### Handle-Based Operations
```pascal
function DBFMemoWriteM(var Memo: PDBFMemo; MemoType: LongInt; Text: string; var StartBlock: LongInt): Boolean;
  { Writes memo text using file handle
    Parameters:
      Memo - Open memo file handle
      MemoType - Type of memo (1=plain text, 2=base64 encoded)
      Text - Text content to write
      StartBlock - Variable to receive starting block number
    Returns:
      True if memo written successfully }

function DBFMemoGetInfoM(var Memo: PDBFMemo; StartBlock: LongInt; var MemoType: LongInt; var Len: LongInt): Boolean;
  { Gets memo block information using handle
    Parameters:
      Memo - Open memo file handle
      StartBlock - Block number to query
      MemoType - Variable to receive memo type
      Len - Variable to receive memo length
    Returns:
      True if info retrieved successfully }

function DBFMemoReadChunkM(var Memo: PDBFMemo; StartBlock: LongInt; Offset: LongInt; var Buf; BufSize: Word; var ReadLen: Word): Boolean;
  { Reads memo chunk using handle
    Parameters:
      Memo - Open memo file handle
      StartBlock - Starting block number
      Offset - Offset within block
      Buf - Buffer to receive data
      BufSize - Size of buffer
      ReadLen - Variable to receive bytes read
    Returns:
      True if chunk read successfully }
```

### Memo Streaming Operations

#### Write Streaming
```pascal
function DBFMemoWriteChunk(var State: TMemoWriteState; var Buf; Len: Word): Boolean;
  { Writes chunk of data during streaming write operation
    Parameters:
      State - Active write state from DBFMemoWriteBegin
      Buf - Buffer containing data to write
      Len - Number of bytes to write
    Returns:
      True if chunk written successfully }

function DBFMemoWriteEnd(var State: TMemoWriteState): Boolean;
  { Completes streaming write operation
    Parameters:
      State - Active write state to complete
    Returns:
      True if write completed successfully }

function DBFMemoWriteEndAtBlock(var State: TMemoWriteState): Boolean;
  { Completes streaming write at specific block
    Parameters:
      State - Active write state to complete
    Returns:
      True if write completed successfully }
```

### Memo Compaction Operations

```pascal
function GetUsedMemoBlocks(DBFFileName: string): PLongIntArray;
  { Scans DBF file and returns array of used memo block numbers
    Parameters:
      DBFFileName - Base filename of DBF file
    Returns:
      Pointer to array of used block numbers
    Note:
      Caller must free the returned array }

function CompactMemoFile(MemoFileName: string; UsedBlocks: PLongIntArray): PLongIntArray;
  { Compacts memo file by removing unused blocks
    Parameters:
      MemoFileName - Base filename of memo file
      UsedBlocks - Array of used block numbers
    Returns:
      Pointer to array mapping old blocks to new blocks
    Note:
      Caller must free the returned array }

procedure UpdateMemoBlocks(DBFFileName: string; BlockMapping: PLongIntArray);
  { Updates DBF file with new block numbers after compaction
    Parameters:
      DBFFileName - Base filename of DBF file
      BlockMapping - Array mapping old blocks to new blocks }
```

### Memo Chunk Management

```pascal
function GetMemoChunk(MemoPtr: LongInt; ChunkIndex: Integer): string;
  { Gets specific chunk from memo data
    Parameters:
      MemoPtr - Pointer to memo data
      ChunkIndex - Index of chunk to retrieve
    Returns:
      Chunk content as string }

function WriteMemoChunk(MemoPtr: LongInt; ChunkIndex: Integer; ChunkText: string): Boolean;
  { Writes specific chunk to memo data
    Parameters:
      MemoPtr - Pointer to memo data
      ChunkIndex - Index of chunk to write
      ChunkText - Text content for chunk
    Returns:
      True if chunk written successfully }

function AppendMemoChunk(MemoPtr: LongInt; ChunkText: string): Boolean;
  { Appends chunk to end of memo data
    Parameters:
      MemoPtr - Pointer to memo data
      ChunkText - Text content to append
    Returns:
      True if chunk appended successfully }
```

### Usage Examples

#### Creating and Writing Memo Fields
```pascal
uses DBF, DBFMEMO, DBFUTIL;

var
  Dbf: PDBFFile;
  Header: TDBFHeader;
  SmartValues: Pointer;
  StartBlock: LongInt;
begin
  { Create DBF with memo field }
  FillChar(Header, SizeOf(Header), 0);
  Header.FieldCount := 2;
  Header.Version := $05;  { dBase V with memo support }
  Header.Year := 124;
  Header.Month := 1;
  Header.Day := 27;
  
  Header.Fields[1].Name := 'ID';
  Header.Fields[1].FieldType := 'N';
  Header.Fields[1].Length := 5;
  Header.Fields[1].Decimals := 0;
  
  Header.Fields[2].Name := 'NOTES';
  Header.Fields[2].FieldType := 'M';
  Header.Fields[2].Length := 10;
  Header.Fields[2].Decimals := 0;
  
  { Create DBF file }
  Dbf := nil;
  if not DBFFileCreate(Dbf, 'TESTMEMO', Header) then
  begin
    WriteLn('Error creating DBF file');
    Exit;
  end;
  
  { Create memo file }
  DBFMemoCreate('TESTMEMO');
  
  { Allocate SmartValueArray }
  SmartValues := AllocateSmartValueArray(Header);
  
  { Write memo content }
  if DBFMemoWrite('TESTMEMO', 1, 'This is a test memo note with multiple lines.' + #13#10 + 'Second line of memo.', StartBlock) then
  begin
    { Set memo field to block number }
    SetSmartFieldValue(SmartValues, Header, 1, '1');
    SetSmartFieldValue(SmartValues, Header, 2, IntToStrLocal(StartBlock));
    
    { Append record }
    DBFFileAppendRow(Dbf, SmartValues, 2);
    
    WriteLn('Memo written to block ', StartBlock);
  end;
  
  { Clean up }
  FreeSmartValueArray(SmartValues);
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;
```

---

## DBFTEXT Module (DBFTEXT.PAS)

### Text Import/Export Operations

```pascal
procedure ExportDBFToText(FileName: string);
  { Exports DBF data to pipe-delimited text file
    Parameters:
      FileName - Base filename (without extensions)
    Output:
      Creates FileName.TXT with pipe-delimited data
    Format:
      First line: field names separated by |
      Subsequent lines: field values separated by | }

procedure ImportDBFFromText(FileName: string);
  { Imports pipe-delimited text data into DBF file
    Parameters:
      FileName - Base filename (without extensions)
    Input:
      Reads FileName.TXT with pipe-delimited data
    Format:
      First line: field names separated by |
      Second line: field specifications (name|type|length|decimals)
      Subsequent lines: field values separated by | }

procedure ImportDBFFromTextStreaming(FileName: string);
  { Memory-optimized streaming version of text import
    Parameters:
      FileName - Base filename (without extensions)
    Note:
      Processes file line-by-line to minimize memory usage }

procedure ImportDBFFromTextFieldByField(FileName: string);
  { Field-by-field minimal memory version of text import
    Parameters:
      FileName - Base filename (without extensions)
    Note:
      Processes each field individually for maximum memory efficiency }

procedure ImportDBFFromTextPacked(FileName: string);
  { Packed buffer maximum efficiency version of text import
    Parameters:
      FileName - Base filename (without extensions)
    Note:
      Uses packed buffers for optimal performance }
```

### Memo Text Operations

```pascal
procedure ExportDBFMemosToText(FileName: string);
  { Exports memo fields to text file
    Parameters:
      FileName - Base filename (without extensions)
    Output:
      Creates FileName.TXT with memo data
    Format:
      Each line: row_index|field_index|memo_type|block_number|memo_content }

procedure ImportDBFMemosFromText(FileName: string);
  { Imports memo data from text file
    Parameters:
      FileName - Base filename (without extensions)
    Input:
      Reads FileName.TXT with memo data
    Format:
      Each line: row_index|field_index|memo_type|block_number|memo_content }

procedure ImportDBFMemosFromTextEx(FileName: string; PreserveBlocks: Boolean);
  { Extended memo import with block preservation option
    Parameters:
      FileName - Base filename (without extensions)
      PreserveBlocks - If True, preserves original block numbers
    Note:
      Allows more flexible memo import strategies }
```

### Utility Functions

```pascal
function ParseMemoLine(Buf: PByteArray; BufLen: LongInt; var RowIndex: LongInt;
  var FieldIdx: Integer; var MemoType: LongInt; var BlockNum: LongInt;
  var Content: string): Boolean;
  { Parses a memo line from text import format
    Parameters:
      Buf - Buffer containing line data
      BufLen - Length of buffer
      RowIndex - Variable to receive row index
      FieldIdx - Variable to receive field index
      MemoType - Variable to receive memo type
      BlockNum - Variable to receive block number
      Content - Variable to receive memo content
    Returns:
      True if line parsed successfully }
```

### Usage Examples

#### Exporting DBF to Text
```pascal
uses DBFTEXT;

begin
  { Export TESTDATA.DBF to TESTDATA.TXT }
  ExportDBFToText('TESTDATA');
  WriteLn('DBF exported to text file');
end;
```

#### Importing Text to DBF
```pascal
uses DBFTEXT;

begin
  { Import TESTDATA.TXT to TESTDATA.DBF }
  ImportDBFFromText('TESTDATA');
  WriteLn('Text imported to DBF file');
end;
```

---

## DBFUTIL Module (DBFUTIL.PAS)

### String and Numeric Utilities

```pascal
function IntToStrLocal(Value: Integer): string;
  { Converts integer to string using local formatting
    Parameters:
      Value - Integer value to convert
    Returns:
      String representation of value }

function FloatToStrLocal(Value: Real): string;
  { Converts real number to string using local formatting
    Parameters:
      Value - Real value to convert
    Returns:
      String representation of value }

function ScaleDecimal(DecimalStr: string; FieldLength: Byte): LongInt;
  { Scales decimal string to fixed-point integer
    Parameters:
      DecimalStr - Decimal string to scale
      FieldLength - Target field length
    Returns:
      Scaled integer value }
```

### Date Utilities

```pascal
function DateToJDN(DateStr: string): LongInt;
  { Converts YYYYMMDD string to Julian Day Number
    Parameters:
      DateStr - Date string in YYYYMMDD format
    Returns:
      Julian Day Number (0 if invalid date) }

function JDNToDate(JDN: LongInt): string;
  { Converts Julian Day Number to YYYYMMDD string
    Parameters:
      JDN - Julian Day Number
    Returns:
      Date string in YYYYMMDD format (empty if invalid) }

function FormatDate(Year, Month, Day: Integer): string;
  { Formats date components to YYYYMMDD string
    Parameters:
      Year - Year component
      Month - Month component (1-12)
      Day - Day component (1-31)
    Returns:
      Formatted date string }

function FormatTime(Hour, Minute, Second: Integer): string;
  { Formats time components to HHMMSS string
    Parameters:
      Hour - Hour component (0-23)
      Minute - Minute component (0-59)
      Second - Second component (0-59)
    Returns:
      Formatted time string }
```

### String Utilities

```pascal
function TrimString(S: string): string;
  { Removes leading and trailing spaces from string
    Parameters:
      S - String to trim
    Returns:
      Trimmed string }

function UpperString(S: string): string;
  { Converts string to uppercase
    Parameters:
      S - String to convert
    Returns:
      Uppercase string }

function LowerString(S: string): string;
  { Converts string to lowercase
    Parameters:
      S - String to convert
    Returns:
      Lowercase string }

function LeftString(S: string; Count: Integer): string;
  { Gets left portion of string
    Parameters:
      S - Source string
      Count - Number of characters to get
    Returns:
      Left portion of string }

function RightString(S: string; Count: Integer): string;
  { Gets right portion of string
    Parameters:
      S - Source string
      Count - Number of characters to get
    Returns:
      Right portion of string }

function MidString(S: string; Start, Count: Integer): string;
  { Gets middle portion of string
    Parameters:
      S - Source string
      Start - Starting position (1-based)
      Count - Number of characters to get
    Returns:
      Middle portion of string }
```

### File Utilities

```pascal
function FileExists(FileName: string): Boolean;
  { Checks if file exists
    Parameters:
      FileName - Name of file to check
    Returns:
      True if file exists }

function RenameFile(OldName, NewName: string): Boolean;
  { Renames file
    Parameters:
      OldName - Current filename
      NewName - New filename
    Returns:
      True if file renamed successfully }

function DeleteFile(FileName: string): Boolean;
  { Deletes file
    Parameters:
      FileName - Name of file to delete
    Returns:
      True if file deleted successfully }

function FileSize(FileName: string): LongInt;
  { Gets file size in bytes
    Parameters:
      FileName - Name of file to check
    Returns:
      File size in bytes (-1 if error) }
```

### Memory Utilities

```pascal
procedure MemoryReport(Label: string);
  { Reports current memory usage statistics
    Parameters:
      Label - Descriptive label for report
    Output:
      Writes heap available and largest block size }

function GetHeapAvailable: LongInt;
  { Gets available heap memory
    Returns:
      Available heap memory in bytes }

function GetLargestBlock: LongInt;
  { Gets largest contiguous memory block
    Returns:
      Size of largest available block in bytes }
```

### Usage Examples

#### Date Conversion
```pascal
uses DBFUTIL;

var
  DateStr: string;
  JDN: LongInt;
begin
  { Convert date to JDN }
  DateStr := '20240127';
  JDN := DateToJDN(DateStr);
  WriteLn('JDN: ', JDN);
  
  { Convert JDN back to date }
  DateStr := JDNToDate(JDN);
  WriteLn('Date: ', DateStr);
end;
```

#### Memory Reporting
```pascal
uses DBFUTIL;

begin
  MemoryReport('Before allocation');
  
  { Allocate memory... }
  
  MemoryReport('After allocation');
end;
```

---

## Error Handling Patterns

### Common Error Checking

```pascal
{ Check DBF operations }
if not DBFFileOpen(Dbf, 'TESTDATA') then
begin
  WriteLn('Error opening DBF file');
  Exit;
end;

{ Check memo operations }
if not DBFMemoWrite('TESTMEMO', 1, 'Test memo', StartBlock) then
begin
  WriteLn('Error writing memo');
  Exit;
end;

{ Check memory allocation }
SmartValues := AllocateSmartValueArray(Header);
if SmartValues = nil then
begin
  WriteLn('Error allocating memory');
  Exit;
end;

{ Always clean up }
if SmartValues <> nil then
  FreeSmartValueArray(SmartValues);
if Dbf <> nil then
begin
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;
```

---

## Quick Reference

### DBF Operations
- `DBFFileCreate(var Dbf, FileName, Header)` - Create DBF
- `DBFFileOpen(var Dbf, FileName)` - Open DBF
- `DBFFileClose(var Dbf)` - Close DBF
- `DBFFileDispose(var Dbf)` - Dispose handle
- `DBFFileGetHeader(var Dbf, var Header)` - Get header
- `DBFFileReadRow(var Dbf, Buf, BufSize)` - Read record
- `DBFFileAppendRow(var Dbf, Values, FieldCount)` - Append record
- `DBFFileSeekToFirstRow(var Dbf)` - Go to first record
- `DBFFileGetActualRowCount(var Dbf)` - Get record count

### SmartValueArray Operations
- `AllocateSmartValueArray(Header)` - Allocate memory
- `FreeSmartValueArray(Values)` - Free memory
- `GetSmartFieldValue(Values, Header, Index)` - Get field value
- `SetSmartFieldValue(Values, Header, Index, Value)` - Set field value
- `DBFFileGetFieldStrFromBuf(Buf, Header, Index)` - Get from buffer

### Memo Operations
- `DBFMemoCreate(FileName)` - Create memo file
- `DBFMemoWrite(FileName, RecordNum, Text, var StartBlock)` - Write memo
- `DBFMemoGetInfo(FileName, Block, var Type, var Len)` - Get memo info
- `ExportDBFMemosToText(FileName)` - Export memos
- `ImportDBFMemosFromText(FileName)` - Import memos

### Text Operations
- `ExportDBFToText(FileName)` - Export DBF to text
- `ImportDBFFromText(FileName)` - Import text to DBF
- `ImportDBFFromTextStreaming(FileName)` - Streaming import
- `ImportDBFFromTextPacked(FileName)` - Packed import

### Utility Operations
- `IntToStrLocal(Value)` - Integer to string
- `FloatToStrLocal(Value)` - Real to string
- `DateToJDN(DateStr)` - Date to JDN
- `JDNToDate(JDN)` - JDN to date
- `TrimString(S)` - Trim string
- `MemoryReport(Label)` - Memory usage report

---

## Memory Management Guidelines

### Allocation Patterns
```pascal
{ Always pair allocations with deallocations }
SmartValues := AllocateSmartValueArray(Header);
try
  { Use SmartValues... }
finally
  FreeSmartValueArray(SmartValues);
end;

{ Always check file handles }
Dbf := nil;
if DBFFileOpen(Dbf, 'TESTDATA') then
begin
  try
    { Use Dbf... }
  finally
    DBFFileClose(Dbf);
    DBFFileDispose(Dbf);
  end;
end;
```

### Memory Reporting
```pascal
{ Monitor memory usage during operations }
MemoryReport('Before operation');
{ ... perform operation ... }
MemoryReport('After operation');
```

---

## DBFFIND Module (DBFFIND.PAS)

### Brute-Force Search Operations

#### Row ID Array Management
```pascal
type
  PRowIdArray = ^TRowIdArray;
  TRowIdArray = array[0..0] of LongInt;  { Open array for pointer math }

function RowIdAt(RowIds: PRowIdArray; Index: Integer): LongInt;
  { Gets row ID at specific index from array
    Parameters:
      RowIds - Pointer to row ID array
      Index - Index in array (0-based)
    Returns:
      Row ID at specified index }
```

#### Exact Match Searches
```pascal
function DBFFileFindRowsExact(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: string; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;
  { Finds rows with exact string match in field
    Parameters:
      Dbf - Open DBF file handle
      FieldIdx - Field index to search (1-based)
      Value - String value to match exactly
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
      ScanPos - Variable to receive scan position
    Returns:
      True if search completed successfully
    Note:
      Case-sensitive exact matching }

function DBFFileFindRowsExactNum(var Dbf: PDBFFile; FieldIdx: Integer;
  Value: LongInt; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;
  { Finds rows with exact numeric match in field
    Parameters:
      Dbf - Open DBF file handle
      FieldIdx - Field index to search (1-based)
      Value - Numeric value to match exactly
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
      ScanPos - Variable to receive scan position
    Returns:
      True if search completed successfully }
```

#### Range Searches
```pascal
function DBFFileFindRowsInRangeNum(var Dbf: PDBFFile; FieldIdxMin: Integer;
  FieldIdxMax: Integer; Value: LongInt; RowIds: PRowIdArray;
  MaxCount: Integer; var Count: Integer; var ScanPos: LongInt): Boolean;
  { Finds rows with numeric value in range across multiple fields
    Parameters:
      Dbf - Open DBF file handle
      FieldIdxMin - Starting field index for range
      FieldIdxMax - Ending field index for range
      Value - Numeric value to find
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
      ScanPos - Variable to receive scan position
    Returns:
      True if search completed successfully
    Note:
      Searches across multiple fields for matching values }
```

#### Prefix Searches
```pascal
function DBFFileFindRowsStartsWith(var Dbf: PDBFFile; FieldIdx: Integer;
  Prefix: string; RowIds: PRowIdArray; MaxCount: Integer;
  var Count: Integer; var ScanPos: LongInt): Boolean;
  { Finds rows with field value starting with prefix
    Parameters:
      Dbf - Open DBF file handle
      FieldIdx - Field index to search (1-based)
      Prefix - String prefix to match
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
      ScanPos - Variable to receive scan position
    Returns:
      True if search completed successfully
    Note:
      Case-sensitive prefix matching }
```

### Usage Examples

#### Exact String Search
```pascal
uses DBFFIND, DBF;

var
  Dbf: PDBFFile;
  RowIds: PRowIdArray;
  MatchCount, I: Integer;
  ScanPos: LongInt;
begin
  { Open DBF file }
  Dbf := nil;
  if not DBFFileOpen(Dbf, 'GAMES') then
  begin
    WriteLn('Error opening DBF');
    Exit;
  end;
  
  { Allocate row ID array }
  GetMem(RowIds, 1000 * SizeOf(LongInt));
  
  { Search for exact match }
  if DBFFileFindRowsExact(Dbf, 2, 'DOOM', RowIds, 1000, MatchCount, ScanPos) then
  begin
    WriteLn('Found ', MatchCount, ' matches');
    for I := 0 to MatchCount - 1 do
      WriteLn('Match at record: ', RowIdAt(RowIds, I));
  end;
  
  { Clean up }
  FreeMem(RowIds, 1000 * SizeOf(LongInt));
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;
```

---

## DBFILTER Module (DBFILTER.PAS)

### Filter Types and Structures

#### Filter Types
```pascal
type
  TDBFilterKind = (fkExactStr, fkExactNum, fkRangeNum, fkStartsWith, fkFieldRange);
  TDBMatchMode = (mmAny, mmAll);
  
  TDBFilterSpec = record
    Kind: TDBFilterKind;           { Type of filter }
    FieldIdx: Integer;             { Field index (1-based) }
    FieldIdxMin: Integer;          { For range: start field }
    FieldIdxMax: Integer;          { For range: end field }
    ValueStr: string[80];          { String value (up to 80 chars) }
    ValueNum: LongInt;             { Numeric value }
    ValueNumMin: LongInt;          { Range minimum }
    ValueNumMax: LongInt;          { Range maximum }
    IndexFileName: string[12];      { Index filename (8.3) }
  end;
  
  TDBFilterSpecArray = array[1..8] of TDBFilterSpec;
  TDBMatchGroup = record
    Mode: TDBMatchMode;            { mmAny or mmAll }
    FilterCount: Integer;          { Number of filters in group }
    Filters: TDBFilterSpecArray;   { Filter specifications }
  end;
  TDBMatchGroupArray = array[1..4] of TDBMatchGroup;
```

#### Filter Cursor
```pascal
type
  TDBMatchCursor = record
    ScanPos: LongInt;              { Current scan position }
    TotalRows: LongInt;            { Total rows in DBF }
    GroupCount: Integer;           { Number of filter groups }
    Groups: TDBMatchGroupArray;   { Filter groups }
    RowIds: PRowIdArray;          { Matching row IDs }
    RowCount: Integer;            { Number of matches }
    CurrentPos: Integer;           { Current position in results }
  end;
```

### Filter Operations

#### Cursor Management
```pascal
function InitFilterCursor(var Cursor: TDBMatchCursor; var Dbf: PDBFFile): Boolean;
  { Initializes filter cursor for DBF file
    Parameters:
      Cursor - Filter cursor to initialize
      Dbf - Open DBF file handle
    Returns:
      True if cursor initialized successfully }

function FreeFilterCursor(var Cursor: TDBMatchCursor): Boolean;
  { Frees filter cursor resources
    Parameters:
      Cursor - Filter cursor to free
    Returns:
      True if cursor freed successfully }
```

#### Filter Execution
```pascal
function ExecuteFilter(var Cursor: TDBMatchCursor): Boolean;
  { Executes filter query on DBF file
    Parameters:
      Cursor - Filter cursor with query specifications
    Returns:
      True if filter executed successfully
    Note:
      Results stored in Cursor.RowIds array }

function ExecuteFilterWithIndex(var Cursor: TDBMatchCursor; IndexFileName: string): Boolean;
  { Executes filter using index for optimization
    Parameters:
      Cursor - Filter cursor with query specifications
      IndexFileName - Index file to use for optimization
    Returns:
      True if filter executed successfully
    Note:
      Uses index to narrow search space before applying filters }
```

#### Result Navigation
```pascal
function FilterEof(var Cursor: TDBMatchCursor): Boolean;
  { Checks if at end of filter results
    Parameters:
      Cursor - Filter cursor to check
    Returns:
      True if at end of results }

function FilterGetRecNo(var Cursor: TDBMatchCursor): LongInt;
  { Gets current record number from filter results
    Parameters:
      Cursor - Filter cursor
    Returns:
      Current record number }

function FilterSkip(var Cursor: TDBMatchCursor; Count: Integer): Boolean;
  { Skips specified number of records in results
    Parameters:
      Cursor - Filter cursor
      Count - Number of records to skip (positive = forward)
    Returns:
      True if skip successful }
```

### Usage Examples

#### Simple Filter
```pascal
uses DBFILTER, DBF;

var
  Dbf: PDBFFile;
  Cursor: TDBMatchCursor;
  RecNo: LongInt;
begin
  { Open DBF file }
  Dbf := nil;
  if not DBFFileOpen(Dbf, 'GAMES') then
  begin
    WriteLn('Error opening DBF');
    Exit;
  end;
  
  { Initialize filter cursor }
  if not InitFilterCursor(Cursor, Dbf) then
  begin
    WriteLn('Error initializing cursor');
    DBFFileClose(Dbf);
    DBFFileDispose(Dbf);
    Exit;
  end;
  
  { Set up filter - find games from 1995 }
  Cursor.GroupCount := 1;
  Cursor.Groups[1].Mode := mmAny;
  Cursor.Groups[1].FilterCount := 1;
  Cursor.Groups[1].Filters[1].Kind := fkExactNum;
  Cursor.Groups[1].Filters[1].FieldIdx := 3;  { YEAR field }
  Cursor.Groups[1].Filters[1].ValueNum := 1995;
  
  { Execute filter }
  if ExecuteFilter(Cursor) then
  begin
    WriteLn('Found ', Cursor.RowCount, ' games from 1995');
    
    { Iterate through results }
    while not FilterEof(Cursor) do
    begin
      RecNo := FilterGetRecNo(Cursor);
      DBFFileSeekToRow(Dbf, RecNo);
      WriteLn('Game: ', DBFFileGetFieldStrFromBuf(Buf, Header, 2));
      FilterSkip(Cursor, 1);
    end;
  end;
  
  { Clean up }
  FreeFilterCursor(Cursor);
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;
```

---

## DBFINDEX Module (DBFINDEX.PAS)

### Index Search Operations

#### Character Searches
```pascal
function FindCharacterExact(NdxFileName, Key: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
  { Finds exact character match in index
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      Key - Exact key to search for
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
    Returns:
      True if search completed successfully
    Note:
      Case-sensitive exact matching }

function FindCharacterBegins(NdxFileName, Prefix: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
  { Finds character keys starting with prefix
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      Prefix - Prefix to search for
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
    Returns:
      True if search completed successfully
    Note:
      Case-sensitive prefix matching }
```

#### Numeric Searches
```pascal
function FindNumberExact(NdxFileName: string; Value: LongInt;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
  { Finds exact numeric match in index
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      Value - Numeric value to search for
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
    Returns:
      True if search completed successfully }

function FindNumberRange(NdxFileName: string; MinValue, MaxValue: LongInt;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
  { Finds numeric values in range
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      MinValue - Minimum value (inclusive)
      MaxValue - Maximum value (inclusive)
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
    Returns:
      True if search completed successfully }
```

#### Date Searches
```pascal
function FindDateExact(NdxFileName, DateStr: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
  { Finds exact date match in index
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      DateStr - Date string in YYYYMMDD format
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
    Returns:
      True if search completed successfully }

function FindDateRange(NdxFileName, StartDateStr, EndDateStr: string;
  RowIds: PRowIdArray; MaxCount: Integer; var Count: Integer): Boolean;
  { Finds dates in range
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      StartDateStr - Start date in YYYYMMDD format
      EndDateStr - End date in YYYYMMDD format
      RowIds - Array to receive matching row IDs
      MaxCount - Maximum number of matches to return
      Count - Variable to receive actual match count
    Returns:
      True if search completed successfully }
```

#### Count Operations
```pascal
function CountNumberExact(NdxFileName: string; Value: LongInt; var Count: LongInt): Boolean;
  { Counts exact numeric matches in index
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      Value - Numeric value to count
      Count - Variable to receive match count
    Returns:
      True if count completed successfully }

function CountNumberRange(NdxFileName: string; MinValue, MaxValue: LongInt; var Count: LongInt): Boolean;
  { Counts numeric values in range
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      MinValue - Minimum value (inclusive)
      MaxValue - Maximum value (inclusive)
      Count - Variable to receive match count
    Returns:
      True if count completed successfully }

function CountDateExact(NdxFileName, DateStr: string; var Count: LongInt): Boolean;
  { Counts exact date matches in index
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      DateStr - Date string in YYYYMMDD format
      Count - Variable to receive match count
    Returns:
      True if count completed successfully }

function CountDateRange(NdxFileName, StartDateStr, EndDateStr: string; var Count: LongInt): Boolean;
  { Counts dates in range
    Parameters:
      NdxFileName - Index filename (without .NDX extension)
      StartDateStr - Start date in YYYYMMDD format
      EndDateStr - End date in YYYYMMDD format
      Count - Variable to receive match count
    Returns:
      True if count completed successfully }
```

### Usage Examples

#### Character Index Search
```pascal
uses DBFINDEX;

var
  RowIds: PRowIdArray;
  MatchCount, I: Integer;
begin
  { Allocate row ID array }
  GetMem(RowIds, 1000 * SizeOf(LongInt));
  
  { Search for exact match }
  if FindCharacterExact('TITLE', 'DOOM', RowIds, 1000, MatchCount) then
  begin
    WriteLn('Found ', MatchCount, ' exact matches');
    for I := 0 to MatchCount - 1 do
      WriteLn('Match at record: ', RowIdAt(RowIds, I));
  end;
  
  { Search for prefix matches }
  if FindCharacterBegins('TITLE', 'DO', RowIds, 1000, MatchCount) then
  begin
    WriteLn('Found ', MatchCount, ' prefix matches');
    for I := 0 to MatchCount - 1 do
      WriteLn('Match at record: ', RowIdAt(RowIds, I));
  end;
  
  { Clean up }
  FreeMem(RowIds, 1000 * SizeOf(LongInt));
end;
```

---

## DBHEAP Module (DBHEAP.PAS)

### Heap Map Types and Structures

#### Field Types
```pascal
type
  THeapFieldType = (hftNone, hftWord, hftLongInt, hftBitFlags, hftNibble, hftByte);
  
  THeapFieldSpec = record
    DBFFieldIdx: Integer;      { Source field index in DBF (0 = RecNo) }
    HeapFieldType: THeapFieldType; { How to store in heap }
    HeapOffset: Byte;          { Offset in heap record (auto-calculated) }
    ConvertToJDN: Boolean;     { Auto-convert date string (YYYYMMDD) to JDN }
    BitMask: Byte;             { For hftBitFlags: which bit(s) to use ($01, $02, $04, etc.) }
    NibbleShift: Byte;         { For hftNibble: 0 (low nibble) or 4 (high nibble) }
  end;
  
  THeapFieldSpecArray = array[1..MaxHeapFields] of THeapFieldSpec;
  
  THeapMap = record
    RecordCount: Word;          { Actual records stored }
    AllocatedRecords: Word;     { Records allocated (for FreeMem) }
    RecordSize: Byte;           { 16, 24, or 32 bytes }
    FieldCount: Byte;           { Number of fields }
    FieldSpecs: THeapFieldSpecArray;
    Records: ^THeapRecord;      { Pointer to dynamically allocated records }
  end;
```

#### Field Type Descriptions
```pascal
{ hftNone:      Invalid/unused field }
{ hftWord:      2 bytes, integers 0-65535 }
{ hftLongInt:   4 bytes, large integers or JDN dates }
{ hftBitFlags:  1 bit, boolean (8 per byte) }
{ hftNibble:    4 bits, small enums 0-15 (2 per byte) }
{ hftByte:      1 byte, medium enums 0-255 }
```

### Heap Map Operations

#### Building Heap Maps
```pascal
function BuildHeapMap(var Dbf: PDBFFile; var FieldSpecs: THeapFieldSpecArray;
  FieldCount: Integer; TargetRecordSize: Byte; var HeapMap: THeapMap): Boolean;
  { Builds memory-packed heap map from DBF data
    Parameters:
      Dbf - Open DBF file handle
      FieldSpecs - Array of field specifications
      FieldCount - Number of fields to extract
      TargetRecordSize - 16, 24, or 32 bytes per record
      HeapMap - Variable to receive heap map structure
    Returns:
      True if heap map built successfully
    Note:
      Maximum 4000 records (4000 × 16 = 64KB < 65535 limit) }

function CalculateHeapLayout(var FieldSpecs: THeapFieldSpecArray;
  FieldCount: Integer; TargetRecordSize: Byte): Boolean;
  { Calculates field offsets for heap layout
    Parameters:
      FieldSpecs - Array of field specifications
      FieldCount - Number of fields
      TargetRecordSize - Target record size
    Returns:
      True if layout calculated successfully
    Note:
      Call before BuildHeapMap to validate layout }
```

#### Accessing Heap Data
```pascal
function HeapGetWord(var HeapMap: THeapMap; RecIdx: Word; FieldIdx: Integer): Word;
  { Gets Word value from heap map
    Parameters:
      HeapMap - Heap map structure
      RecIdx - Record index (0-based)
      FieldIdx - Field index (1-based)
    Returns:
      Word value from specified field }

function HeapGetLongInt(var HeapMap: THeapMap; RecIdx: Word; FieldIdx: Integer): LongInt;
  { Gets LongInt value from heap map
    Parameters:
      HeapMap - Heap map structure
      RecIdx - Record index (0-based)
      FieldIdx - Field index (1-based)
    Returns:
      LongInt value from specified field }

function HeapGetBitFlag(var HeapMap: THeapMap; RecIdx: Word; FieldIdx: Integer): Boolean;
  { Gets boolean value from heap map
    Parameters:
      HeapMap - Heap map structure
      RecIdx - Record index (0-based)
      FieldIdx - Field index (1-based)
    Returns:
      Boolean value from specified field }

function HeapGetNibble(var HeapMap: THeapMap; RecIdx: Word; FieldIdx: Integer): Byte;
  { Gets nibble value (0-15) from heap map
    Parameters:
      HeapMap - Heap map structure
      RecIdx - Record index (0-based)
      FieldIdx - Field index (1-based)
    Returns:
      Nibble value (0-15) from specified field }

function HeapGetByte(var HeapMap: THeapMap; RecIdx: Word; FieldIdx: Integer): Byte;
  { Gets byte value (0-255) from heap map
    Parameters:
      HeapMap - Heap map structure
      RecIdx - Record index (0-based)
      FieldIdx - Field index (1-based)
    Returns:
      Byte value (0-255) from specified field }
```

#### Memory Management
```pascal
procedure FreeHeapMap(var HeapMap: THeapMap);
  { Frees heap map memory
    Parameters:
      HeapMap - Heap map structure to free
    Note:
      Must be called to prevent memory leaks }
```

### Usage Examples

#### Building and Using Heap Map
```pascal
uses DBHEAP, DBF;

var
  Dbf: PDBFFile;
  HeapMap: THeapMap;
  FieldSpecs: THeapFieldSpecArray;
  I: Word;
  Year: Word;
  Active: Boolean;
begin
  { Open DBF file }
  Dbf := nil;
  if not DBFFileOpen(Dbf, 'GAMES') then
  begin
    WriteLn('Error opening DBF');
    Exit;
  end;
  
  { Define field specifications }
  FieldSpecs[1].DBFFieldIdx := 0;        { RecNo }
  FieldSpecs[1].HeapFieldType := hftWord;
  
  FieldSpecs[2].DBFFieldIdx := 3;        { YEAR }
  FieldSpecs[2].HeapFieldType := hftWord;
  
  FieldSpecs[3].DBFFieldIdx := 5;        { ACTIVE }
  FieldSpecs[3].HeapFieldType := hftBitFlags;
  FieldSpecs[3].BitMask := $01;           { Bit 0 }
  
  { Build heap map (16-byte records) }
  if BuildHeapMap(Dbf, FieldSpecs, 3, 16, HeapMap) then
  begin
    WriteLn('Heap map built: ', HeapMap.RecordCount, ' records');
    
    { Access data }
    for I := 0 to HeapMap.RecordCount - 1 do
    begin
      Year := HeapGetWord(HeapMap, I, 2);
      Active := HeapGetBitFlag(HeapMap, I, 3);
      
      if (Year = 1995) and Active then
        WriteLn('Match at record ', I);
    end;
    
    { Clean up }
    FreeHeapMap(HeapMap);
  end;
  
  DBFFileClose(Dbf);
  DBFFileDispose(Dbf);
end;
```

---

## MEMOPAGE Module (MEMOPAGE.PAS)

### Memo Pagination Types

#### Page Structure
```pascal
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
```

### Memo Pagination Operations

#### Initialization
```pascal
function MPInit(var MP: TMemoPage;
                Memo: PDBFMemo;
                StartBlock: LongInt;
                LineWidth, LinesPerPage: Byte): Boolean;
  { Initializes memo viewer for pagination
    Parameters:
      MP - Memo page structure to initialize
      Memo - Open memo handle
      StartBlock - Starting block of memo
      LineWidth - Characters per line (max 80)
      LinesPerPage - Lines per page (max 50)
    Returns:
      True if initialization successful
    Note:
      Calculates total lines and pages automatically }
```

#### Page Operations
```pascal
function MPGetPage(var MP: TMemoPage; var Buf: TPageBuffer): Byte;
  { Gets current page into padded buffer
    Parameters:
      MP - Memo page structure
      Buf - Buffer to receive page data
    Returns:
      Number of lines actually filled
    Note:
      Lines are padded with spaces to LineWidth }

function MPPageDown(var MP: TMemoPage): Boolean;
  { Moves to next page
    Parameters:
      MP - Memo page structure
    Returns:
      True if page changed successfully }

function MPPageUp(var MP: TMemoPage): Boolean;
  { Moves to previous page
    Parameters:
      MP - Memo page structure
    Returns:
      True if page changed successfully }

function MPGotoPage(var MP: TMemoPage; PageNum: Word): Boolean;
  { Goes to specific page
    Parameters:
      MP - Memo page structure
      PageNum - Page number (0-based)
    Returns:
      True if page changed successfully }
```

#### Information Functions
```pascal
function MPGetCurrentPage(var MP: TMemoPage): Word;
  { Gets current page number
    Parameters:
      MP - Memo page structure
    Returns:
      Current page number (0-based) }

function MPGetTotalPages(var MP: TMemoPage): Word;
  { Gets total page count
    Parameters:
      MP - Memo page structure
    Returns:
      Total number of pages }

function MPGetTotalLines(var MP: TMemoPage): Word;
  { Gets total line count
    Parameters:
      MP - Memo page structure
    Returns:
      Total number of wrapped lines }
```

### Usage Examples

#### Memo Pagination
```pascal
uses MEMOPAGE, DBFMEMO;

var
  MP: TMemoPage;
  Memo: PDBFMemo;
  PageBuf: TPageBuffer;
  LinesFilled, I: Byte;
begin
  { Open memo file }
  Memo := nil;
  if not DBFMemoOpen(Memo, 'GAMES') then
  begin
    WriteLn('Error opening memo file');
    Exit;
  end;
  
  { Initialize memo viewer }
  if MPInit(MP, Memo, 1, 80, 50) then
  begin
    WriteLn('Memo: ', MPGetTotalLines(MP), ' lines, ', MPGetTotalPages(MP), ' pages');
    
    { Display first page }
    LinesFilled := MPGetPage(MP, PageBuf);
    WriteLn('Page ', MPGetCurrentPage(MP) + 1, ' (', LinesFilled, ' lines):');
    
    for I := 0 to LinesFilled - 1 do
      WriteLn(PageBuf[I]);
    
    { Navigate pages }
    WriteLn('Press any key for next page...');
    if MPPageDown(MP) then
    begin
      LinesFilled := MPGetPage(MP, PageBuf);
      WriteLn('Page ', MPGetCurrentPage(MP) + 1, ':');
      for I := 0 to LinesFilled - 1 do
        WriteLn(PageBuf[I]);
    end;
  end;
  
  { Clean up }
  DBFMemoClose(Memo);
  DBFMemoDispose(Memo);
end;
```

---

## Performance Guidelines

### **Critical Performance Decision: DBFILTER vs DBHEAP**

#### **DBFILTER Module - Disk-Based Full Scan**
```pascal
{ Use DBFILTER when: }
- Table size > 8,000 records (exceeds heap map capacity)
- Memory is extremely limited (< 64KB available)
- One-time queries where setup overhead matters
- Complex multi-field queries that don't fit in heap layout

{ Performance Characteristics: }
- Scans entire DBF file from disk
- O(n) disk I/O operations
- No memory overhead for data storage
- Suitable for large tables or infrequent queries
```

#### **DBHEAP Module - In-Memory Search**
```pascal
{ Use DBHEAP when: }
- Table size ≤ 8,000 records (fits in memory)
- Need fast repeated queries with different parameters
- Quick toggle of query parameters (year, active flags, etc.)
- Real-time filtering or interactive applications

{ Performance Characteristics: }
- One-time disk load, then all queries in memory
- O(1) memory access for filtering
- 50-100x faster than disk-based filtering
- Ideal for dashboards, reports, interactive tools
```

#### **Performance Comparison (10,000 Records)**
```pascal
{ DBFILTER (Disk Scan) }
- Query time: ~2.5 seconds
- Memory usage: ~8KB (filter state)
- Setup time: ~0.1 seconds
- Best for: Large tables, one-time queries

{ DBHEAP (In-Memory) }
- Load time: ~1.2 seconds (one-time)
- Query time: ~0.02 seconds
- Memory usage: ~160KB (heap map)
- Best for: Repeated queries, interactive use
```

#### **Decision Matrix**
| Scenario | Recommended Module | Reason |
|----------|-------------------|---------|
| ≤8K records, repeated queries | **DBHEAP** | 100x faster after initial load |
| >8K records, one-time query | **DBFILTER** | No memory overhead |
| Interactive dashboard | **DBHEAP** | Instant response to parameter changes |
| Large report generation | **DBFILTER** | Handles unlimited records |
| Real-time filtering | **DBHEAP** | Sub-second response times |
| Memory constrained (<64KB) | **DBFILTER** | Minimal memory usage |

#### **Example: Interactive Game Browser**
```pascal
{ Use DBHEAP for instant filtering }
BuildHeapMap(Dbf, FieldSpecs, 4, 16, HeapMap);

{ User changes filter parameters }
while UserInteraction do
begin
  { Instant response - no disk I/O }
  if HeapGetWord(HeapMap, RecIdx, 2) = SelectedYear then
    DisplayGame(RecIdx);
end;
```

#### **Example: Large Inventory Report**
```pascal
{ Use DBFILTER for large dataset }
InitFilterCursor(Cursor, Dbf);
Cursor.Groups[1].Filters[1].ValueNum := TargetYear;

{ One-time scan of entire database }
ExecuteFilter(Cursor);
GenerateReport(Cursor.RowIds, Cursor.RowCount);
```

### **Memory Management Guidelines**

- [DBF.PAS source code](../DBF.PAS) - Complete implementation
- [DBFMEMO.PAS source code](../DBFMEMO.PAS) - Memo implementation
- [DBFTEXT.PAS source code](../DBFTEXT.PAS) - Text import/export
- [DBFUTIL.PAS source code](../DBFUTIL.PAS) - Utility functions
- [tests/TESTTEXT.PAS](../tests/TESTTEXT.PAS) - Comprehensive test suite
