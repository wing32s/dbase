unit Assert;

interface

var
  TestsRun: Integer;
  TestsFailed: Integer;

procedure BeginTest(TestName: string);
procedure EndTest;
procedure AssertTrue(Cond: Boolean; Msg: string);
procedure AssertFalse(Cond: Boolean; Msg: string);
procedure AssertEqualsInt(Expected, Actual: LongInt; Msg: string);
procedure AssertEqualsStr(Expected, Actual: string; Msg: string);
procedure ResetAsserts;
procedure PrintSummary;

implementation

var
  CurrentTest: string;
  CurrentFailed: Boolean;
  InTest: Boolean;

procedure BeginTest(TestName: string);
begin
  WriteLn('Starting test: ' + TestName);
  CurrentTest := TestName;
  CurrentFailed := False;
  InTest := True;
end;

procedure EndTest;
begin
  if InTest then
  begin
    Inc(TestsRun);
    if CurrentFailed then
      Inc(TestsFailed);
  end;
  InTest := False;
  CurrentTest := '';
  CurrentFailed := False;
end;

procedure AssertTrue(Cond: Boolean; Msg: string);
begin
  if not Cond then
  begin
    CurrentFailed := True;
    if CurrentTest <> '' then
      WriteLn('FAIL: ', CurrentTest, ': ', Msg)
    else
      WriteLn('FAIL: ', Msg);
  end;
end;

procedure AssertFalse(Cond: Boolean; Msg: string);
begin
  AssertTrue(not Cond, Msg);
end;

procedure AssertEqualsInt(Expected, Actual: LongInt; Msg: string);
begin
  AssertTrue(Expected = Actual, Msg);
end;

procedure AssertEqualsStr(Expected, Actual: string; Msg: string);
begin
  AssertTrue(Expected = Actual, Msg);
  if (CurrentFailed) then
  begin
    WriteLn('   >> EXPECTED: [', Expected, ']');
    WriteLn('   >> ACTUAL: [', Actual, ']');
  end;
end;

procedure ResetAsserts;
begin
  TestsRun := 0;
  TestsFailed := 0;
  CurrentTest := '';
  CurrentFailed := False;
  InTest := False;
end;

procedure PrintSummary;
begin
  WriteLn('Tests: ', TestsRun,
          ' Passed: ', TestsRun - TestsFailed,
          ' Failed: ', TestsFailed);
end;

begin
  ResetAsserts;
end.
