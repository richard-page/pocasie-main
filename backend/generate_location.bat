@echo off
REM Generuje ECMWF JSON pre konkrétne mesto
REM Použitie: generate_location.bat "Meno Mesta" lat lon
REM Príklad: generate_location.bat "Hlohovec" 48.43 17.80

if "%~3"=="" (
    echo Použitie: %0 "Nazov" lat lon
    echo Príklad: %0 "Hlohovec" 48.43 17.80
    exit /b 1
)

python fetch_ecmwf_official.py %1 %2 %3
