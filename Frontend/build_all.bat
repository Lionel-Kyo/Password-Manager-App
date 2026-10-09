@echo off
echo ====================================================
echo Starting Multi-Platform Flutter Build...
echo ====================================================

:: 1. Clean and get dependencies
echo [1/4] Cleaning workspace and fetching dependencies...
call flutter clean
call flutter pub get
if %errorlevel% neq 0 goto :error
echo.

:: 2. Build Web (WASM)
::echo [2/4] Building Flutter Web with WebAssembly (WASM)...
::call flutter build web --wasm
::if %errorlevel% neq 0 goto :error
::echo.

:: 2. Build Web (WASM)
echo [2/4] Building Flutter Web...
call flutter build web
if %errorlevel% neq 0 goto :error
echo.

:: 3. Build Android APK
echo [3/4] Building Android APK (Release)...
call flutter build apk --release
if %errorlevel% neq 0 goto :error
echo.

:: 4. Build Windows EXE
echo [4/4] Building Windows Desktop EXE...
call flutter build windows --release
if %errorlevel% neq 0 goto :error
echo.

echo ====================================================
echo SUCCESS: All platforms built successfully!
echo ====================================================
echo Outputs can be found in:
echo Web (WASM):  .\build\web
echo Android APK: .\build\app\outputs\flutter-apk\app-release.apk
echo Windows EXE: .\build\windows\x64\runner\Release\
echo ====================================================
pause
exit /b 0

:error
echo ====================================================
echo ERROR: Build failed at the last step.
echo ====================================================
pause
exit /b 1
