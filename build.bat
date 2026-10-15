@echo off
rem Build Z-Police: regenerate tables, assemble to zpolice.nex
rem Optional:  build run   -> also launch in CSpect
setlocal
cd /d "%~dp0"
set SJASM=C:\CSpect\sjasmplus.exe
set CSPECT=C:\CSpect\CSpect.exe

python gentables.py || exit /b 1
"%SJASM%" --zxnext --nologo --sym=zpolice.sym  --msg=all --color=auto --lst=zpolice.txt zpolice.asm || exit /b 1

if /i "%1"=="run" "%CSPECT%" -w3 -zxnext -s28 -debug -sound -rewind -nextrom -nodelay -map=zpolice.map "%~dp0zpolice.nex"
