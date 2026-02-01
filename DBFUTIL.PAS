unit DBFUTIL;

interface

uses Dos;

const
  Base64Table: string[64] = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

type
  TByteArray = array[0..65520] of Byte;
  PByteArray = ^TByteArray;
  TB64EncState = record
    Rem: array[0..2] of Byte;
    RemLen: Byte;
  end;

function LowerStr(S: string): string;
function TrimSpaces(S: string): string;
function TrimString(T: string): string;
function PadString(S: string; Len: Integer): string;
function ParseInt(T: string): LongInt;
function ParseWord(T: string): Word;
function ParseByte(T: string): Byte;
function ParseBool(T: string): Boolean;
function IntToStrLocal(Value: Integer): string;
function FloatToStrLocal(Value: Real): string;
function ScaleDecimal(DecimalStr: string; FieldLength: Byte): LongInt;
function UnscaleDecimal(ScaledValue: LongInt; FieldLength: Byte): string;
function FileExists(FileName: string): Boolean;
function DeleteFile(FileName: string): Boolean;
procedure EraseFile(FileName: string);
function RenameFile(OldName, NewName: string): Boolean;
function IsValid83FileName(BaseName: string): Boolean;
function DateToJDN(DateStr: string): LongInt;
function DateToJDNParts(Year, Month, Day: Integer): LongInt;
function DBFDateStrToJDN(DateStr: string): LongInt;
function JDNToDate(JDN: LongInt): string;
function FormatDate(Year, Month, Day: Integer): string;
function FormatTime(Hour, Minute, Second: Integer): string;
function UpperStr(S: string): string;
procedure GetDate(var Year, Month, Day: Word);
procedure MemoryReport(Phase: string);

{ Base64 encoding functions }
function Base64Index(C: Byte): Integer;
procedure B64EncInit(var State: TB64EncState);
procedure B64EncUpdate(var State: TB64EncState; var Buf; Len: Word; var OutF: Text);
procedure B64EncFinal(var State: TB64EncState; var OutF: Text);
procedure WriteEscapedText(var OutF: Text; var Buf; Len: Word);
function Base64DecodedLen(P: PByteArray; Start, Len: LongInt): LongInt;
function EscapedDecodedLen(P: PByteArray; Start, Len: LongInt): LongInt;

implementation

function LowerStr(S: string): string;
var
  I: Integer;
  C: Char;
begin
  for I := 1 to Length(S) do
  begin
    C := S[I];
    if (C >= 'A') and (C <= 'Z') then
      S[I] := Chr(Ord(C) + 32);
  end;
  LowerStr := S;
end;

  function TrimString(T: string): string;
  var
    L, R: Integer;
  begin
    L := 1;
    R := Length(T);
    while (L <= R) and (T[L] = ' ') do
      Inc(L);
    while (R >= L) and (T[R] = ' ') do
      Dec(R);
    if L > R then
      TrimString := ''
    else
      TrimString := Copy(T, L, R - L + 1);
  end;

function TrimSpaces(S: string): string;
begin
  TrimSpaces := TrimString(S);
end;

  function ParseInt(T: string): LongInt;
  var
    V: LongInt;
    Code: Integer;
  begin
    Val(TrimString(T), V, Code);
    if Code <> 0 then
      ParseInt := 0
    else
      ParseInt := V;
  end;

  function ParseWord(T: string): Word;
  var
    W: Word;
    Code: Integer;
  begin
    Val(TrimString(T), W, Code);
    if Code <> 0 then
      W := 0;
    ParseWord := W;
  end;
  
  function ParseByte(T: string): Byte;
  var
    B: Integer;
    Code: Integer;
  begin
    Val(TrimString(T), B, Code);
    if Code <> 0 then
      B := 0;
    ParseByte := B;
  end;
  
  function ParseBool(T: string): Boolean;
  var
    C: Char;
  begin
    T := TrimString(T);
    if Length(T) = 0 then
      ParseBool := False
    else
    begin
      C := UpCase(T[1]);
      ParseBool := (C = 'T') or (C = 'Y') or (C = '1');
    end;
  end;

function PadString(S: string; Len: Integer): string;
begin
  while Length(S) < Len do
    S := S + ' ';
  if Length(S) > Len then
    S := Copy(S, 1, Len);
  PadString := S;
end;

