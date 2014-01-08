@rem Copyright (c) 2013 Google, Inc.
@rem
@rem This software is provided 'as-is', without any express or implied
@rem warranty.  In no event will the authors be held liable for any damages
@rem arising from the use of this software.
@rem Permission is granted to anyone to use this software for any purpose,
@rem including commercial applications, and to alter it and redistribute it
@rem freely, subject to the following restrictions:
@rem 1. The origin of this software must not be misrepresented; you must not
@rem claim that you wrote the original software. If you use this software
@rem in a product, an acknowledgment in the product documentation would be
@rem appreciated but is not required.
@rem 2. Altered source versions must be plainly marked as such, and must not be
@rem misrepresented as being the original software.
@rem 3. This notice may not be removed or altered from any source distribution.
@echo off
rem See help text below or run with -h for a description of this batch file.

rem Project name.
set project_name=LiquidFun
rem Minimum cmake version this project has been tested with.
set cmake_minversion_minmaj=2.8
rem Build configuration options.
set solution_to_build=Box2D.sln
rem Default set of configurations to build.
set build_configuration_default=Debug MinSizeRel Release RelWithDebInfo
rem Default arguments for msbuild.exe.
set msbuild_args=/m:%NUMBER_OF_PROCESSORS% /t:Rebuild
rem Newest and oldest version of Visual Studio that it's possible to select.
set visual_studio_version_max=12
set visual_studio_version_min=8
rem Enable clean step by default.
set clean=1
rem Enable dry run mode by setting this to "echo"
set dryrun=

rem Directory containing this file.
set batch_file_dir=%~d0%~p0

rem Display help text and exit the script.
goto display_help_end
:display_help
  echo Generate Visual Studio Solution for %project_name% and build the
  echo specified set of configurations.
  echo.
  echo Usage: %~nx0 [-n] [-d] [-b build_configurations]
  echo          [-s visual_studio_version]
  echo          [build_configurations] [visual_studio_version]
  echo.
  echo -n: Builds the solution without cleaning first.
  echo.
  echo -d: Display the build commands this script would run without building.
  echo.
  echo -b build_configurations: Is space separated list of build configurations
  echo that should be built by this script.  If this isn't specified it
  echo defaults to all build configurations generated by CMake
  echo "Debug MinSizeRel Release RelWithDebInfo".
  echo .
  echo -s visual_studio_version: Version of Visual Studio cmake generator to
  echo use.  If this isn't specified the newest version of Visual Studio
  echo installed will be selected.
  echo.
  echo build_configurations: Legacy form of '-b build_configurations'.
  echo.
  echo visual_studio_version: Legacy form of '-s visual_studio_version'.
  echo.
  echo For example to just build the Debug configuration:
  echo   %~nx0 Debug
  echo.
  exit /B -1
:display_help_end

rem Disable the clean step.
goto disable_clean_end
:disable_clean
  set clean=0
  set msbuild_args=%msbuild_args:Rebuild=Build%
  goto:eof
:disable_clean_end

rem Set the build configuration to %1 or fallback to the default set if %1 is
rem an empty string.
goto set_build_config_end
:set_build_config
  if not "%1"=="" set build_configuration=%1
  if "%build_configuration%"=="" (
    set build_configuration=%build_configuration_default%
  )
  goto:eof
:set_build_config_end

rem Set the visual studio version to %1 or fallback to searching for the
rem generator if %1 is an empty string.
goto set_vs_ver_end
:set_vs_ver
  if not "%1"=="" set visual_studio_version=%1
  goto:eof
:set_vs_ver_end

rem Change into this batch file's directory.
cd %batch_file_dir%

rem Parse switches.
:parse_args
  set current_arg=%1
  rem Determine whether this is a switch (starts with "-").
  set arg_first_character=%current_arg:~0,1%
  if not "%arg_first_character%"=="-" (
    rem Not a switch, continue to positional argument parsing.
    goto parse_args_end
  )
  shift
  rem Interpret switches.
  if "%current_arg%"=="-h" goto display_help
  if "%current_arg%"=="-n" call :disable_clean
  if "%current_arg%"=="-d" set dryrun=echo
  if "%current_arg%"=="-b" (
    call :set_build_config %1
    shift
  )
  if "%current_arg%"=="-s" (
    call :set_vs_ver %1
    shift
  )
