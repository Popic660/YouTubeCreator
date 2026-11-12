@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >nul
set "ROOT=%~dp0"
if "%ROOT:~-1%"=="\" set "ROOT=%ROOT:~0,-1%"
cd /d "%ROOT%"

echo [1/3] Tools

set "QTDIR=%QTDIR%"
if not defined QTDIR set "QTDIR=%CMAKE_PREFIX_PATH%"
if not defined QTDIR if exist "C:\Qt1\6.10.2\msvc2022_64\bin\windeployqt.exe" set "QTDIR=C:\Qt1\6.10.2\msvc2022_64"
if not defined QTDIR if exist "C:\Qt\6.10.2\msvc2022_64\bin\windeployqt.exe" set "QTDIR=C:\Qt\6.10.2\msvc2022_64"
if not exist "%QTDIR%\bin\windeployqt.exe" (
  echo ERROR: Qt msvc2022_64 not found. Set QTDIR, for example:
  echo   set QTDIR=C:\Qt1\6.10.2\msvc2022_64
  exit /b 1
)

if not defined FFMPEG_ROOT goto :no_ffmpeg
if "%FFMPEG_ROOT%"=="" goto :no_ffmpeg
goto :ffmpeg_ok
:no_ffmpeg
echo ERROR: FFmpeg shared not found. Set FFMPEG_ROOT, for example:
echo   set FFMPEG_ROOT=C:\ffmpeg-9.0.2-full_build-shared
exit /b 1
:ffmpeg_ok
if not exist "%FFMPEG_ROOT%\include\libavcodec\avcodec.h" (
  echo ERROR: FFMPEG_ROOT has no libavcodec headers:
  echo   %FFMPEG_ROOT%
  exit /b 1
)
for %%I in ("%FFMPEG_ROOT%") do set "FFMPEG_ROOT=%%~sI"

set "VCVARS="
for %%P in (
  "%ProgramFiles%\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles%\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles%\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
  "%ProgramFiles(x86)%\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat"
) do if exist "%%~P" if not defined VCVARS set "VCVARS=%%~P"
if not defined VCVARS (
  echo ERROR: vcvars64.bat not found. Install Visual Studio 2022 C++ tools.
  exit /b 1
)
call "%VCVARS%" >nul
if errorlevel 1 (
  echo ERROR: failed to load MSVC environment.
  exit /b 1
)

set "CMAKE_EXE="
where cmake >nul 2>&1 && for /f "delims=" %%P in ('where cmake') do if not defined CMAKE_EXE set "CMAKE_EXE=%%P"
if not defined CMAKE_EXE if exist "%ProgramFiles%\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe" set "CMAKE_EXE=%ProgramFiles%\Microsoft Visual Studio\2022\Community\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
if not defined CMAKE_EXE (
  echo ERROR: cmake.exe not found.
  exit /b 1
)
for %%P in ("%CMAKE_EXE%") do set "CTEST_EXE=%%~dpPctest.exe"
if not exist "%CTEST_EXE%" set "CTEST_EXE=ctest"

set "PATH=%QTDIR%\bin;%PATH%"
echo   Qt      %QTDIR%
echo   CMake   %CMAKE_EXE%
echo   FFmpeg  %FFMPEG_ROOT%

echo [2/3] Configure and build Release
"%CMAKE_EXE%" -S "%ROOT%" -B "%ROOT%\build" -G "NMake Makefiles" -DCMAKE_BUILD_TYPE=Release -DCMAKE_PREFIX_PATH="%QTDIR%" -DFFMPEG_ROOT="%FFMPEG_ROOT%"
if errorlevel 1 exit /b 1
"%CMAKE_EXE%" --build "%ROOT%\build" --target youtube-creator --target shell_tests
if errorlevel 1 exit /b 1

echo [3/3] Tests
set "QT_QPA_PLATFORM=offscreen"
"%ROOT%\build\shell_tests.exe" -v1 -o "%ROOT%\build\shell-tests.txt,txt"
set "TEST_CODE=%ERRORLEVEL%"
if exist "%ROOT%\build\shell-tests.txt" type "%ROOT%\build\shell-tests.txt"
if not "%TEST_CODE%"=="0" exit /b %TEST_CODE%

if not exist "%ROOT%\build\youtube-creator.exe" (
  echo ERROR: youtube-creator.exe was not built.
  exit /b 1
)

echo.
echo youtube-creator.exe
echo   %ROOT%\build\youtube-creator.exe
exit /b 0
