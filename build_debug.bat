@echo off
set arg1=%1
IF NOT DEFINED arg1 set arg1=just_build
echo %arg1%

IF %arg1%==and_run (SET run_or_build_arg=run)
IF NOT %arg1%==and_run (SET run_or_build_arg=build)
echo %run_or_build_arg%

echo Building game...
odin %run_or_build_arg% src -debug -o:none -out:game.exe -define:DEV=true
if errorlevel 1 goto build_failed

goto end

:build_failed
echo Build Failed!

:end