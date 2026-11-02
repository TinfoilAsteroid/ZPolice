@echo off
rem Build Z-Police: regenerate tables, assemble to zpolice.nex
rem Optional:  build run       -> also launch in CSpect (sound off: -sound)
rem            build runsound  -> launch in CSpect with sound on
rem            build notest    -> skip the regression tests (tests\run_tests.py),
rem                               e.g. build run notest
setlocal
cd /d "%~dp0"
set SJASM=C:\CSpect\sjasmplus.exe
set CSPECT=C:\CSpect\CSpect.exe

python gengraphics.py || exit /b 1
python gentables.py || exit /b 1
"%SJASM%" --zxnext --nologo --sym=zpolice.sym  --msg=all --color=auto --lst=zpolice.txt zpolice.asm || exit /b 1

set TESTS=1
for %%a in (%*) do if /i "%%a"=="notest" set TESTS=0
if "%TESTS%"=="1" python tests\run_tests.py || exit /b 1

if /i "%1"=="run" "%CSPECT%" -w3 -zxnext -s28 -debug -sound -rewind -nextrom -nodelay -map=zpolice.map "%~dp0zpolice.nex"
if /i "%1"=="runsound" "%CSPECT%" -w3 -zxnext -s28 -debug -rewind -nextrom -nodelay -map=zpolice.map "%~dp0zpolice.nex"