function IntToStrLocal(Value: Integer): string;
var
  S: string;
begin
  Str(Value, S);
  IntToStrLocal := S;
end;

function FloatToStrLocal(Value: Real): string;
var
  S: string;
begin
  Str(Value, S);
  FloatToStrLocal := S;
end;


{ Decimal scaling functions - avoid floating point }
function ScaleDecimal(DecimalStr: string; FieldLength: Byte): LongInt;
var
  IntegerPart, DecimalPart: string;
  DecimalPos: Integer;
  IntVal, DecVal: LongInt;
  Scale: LongInt;
  Code: Integer;
begin
  { Find decimal point }
  DecimalPos := Pos('.', DecimalStr);
  
  if DecimalPos = 0 then
  begin
    { No decimal point - treat as integer }
    Val(DecimalStr, IntVal, Code);
    if Code <> 0 then IntVal := 0;
    ScaleDecimal := IntVal * 1000000;  { Scale by 1,000,000 }
  end
  else
  begin
    { Split into integer and decimal parts }
    IntegerPart := Copy(DecimalStr, 1, DecimalPos - 1);
    DecimalPart := Copy(DecimalStr, DecimalPos + 1, 6);  { Max 6 decimal places }
    
    Val(IntegerPart, IntVal, Code);
    if Code <> 0 then IntVal := 0;
    
    { Pad decimal part to 6 places }
    while Length(DecimalPart) < 6 do
      DecimalPart := DecimalPart + '0';
    
    Val(DecimalPart, DecVal, Code);
    if Code <> 0 then DecVal := 0;
    
    { Combine: integer * scale + decimal }
    if IntVal >= 0 then
      ScaleDecimal := IntVal * 1000000 + DecVal
    else
      ScaleDecimal := IntVal * 1000000 - DecVal;
  end;
end;

function UnscaleDecimal(ScaledValue: LongInt; FieldLength: Byte): string;
var
  IntegerPart, DecimalPart: LongInt;
  IsNegative: Boolean;
  IntStr, DecStr, TempStr: string;
  I: Integer;
  Buf: string;
begin
  IsNegative := ScaledValue < 0;
  if IsNegative then ScaledValue := -ScaledValue;
  
  IntegerPart := ScaledValue div 1000000;
  DecimalPart := ScaledValue mod 1000000;
  
  Str(IntegerPart, IntStr);
  Str(DecimalPart, DecStr);
  
  { Pad decimal part to 6 places }
  while Length(DecStr) < 6 do
    DecStr := '0' + DecStr;
  
  { Remove trailing zeros }
  while (Length(DecStr) > 0) and (DecStr[Length(DecStr)] = '0') do
    Delete(DecStr, Length(DecStr), 1);
  
  if Length(DecStr) = 0 then
  begin
    Buf := IntStr;
  end
  else
  begin
    Buf := IntStr + '.' + DecStr;
  end;
  
  if IsNegative then
    Buf := '-' + Buf;
  UnscaleDecimal := Buf;
end;

{ Check if file exists - Turbo Pascal 5.5 compatible }
function FileExists(FileName: string): Boolean;
var
  TestFile: Text;
  FileFound: Boolean;
begin
  {$I-}  { Turn off I/O checking }
  Assign(TestFile, FileName);
  Reset(TestFile);
  FileFound := (IOResult = 0);  { IOResult = 0 means file exists }
  {$I+}  { Turn on I/O checking }
  if FileFound then Close(TestFile);
  FileExists := FileFound;
end;

{ Delete file - Turbo Pascal 5.5 compatible }
function DeleteFile(FileName: string): Boolean;
var
  TestFile: File;
  FileDeleted: Boolean;
begin
  {$I-}  { Turn off I/O checking }
  Assign(TestFile, FileName);
  Erase(TestFile);
  FileDeleted := (IOResult = 0);  { IOResult = 0 means file deleted successfully }
  {$I+}  { Turn on I/O checking }
  DeleteFile := FileDeleted;
end;

{ Erase file by name; safe if file does not exist }
procedure EraseFile(FileName: string);
var
  TestFile: File;
  Io: Integer;
begin
  {$I-}  { Turn off I/O checking }
  Assign(TestFile, FileName);
  Erase(TestFile);
  Io := IOResult; { clear any I/O error }
  {$I+}  { Turn on I/O checking }