goto parse_args
:parse_args_end
rem Parse positional arguments.
call :set_build_config %1
call :set_vs_ver %2

rem Search the path for cmake.
set cmake=
rem Look for a prebuilt cmake in the tree.
set android_root=..\..\..\..\..\..\
for %%a in (%android_root%) do (
  set android_root=%%~da%%~pa
)
set cmake_prebuilts_root=%android_root%prebuilts\cmake\windows
for /F %%a in ('dir /b %cmake_prebuilts_root%\cmake-*') do (
  if exist %cmake_prebuilts_root%\%%a\bin\cmake.exe (
    set cmake_prebuilt=%cmake_prebuilts_root%\%%a\bin\cmake.exe
    goto found_cmake_prebuilt
  )
)
:found_cmake_prebuilt

if exist %cmake_prebuilt% (
  set cmake=%cmake_prebuilt%
  goto check_cmake_version
)
echo Searching PATH for cmake. >&2
for /F "delims=;" %%a in ('where cmake') do set cmake=%%a
if exist "%cmake%" goto check_cmake_version
echo Unable to find cmake %cmake_minversion_minmaj% on this machine.>&2
exit /B -1
:check_cmake_version
rem Get the absolute path of cmake.
for /F "delims=;" %%a in ("%cmake%") do set cmake="%%~da%%~pa%%~na%%~xa"

rem Verify the version of cmake found in the path is the same version or
rem newer than the version this project has been tested against.
set cmake_version=
for /F "tokens=3" %%a in ('%cmake% --version') do set cmake_version=%%a
if "%cmake_version%" == "" (
  echo Unable to get version of cmake %cmake%. >&2
  exit /B 1
)
set cmake_ver_minmaj=
for /F "tokens=1,2 delims=." %%a in ("%cmake_version%") do (
  set cmake_ver_minmaj=%%a.%%b
)
if %cmake_ver_minmaj% LSS %cmake_minversion_minmaj% (
  echo %cmake% %cmake_version% older than required version ^
%cmake_minversion_minmaj% >&2
  exit /B -1
)

rem Determine whether the selected version of visual studio is installed.
setlocal enabledelayedexpansion
if not "%visual_studio_version%"=="" (
  reg query ^
    HKLM\SOFTWARE\Microsoft\VisualStudio\%visual_studio_version%.0 /ve ^
    1>NUL 2>NUL
  if !ERRORLEVEL! EQU 0 (
    goto found_vs
  )
)

rem Determine the newest version of Visual Studio installed on this machine.
set visual_studio_version=
for /L %%a in (%visual_studio_version_max%,-1,%visual_studio_version_min%) do (
  echo Searching for Visual Studio %%a >&2
  reg query HKLM\SOFTWARE\Microsoft\VisualStudio\%%a.0 /ve 1>NUL 2>NUL
  if !ERRORLEVEL! EQU 0 (
    set visual_studio_version=%%a
    goto found_vs
  )
)
echo Unable to determine whether Visual Studio is installed. >&2
exit /B 1
:found_vs

rem Map Visual Studio version to cmake generator name.
if "%visual_studio_version%"=="8" (
  set cmake_generator=Visual Studio 8 2005
)
if "%visual_studio_version%"=="9" (
  set cmake_generator=Visual Studio 9 2008
)
if %visual_studio_version% GEQ 10 (
  set cmake_generator=Visual Studio %visual_studio_version%
)

rem Generate Visual Studio solution.
cd ..
set run_cmake=1
if "%clean%"=="0" (
  rem Don't regenerate the Visual Studio solution if the clean build step is
  rem disabled.
  rem NOTE: This will result in changes to CMakeLists.txt and any dependencies
  rem not being reflected in the generated solution and projects.
  if exist Box2D.sln (
    set run_cmake=0
  )
)
if "%run_cmake%"=="1" (
  echo Generating solution for %cmake_generator%. >&2
  %cmake% -G"%cmake_generator%"
  if %ERRORLEVEL% NEQ 0 (
    exit /B %ERRORLEVEL%
  )
)
endlocal

rem Build the project.
for %%c in (%build_configuration%) do (
  cd %batch_file_dir%/..
  echo Building %solution_to_build% with the %%c configuration. >&2
  %dryrun% AutoBuild\msbuild.bat %msbuild_args% /p:Configuration=%%c ^
    %solution_to_build%
)
