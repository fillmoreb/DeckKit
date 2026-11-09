@echo off
rem Starts Battle.net and has it launch WoW: Forever as soon as it can.
rem
rem Battle.net ignores "launch" requests until it has logged in (an --exec on its command line at a
rem cold start only selects the game). So: start it, find the log file it just created, wait for
rem the line it writes when login completes, then ask. Until Wow.exe shows up, ask again every 3 s,
rem and every 10 s once 30 s have gone by; give up after about 3 minutes. If the log can't be found
rem or never shows the line, it just falls back to asking on that schedule.
rem Under Wine "timeout" returns at once, so every delay here is ping: "ping -n N" waits N-1 seconds.
setlocal EnableDelayedExpansion
set "LOGS=%LOCALAPPDATA%\Battle.net\Logs"
set "OK=Logged into Battle.net successfully"

set "BEFORE="
for /f "delims=" %%f in ('dir /b /o-n "%LOGS%\battle.net-*.log" 2^>nul') do if not defined BEFORE set "BEFORE=%%f"

cd /d "C:\Program Files (x86)\Battle.net"
start "" "Battle.net.exe" --exec="launch WoWF"

rem The new Battle.net's log: the newest one, once it's newer than BEFORE (up to 10 s).
set "LOG="
for /l %%i in (1,1,10) do if not defined LOG (
    ping -n 2 127.0.0.1 >nul
    for /f "delims=" %%f in ('dir /b /o-n "%LOGS%\battle.net-*.log" 2^>nul') do (
        if not defined LOG if /i "%%f" gtr "!BEFORE!" set "LOG=%%f"
    )
)

rem Wait for the login line (up to 40 s; login took about 14 s on 2026-11-09).
set "READY="
if defined LOG for /l %%i in (1,1,40) do if not defined READY (
    find "%OK%" "%LOGS%\!LOG!" >nul 2>&1 && (set "READY=1") || ping -n 2 127.0.0.1 >nul
)
rem Battle.net sets up its game accounts just after logging in.
if defined READY ping -n 2 127.0.0.1 >nul

set /a waited=0
:ask
tasklist | find /i "Wow.exe" >nul && goto :eof
"Battle.net.exe" --exec="launch WoWF"
set /a gap=3
if %waited% geq 30 set /a gap=10
set /a pings=gap+1
ping -n %pings% 127.0.0.1 >nul
set /a waited+=gap
if %waited% lss 180 goto ask
goto :eof
