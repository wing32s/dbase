@echo off
echo Running %1...
echo --- RUN %1 --- >>..\%LOG%
%1 >>..\%LOG%
echo.>>..\%LOG%
