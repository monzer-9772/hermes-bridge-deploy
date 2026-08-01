@echo off
powershell -ExecutionPolicy Bypass -Command "irm https://raw.githubusercontent.com/monzer-9772/hermes-bridge-deploy/main/finish_setup_v2.ps1 | iex"
pause
