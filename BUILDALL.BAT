@echo off
rem setlocal

set LOG=out.txt
set TPUNITS=C:\TP55\UNITS

echo.>%LOG%
echo ================================>>%LOG%
echo BUILD+RUN START  %DATE%  %TIME%>>%LOG%
echo ================================>>%LOG%
echo.>>%LOG%

REM Clean build artifacts (safe because this runs in C:\temp\dbase-main)
del /q *.tpu 2>nul
del /q build\*.exe 2>nul
del /q tests\*.exe 2>nul
del /q tests\*.tpu 2>nul

echo Building MKUNITS...
echo [LIB] build\mkunits.pas>>%LOG%
tpc /B /Q /U.;%TPUNITS% build\mkunits.pas >>%LOG%
if errorlevel 1 goto :done
echo.>>%LOG%

rem if not exist tests\tests.lst (
rem   echo [TESTS] Missing tests\tests.lst; skipping.>>%LOG%
rem   goto :done
rem )

echo [TESTS] Compile + run>>%LOG%
cd tests

for %%t in (*.pas) do call compile %%t
for %%t in (*.exe) do call runtest %%t

cd ..

:done
echo.>>%LOG%
echo ================================>>%LOG%
echo END  %DATE%  %TIME%>>%LOG%
echo ================================>>%LOG%

rem endlocal
goto :eof

:onetest
echo --- COMPILE %1 --- >>..\%LOG%
tpc /B /Q /U..;%TPUNITS% %1 >>..\%LOG%
if errorlevel 1 (
  echo [FAIL COMPILE] %1>>..\%LOG%
  echo.>>..\%LOG%
  goto :eof
)

REM Figure out exe name: TESTDBF.PAS -> TESTDBF.EXE
set EXE=%1
REM remove extension (DOS SET trick)
for %%x in (%EXE%) do set EXE=%%~nx
REM %%~nx keeps name+ext; we want name only:
for %%x in (%EXE%) do set EXE=%%~nxx
REM Above is a bit DOS-cranky; easiest is just run same base name:
REM We'll do a safer approach below using parameter expansion by FOR:

for %%x in (%1) do set EXE=%%~nxx

echo --- RUN %%EXE%%.EXE --- >>..\%LOG%
%%EXE%%.EXE >>..\%LOG%
echo.>>..\%LOG%
goto :eof

:eof
