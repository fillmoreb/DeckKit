@echo off
rem Battle.net ignores a launch request until it has logged in, and how long that takes varies.
rem So: start it, then every 10 s ask again until Wow.exe is running (gives up after ~3 min).
cd /d "C:\Program Files (x86)\Battle.net"
start "" "Battle.net.exe" --exec="launch WoWF"
set /a tries=0
:wait
call :sleep10
tasklist | find /i "Wow.exe" >nul && goto :eof
set /a tries+=1
if %tries% geq 18 goto :eof
"Battle.net.exe" --exec="launch WoWF"
goto wait

:sleep10
rem timeout can return at once under Wine (it did once); ping 127.0.0.1 is the fallback delay.
timeout /t 10 /nobreak >nul 2>&1
if errorlevel 1 ping -n 11 127.0.0.1 >nul
goto :eof
