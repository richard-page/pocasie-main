@echo off
REM Pridá novú lokalitu - vygeneruje JSON a pushne na GitHub
REM Použitie: new_location.bat "Nazov" lat lon

if "%~3"=="" (
    echo Použitie: %0 "Nazov Mesta" lat lon
    echo Príklad: %0 "Hlohovec" 48.43 17.80
    exit /b 1
)

cd backend
python fetch_ecmwf_official.py "%~1" %2 %3

cd ..
git add backend/ecmwf_forecast_*.json
git commit -m "Add forecast for %~1"
git push origin main

echo.
echo ✓ Hotovo! JSON dostupný na:
echo https://raw.githubusercontent.com/richard-page/pocasie/main/backend/ecmwf_forecast_%~1.json
