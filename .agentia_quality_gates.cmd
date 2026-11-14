@echo off
setlocal EnableExtensions EnableDelayedExpansion
REM Local Agentia quality gates (Windows).
REM Edit this script to match your project. Agentia runs it from the repo root during
REM `agentia cicd work test` (local by default) and `agentia cicd work submit` (unless --skip-local-tests).
REM The script must exit non-zero if any check fails.
REM
REM Each gate is declared with an "agentia-gate: <id> - <description>" comment and guarded by an AGENTIA_GATES check.
REM `agentia cicd work test --gate lint` runs only the lint gate (AGENTIA_GATES=lint);
REM without --gate (or with --all) every gate runs. Add your own gates with a new id.
if not defined AGENTIA_GATES set "AGENTIA_GATES=all"
set "SELECTED=,!AGENTIA_GATES!,"

REM Code Analyzer scope: "changed" (default) scans only files changed on this branch versus its base branch
REM (committed, uncommitted and untracked; Agentia exports the base as AGENTIA_BASE_BRANCH). It falls back to a
REM full scan when git or the base branch is unavailable. For a full scan once:
REM   agentia cicd work test --gate lint -e LINT_SCOPE=all     (or change the default below)
if not defined LINT_SCOPE set "LINT_SCOPE=changed"
if not defined AGENTIA_BASE_BRANCH set "AGENTIA_BASE_BRANCH=main"

REM agentia-gate: lint - Salesforce Code Analyzer (changed files by default, see LINT_SCOPE)
echo !SELECTED!| findstr /i /c:",all," /c:",lint," >nul && (
  call :code_analyzer
  if errorlevel 1 exit /b !errorlevel!
)

REM agentia-gate: apex - Apex tests (classes from --apex-test-classes)
echo !SELECTED!| findstr /i /c:",all," /c:",apex," >nul && (
  call agentia cicd work test --gate apex --apex-test-classes="!AGENTIA_APEX_TEST_CLASSES!" !AGENTIA_APEX_RERUN_FAILED!
  if errorlevel 1 exit /b !errorlevel!
)

REM agentia-gate: lwc - LWC Jest tests
echo !SELECTED!| findstr /i /c:",all," /c:",lwc," >nul && (
  echo ## Running LWC tests
  call npx sfdx-lwc-jest -- --passWithNoTests
  if errorlevel 1 exit /b !errorlevel!
)

exit /b 0

REM Runs Code Analyzer on the files changed since the merge-base with the base branch, or on everything.
:code_analyzer
set "MERGE_BASE="
if /i "!LINT_SCOPE!"=="changed" (
  for %%r in ("origin/!AGENTIA_BASE_BRANCH!" "!AGENTIA_BASE_BRANCH!") do if not defined MERGE_BASE (
    for /f %%m in ('git merge-base HEAD %%~r 2^>nul') do set "MERGE_BASE=%%m"
  )
)
if not defined MERGE_BASE (
  echo ## Running Code Analyzer on the whole project
  call sf code-analyzer run
  exit /b !errorlevel!
)

set "TARGETS="
set "COUNT=0"
for /f "delims=" %%f in ('git -c core.quotepath=off diff --name-only --diff-filter=ACMR !MERGE_BASE! ^& git -c core.quotepath=off ls-files --others --exclude-standard') do (
  if exist "%%f" (
    set "TARGETS=!TARGETS! --target "%%f""
    set /a COUNT+=1
  )
)
if !COUNT!==0 (
  echo ## Code Analyzer: no changed files, skipping
  exit /b 0
)
echo ## Running Code Analyzer on !COUNT! changed file(s)
call sf code-analyzer run !TARGETS!
exit /b !errorlevel!
