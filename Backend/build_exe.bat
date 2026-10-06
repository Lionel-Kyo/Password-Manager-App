@chcp 65001
@echo off

go build -trimpath -ldflags="-s -w" -o PasswordManagerBackend.exe .

pause
exit
