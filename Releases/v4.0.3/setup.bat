@echo off
setlocal enabledelayedexpansion

echo ============================================================
echo              ATHENA - Company Knowledge Assistant
echo                      Setup Script v4.0.3
echo ============================================================
echo.

:: -----------------------------------------------------------
:: 1. Read vault path from .vault-path
:: -----------------------------------------------------------
SET "VAULT_PATH_FILE=%~dp0.vault-path"
if not exist "%VAULT_PATH_FILE%" (
    echo ERROR: .vault-path file not found at %VAULT_PATH_FILE%
    echo Cannot proceed without a valid vault path.
    echo.
    pause
    exit /b 1
)

SET /P VAULT_PATH_UNIX=<"%VAULT_PATH_FILE%"
if "!VAULT_PATH_UNIX!"=="" (
    echo ERROR: .vault-path file is empty.
    echo.
    pause
    exit /b 1
)

echo Vault path: !VAULT_PATH_UNIX!
echo.

:: -----------------------------------------------------------
:: 2. Check for bun
:: -----------------------------------------------------------
echo ------------------------------------------------------------
echo  Checking dependencies...
echo ------------------------------------------------------------
echo.

where bun >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Bun not found. Installing bun...
    powershell -NoProfile -Command "irm bun.sh/install.ps1 | iex"
    SET "PATH=%USERPROFILE%\.bun\bin;!PATH!"
    echo Bun installed.
) else (
    echo [OK] Bun found.
)

:: -----------------------------------------------------------
:: 3. Check for Claude Code
:: -----------------------------------------------------------
where claude >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo.
    echo [WARNING] Claude Code not found. Install it from https://claude.ai/download before using ATHENA.
) else (
    echo [OK] Claude Code found.
)
echo.

:: -----------------------------------------------------------
:: 4. Prompt for employee info
:: -----------------------------------------------------------
echo ------------------------------------------------------------
echo  Employee Information
echo ------------------------------------------------------------
echo.

SET /P EMP_NAME=Full name:
SET /P EMP_EMAIL=Email:

echo.
echo Select your department:
echo   1) engineering
echo   2) product
echo   3) design
echo   4) hr
echo   5) finance
echo   6) company-wide
echo.
SET /P DEPT_CHOICE=Enter number (1-6):

if "!DEPT_CHOICE!"=="1" SET "EMP_DEPT=engineering"
if "!DEPT_CHOICE!"=="2" SET "EMP_DEPT=product"
if "!DEPT_CHOICE!"=="3" SET "EMP_DEPT=design"
if "!DEPT_CHOICE!"=="4" SET "EMP_DEPT=hr"
if "!DEPT_CHOICE!"=="5" SET "EMP_DEPT=finance"
if "!DEPT_CHOICE!"=="6" SET "EMP_DEPT=company-wide"

if not defined EMP_DEPT (
    echo Invalid selection. Defaulting to company-wide.
    SET "EMP_DEPT=company-wide"
)

echo.
echo Department: !EMP_DEPT!
echo.

:: -----------------------------------------------------------
:: 5. Generate employee ID
:: -----------------------------------------------------------
SET "EMP_ID=emp_%USERNAME%"
echo Employee ID: !EMP_ID!
echo.

:: -----------------------------------------------------------
:: 6. Create directories
:: -----------------------------------------------------------
echo ------------------------------------------------------------
echo  Setting up directories...
echo ------------------------------------------------------------
echo.

if not exist "%USERPROFILE%\.claude\" mkdir "%USERPROFILE%\.claude"
if not exist "%USERPROFILE%\.claude\hooks\" mkdir "%USERPROFILE%\.claude\hooks"
if not exist "%USERPROFILE%\.claude\hooks\lib\" mkdir "%USERPROFILE%\.claude\hooks\lib"

echo [OK] Directories created.
echo.

:: -----------------------------------------------------------
:: 7. Copy files from release
:: -----------------------------------------------------------
echo ------------------------------------------------------------
echo  Copying files...
echo ------------------------------------------------------------
echo.

xcopy /Y /E "%~dp0.claude\hooks\*" "%USERPROFILE%\.claude\hooks\" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] Hooks copied.
) else (
    echo [WARNING] Could not copy hooks.
)

copy /Y "%~dp0.claude\CLAUDE.md" "%USERPROFILE%\.claude\CLAUDE.md" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] CLAUDE.md copied.
) else (
    echo [WARNING] Could not copy CLAUDE.md.
)

copy /Y "%~dp0.claude\company-roles.json" "%USERPROFILE%\.claude\company-roles.json" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    echo [OK] company-roles.json copied.
) else (
    echo [WARNING] Could not copy company-roles.json.
)

echo.

:: -----------------------------------------------------------
:: 8. Generate employee.json
:: -----------------------------------------------------------
echo ------------------------------------------------------------
echo  Generating employee.json...
echo ------------------------------------------------------------
echo.

(
echo {
echo   "employee_id": "!EMP_ID!",
echo   "name": "!EMP_NAME!",
echo   "email": "!EMP_EMAIL!",
echo   "department": "!EMP_DEPT!",
echo   "role": "viewer",
echo   "clearance": "public"
echo }
) > "%USERPROFILE%\.claude\employee.json"

echo [OK] employee.json created.
echo.

:: -----------------------------------------------------------
:: 9. Generate settings.json from template
:: -----------------------------------------------------------
echo ------------------------------------------------------------
echo  Generating settings.json...
echo ------------------------------------------------------------
echo.

SET "HOOKS_DIR_UNIX=%USERPROFILE:\=/%/.claude/hooks"

powershell -NoProfile -Command "(Get-Content '%~dp0.claude\settings.json' -Raw) -replace '__VAULT_PATH__', '!VAULT_PATH_UNIX!' -replace '__HOOKS_DIR__', '!HOOKS_DIR_UNIX!' | Set-Content '%USERPROFILE%\.claude\settings.json'"

if %ERRORLEVEL% EQU 0 (
    echo [OK] settings.json created.
) else (
    echo [WARNING] Could not generate settings.json. Check that the template exists.
)

echo.

:: -----------------------------------------------------------
:: 10. Write version marker
:: -----------------------------------------------------------
echo v4.0.3> "%USERPROFILE%\.claude\.athena-version"

:: -----------------------------------------------------------
:: 11. Final message
:: -----------------------------------------------------------
echo.
echo ============================================================
echo              ATHENA setup complete!
echo ============================================================
echo.
echo  Your employee ID: !EMP_ID!
echo  Role: viewer (public clearance) -- ask your admin to add
echo  you to the roster for elevated access.
echo.
echo  Start Claude Code in any project and ATHENA will greet you.
echo.
echo ============================================================
echo.

pause
