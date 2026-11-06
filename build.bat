@echo off
rem Build Z-Police: regenerate tables, assemble to zpolice.nex
rem Optional:  build run       -> also launch in CSpect (sound off: -sound)
rem            build runsound  -> launch in CSpect with sound on
rem            build notest    -> skip the regression tests (tests\run_tests.py),
rem                               e.g. build run notest
rem            build release   -> then a release build in release\: no debug
rem                               keys, load-out or upgrades (the tests run on
rem                               the debug build first; release_check on it).
rem                               With run or runsound it launches that one
setlocal
cd /d "%~dp0"
set SJASM=C:\CSpect\sjasmplus.exe
set CSPECT=C:\CSpect\CSpect.exe

set TESTS=1
set RELEASE=0
set RUN=
for %%a in (%*) do (
    if /i "%%a"=="notest" set TESTS=0
    if /i "%%a"=="release" set RELEASE=1
    if /i "%%a"=="run" set RUN=run
    if /i "%%a"=="runsound" set RUN=runsound
)

python gengraphics.py || exit /b 1
python gentables.py || exit /b 1
"%SJASM%" --zxnext --nologo --sym=zpolice.sym  --msg=all --color=auto --lst=zpolice.txt zpolice.asm || exit /b 1

if "%TESTS%"=="1" python tests\run_tests.py || exit /b 1

if "%RELEASE%"=="1" goto release
if "%RUN%"=="run" "%CSPECT%" -w3 -zxnext -s28 -debug -sound -rewind -nextrom -nodelay -map=zpolice.map "%~dp0zpolice.nex"
if "%RUN%"=="runsound" "%CSPECT%" -w3 -zxnext -s28 -debug -rewind -nextrom -nodelay -map=zpolice.map "%~dp0zpolice.nex"
exit /b 0

:release
if not exist release_tmp mkdir release_tmp
"%SJASM%" --zxnext --nologo -DRELEASE --sym=release_tmp\zpolice.sym --msg=all --color=auto --lst=release_tmp\zpolice.txt zpolice.asm || exit /b 1
python tools\make_release.py || exit /b 1
python tests\release_check.py
if errorlevel 1 (
    rmdir /s /q release
    echo The release failed its check: release\ removed
    exit /b 1
)
cd /d "%~dp0release"
if "%RUN%"=="run" "%CSPECT%" -w3 -zxnext -s28 -sound -nextrom -nodelay "%~dp0release\zpolice.nex"
if "%RUN%"=="runsound" "%CSPECT%" -w3 -zxnext -s28 -nextrom -nodelay "%~dp0release\zpolice.nex"
exit /b 0