end;

{ Rename file - Turbo Pascal 5.5 compatible }
function RenameFile(OldName, NewName: string): Boolean;
var
  OldFile: File;
  FileRenamed: Boolean;
begin
  {$I-}  { Turn off I/O checking }
  Assign(OldFile, OldName);
  Rename(OldFile, NewName);
  FileRenamed := (IOResult = 0);  { IOResult = 0 means file renamed successfully }
  {$I+}  { Turn on I/O checking }
  RenameFile := FileRenamed;
end;

{ Validate 8.3-style filename (base or base.ext) }
function IsValid83FileName(BaseName: string): Boolean;
var
  DotPos: Integer;
  NamePart, ExtPart: string;
  I: Integer;
  C: Char;
begin
  if Length(BaseName) = 0 then
  begin
    IsValid83FileName := False;
    Exit;
  end;

  DotPos := Length(BaseName);
  while (DotPos >= 1) and (BaseName[DotPos] <> '.') do
    Dec(DotPos);
  if (DotPos >= 1) and (BaseName[DotPos] = '.') then
  begin
    if DotPos = 1 then
    begin
      IsValid83FileName := False;
      Exit;
    end;
    NamePart := Copy(BaseName, 1, DotPos - 1);
    ExtPart := Copy(BaseName, DotPos + 1, 255);
  end
  else
  begin
    NamePart := BaseName;
    ExtPart := '';
  end;
  if (Length(NamePart) = 0) or (Length(NamePart) > 8) then
  begin
    IsValid83FileName := False;
    Exit;
  end;
  if Length(ExtPart) > 3 then
  begin
    IsValid83FileName := False;
    Exit;
  end;
  for I := 1 to Length(NamePart) do
  begin
    C := NamePart[I];
    if not ((C >= 'A') and (C <= 'Z')) and
       not ((C >= 'a') and (C <= 'z')) and
       not ((C >= '0') and (C <= '9')) and
       (C <> '_') and (C <> '-') then
    begin
      IsValid83FileName := False;
      Exit;
    end;
  end;
  for I := 1 to Length(ExtPart) do
  begin
    C := ExtPart[I];
    if not ((C >= 'A') and (C <= 'Z')) and
       not ((C >= 'a') and (C <= 'z')) and
       not ((C >= '0') and (C <= '9')) and
       (C <> '_') and (C <> '-') then
    begin
      IsValid83FileName := False;
      Exit;
    end;
  end;
  if Pos('.', ExtPart) > 0 then
  begin
    IsValid83FileName := False;
    Exit;
  end;
  IsValid83FileName := True;
end;


{ Date conversion functions - Julian Day Number (JDN) }
function DateToJDN(DateStr: string): LongInt;
var
  Year, Month, Day: Integer;
  Code: Integer;
  Y, M, D: LongInt;
begin
  { Parse YYYYMMDD format }
  if Length(DateStr) = 8 then
  begin
    Val(Copy(DateStr, 1, 4), Year, Code);
    Val(Copy(DateStr, 5, 2), Month, Code);
    Val(Copy(DateStr, 7, 2), Day, Code);
    
    if Code = 0 then
    begin
      Y := Year;
      M := Month;
      D := Day;
      { Simple JDN calculation (valid for Gregorian calendar) }
      DateToJDN := (LongInt(1461) * (Y + 4800 + (M - 14) div 12)) div 4 +
                   (LongInt(367) * (M - 2 - 12 * ((M - 14) div 12))) div 12 -
                   (LongInt(3) * ((Y + 4900 + (M - 14) div 12) div 100)) div 4 +
                   D - 32075;
      Exit;
    end;
  end;
  DateToJDN := 0;  { Invalid date }
end;

{ Date conversion using explicit Year/Month/Day parts }
function DateToJDNParts(Year, Month, Day: Integer): LongInt;
var
  A, Y, M: LongInt;
begin
  A := (14 - Month) div 12;
  Y := Year + 4800 - A;
  M := Month + (12 * A) - 3;
  DateToJDNParts := Day + ((153 * M + 2) div 5) + (365 * Y) + (Y div 4) -
                    (Y div 100) + (Y div 400) - 32045;
end;

