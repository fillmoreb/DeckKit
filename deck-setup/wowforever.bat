@echo off
rem Starts Battle.net and has it launch WoW: Forever as soon as it can.
rem
rem Battle.net ignores "launch" requests until it has logged in (an --exec on its command line at a
rem cold start only selects the game), and login takes 10-15 s. So: start it, wait 8 s, then ask
rem every 2 s until Wow.exe is running (every 10 s once 40 s have gone by; give up after ~3 min).
rem Requests that arrive before login are ignored, so asking often only costs a quick extra process.
rem (Watching Battle.net's log for its login line doesn't work from inside Wine: the line isn't
rem visible to cmd until later. Tried 2026-11-09.)
rem Under Wine "timeout" returns at once, so every delay here is ping: "ping -n N" waits N-1 seconds.
cd /d "C:\Program Files (x86)\Battle.net"
start "" "Battle.net.exe" --exec="launch WoWF"
ping -n 9 127.0.0.1 >nul
set /a waited=8

:ask
tasklist | find /i "Wow.exe" >nul && goto :eof
"Battle.net.exe" --exec="launch WoWF"
set /a gap=2
if %waited% geq 40 set /a gap=10
set /a pings=gap+1
ping -n %pings% 127.0.0.1 >nul
set /a waited+=gap
if %waited% lss 180 goto ask
goto :eof
