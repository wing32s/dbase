@echo off
echo Compiling %1...
echo --- COMPILE %1 --- >>..\%LOG%
tpc /B /Q /U..;%TPUNITS% %1 >>..\%LOG%