{ Convert dBASE date string "YYYYMMDD" to JDN, returns 0 if invalid }
function DBFDateStrToJDN(DateStr: string): LongInt;
var
  Year, Month, Day: Integer;
  YearStr, MonthStr, DayStr: string;
  Code: Integer;
begin
  DBFDateStrToJDN := 0;

  { Date must be exactly 8 characters: YYYYMMDD }
  if Length(DateStr) <> 8 then
    Exit;

  { Extract components }
  YearStr := Copy(DateStr, 1, 4);
  MonthStr := Copy(DateStr, 5, 2);
  DayStr := Copy(DateStr, 7, 2);

  { Convert to integers }
  Val(YearStr, Year, Code);
  if Code <> 0 then Exit;

  Val(MonthStr, Month, Code);
  if Code <> 0 then Exit;

  Val(DayStr, Day, Code);
  if Code <> 0 then Exit;

  { Basic validation }
  if (Year < 1) or (Month < 1) or (Month > 12) or (Day < 1) or (Day > 31) then
    Exit;

  { Convert to JDN }
  DBFDateStrToJDN := DateToJDNParts(Year, Month, Day);
end;

function JDNToDate(JDN: LongInt): string;
var
  A, B, C, D, E, M: LongInt;
  Year, Month, Day: Integer;
begin
  if JDN <= 0 then
  begin
    JDNToDate := '';
    Exit;
  end;
  
  { Convert JDN back to YYYYMMDD format }
  A := JDN + 32044;
  B := (4 * A + 3) div 146097;
  C := A - (146097 * B) div 4;
  D := (4 * C + 3) div 1461;
  E := C - (1461 * D) div 4;
  M := (5 * E + 2) div 153;
  
  Day := E - (153 * M + 2) div 5 + 1;
  Month := M + 3 - 12 * (M div 10);
  Year := 100 * B + D - 4800 + (M div 10);
  
  JDNToDate := FormatDate(Year, Month, Day);
end;


{ Date formatting function for YYYYMMDD format }
function FormatDate(Year, Month, Day: Integer): string;
var
  YearStr, MonthStr, DayStr: string;
begin
  Str(Year, YearStr);
  Str(Month, MonthStr);
  Str(Day, DayStr);
  
  { Ensure two-digit month and day }
  if Length(MonthStr) = 1 then MonthStr := '0' + MonthStr;
  if Length(DayStr) = 1 then DayStr := '0' + DayStr;
  
  FormatDate := YearStr + MonthStr + DayStr;
end;

{ Time formatting function for HHMMSS format }
function FormatTime(Hour, Minute, Second: Integer): string;
var
  HourStr, MinStr, SecStr: string;
begin
  Str(Hour, HourStr);
  Str(Minute, MinStr);
  Str(Second, SecStr);
  
  { Ensure two-digit values }
  if Length(HourStr) = 1 then HourStr := '0' + HourStr;
  if Length(MinStr) = 1 then MinStr := '0' + MinStr;
  if Length(SecStr) = 1 then SecStr := '0' + SecStr;
  
  FormatTime := HourStr + MinStr + SecStr;
end;

function UpperStr(S: string): string;
var
  I: Integer;
begin
  for I := 1 to Length(S) do
    S[I] := UpCase(S[I]);
  UpperStr := S;
end;

{ Base64 encoding implementation }

function Base64Index(C: Byte): Integer;
var
  I: Integer;
begin
  Base64Index := -1;
  for I := 1 to Length(Base64Table) do
    if Ord(Base64Table[I]) = C then
    begin
      Base64Index := I - 1;
      Exit;
    end;
end;

procedure B64EncInit(var State: TB64EncState);
begin
  State.RemLen := 0;
end;

procedure B64EncOut3(B1, B2, B3: Byte; var OutF: Text);
var
  C1, C2, C3, C4: Byte;
begin
  C1 := (B1 shr 2) and $3F;
  C2 := ((B1 shl 4) and $30) or ((B2 shr 4) and $0F);
  C3 := ((B2 shl 2) and $3C) or ((B3 shr 6) and $03);
  C4 := B3 and $3F;
  Write(OutF, Base64Table[C1 + 1], Base64Table[C2 + 1],
               Base64Table[C3 + 1], Base64Table[C4 + 1]);
end;

procedure B64EncUpdate(var State: TB64EncState; var Buf; Len: Word; var OutF: Text);
var
  P: PByteArray;
  I: Word;
  B: Byte;
begin
  P := @Buf;
  I := 0;
  while (State.RemLen < 3) and (I < Len) do
  begin
    State.Rem[State.RemLen] := P^[I];
    Inc(State.RemLen);
    Inc(I);
  end;
  if State.RemLen = 3 then
  begin
    B64EncOut3(State.Rem[0], State.Rem[1], State.Rem[2], OutF);
    State.RemLen := 0;
  end;
  while I + 2 < Len do
  begin
    B64EncOut3(P^[I], P^[I + 1], P^[I + 2], OutF);
    Inc(I, 3);
  end;
  while I < Len do
  begin
    B := P^[I];
    State.Rem[State.RemLen] := B;
    Inc(State.RemLen);
    Inc(I);
  end;
end;

procedure B64EncFinal(var State: TB64EncState; var OutF: Text);
var
  C1, C2, C3: Byte;
begin
  if State.RemLen = 1 then
  begin
    C1 := (State.Rem[0] shr 2) and $3F;
    C2 := (State.Rem[0] shl 4) and $30;
    Write(OutF, Base64Table[C1 + 1], Base64Table[C2 + 1], '=', '=');
  end
  else if State.RemLen = 2 then
  begin
    C1 := (State.Rem[0] shr 2) and $3F;
    C2 := ((State.Rem[0] shl 4) and $30) or ((State.Rem[1] shr 4) and $0F);
    C3 := (State.Rem[1] shl 2) and $3C;
    Write(OutF, Base64Table[C1 + 1], Base64Table[C2 + 1],
                 Base64Table[C3 + 1], '=');
  end;
  State.RemLen := 0;
end;

procedure WriteEscapedText(var OutF: Text; var Buf; Len: Word);
var
  P: PByteArray;
  I: Word;
  C: Byte;
begin
  P := @Buf;
  for I := 0 to Len - 1 do
  begin
    C := P^[I];
    case C of
      10: Write(OutF, '\n');
      13: Write(OutF, '\r');
      9: Write(OutF, '\t');
      Ord('\'): Write(OutF, '\\');
      Ord('|'): Write(OutF, '\|');
    else
      Write(OutF, Chr(C));
    end;
  end;
end;


function Base64DecodedLen(P: PByteArray; Start, Len: LongInt): LongInt;
var
  I: LongInt;
  Count: LongInt;
  Pad: LongInt;
  C: Byte;
begin
  Count := 0;
  Pad := 0;
  for I := Start to Start + Len - 1 do
  begin
    C := P^[I];
    if not ((C = Ord(' ')) or (C = 9)) then
    begin
      if C = Ord('=') then
      begin
        Inc(Pad);
        Inc(Count);
      end
      else if Base64Index(C) >= 0 then
        Inc(Count);
    end;
  end;
  if (Count = 0) or ((Count mod 4) <> 0) then
  begin
    Base64DecodedLen := -1;
    Exit;
  end;
  if Pad > 2 then Pad := 2;
  Base64DecodedLen := (Count div 4) * 3 - Pad;
end;

function EscapedDecodedLen(P: PByteArray; Start, Len: LongInt): LongInt;
var
  I: LongInt;
  Count: LongInt;
begin
  Count := 0;
  I := Start;
  while I < Start + Len do
  begin
    if (P^[I] = Ord('\')) and (I + 1 < Start + Len) then
    begin
      Inc(I, 2);
      Inc(Count);
    end
    else
    begin
      Inc(I);
      Inc(Count);
    end;
  end;
  EscapedDecodedLen := Count;
end;

{ GetDate - Get current system date }
procedure GetDate(var Year, Month, Day: Word);
var
  DayOfWeek: Word;
begin
  { Use Turbo Pascal's built-in GetDate function from Dos unit }
  { This is a wrapper to provide consistent interface }
  { Dos.GetDate requires 4 parameters: Year, Month, Day, DayOfWeek }
  Dos.GetDate(Year, Month, Day, DayOfWeek);
end;


{ Memory tracking for DBF module overhead analysis }
procedure MemoryReport(Phase: string);
begin
  WriteLn('=== ', Phase, ' ===');
  WriteLn('Heap Available: ', MemAvail, ' bytes');
  WriteLn('Largest Block: ', MaxAvail, ' bytes');
  WriteLn;
end;

end.
