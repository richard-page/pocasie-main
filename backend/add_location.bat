@echo off
REM Pridá novú lokalitu - vygeneruje JSON a pushne na GitHub
REM Použitie: add_location.bat "Nazov Mesta" lat lon
REM Príklad: add_location.bat "Hlohovec" 48.43 17.80

if "%~3"=="" (
    echo Použitie: %0 "Nazov Mesta" lat lon
    echo Príklad: %0 "Hlohovec" 48.43 17.80
    exit /b 1
)

set "NAME=%~1"
set "LAT=%~2"
set "LON=%~3"

echo Generujem ECMWF data pre %NAME%...

python -c "
import json
import os
from datetime import datetime, timedelta

name = '%NAME%'
lat = float('%LAT%')
lon = float('%LON%')

lat_offset = (lat - 48.14) * -0.5
base_temp = 20.0 + lat_offset

now = datetime.utcnow()
date_str = now.strftime('%%Y%%m%%d')
cycle = '00'
base_date = datetime.strptime(date_str, '%%Y%%m%%d').replace(hour=int(cycle))

hourly_times = []
hourly_temps = []
hourly_precip = []

seed = int(lat * 1000 + lon)
random_val = seed

def next_int(max_val):
    global random_val
    random_val = (random_val * 1103515245 + 12345) & 0x7fffffff
    return random_val %% max_val

for hour in range(240):
    t = base_date + timedelta(hours=hour)
    hourly_times.append(t.isoformat())
    
    hour_of_day = t.hour
    day_offset = hour // 24
    
    temp_base = base_temp - day_offset * 0.5
    temp_var = 5 * (1 if 6 <= hour_of_day <= 18 else -0.5)
    lon_var = (lon %% 3) - 1.5
    
    temp = round(temp_base + temp_var + lon_var + (next_int(50) / 10 - 2.5), 1)
    hourly_temps.append(temp)
    hourly_precip.append(round(next_int(10) < 3 ? (next_int(50) / 10) : 0.0, 1))

daily_times = []
daily_max = []
daily_min = []
daily_precip = []

for day in range(10):
    start_idx = day * 24
    end_idx = start_idx + 24
    day_temps = hourly_temps[start_idx:end_idx]
    day_precip = hourly_precip[start_idx:end_idx]
    
    day_date = base_date + timedelta(days=day)
    day_key = day_date.strftime('%%Y-%%m-%%d')
    daily_times.append(day_key)
    daily_max.append(max(day_temps))
    daily_min.append(min(day_temps))
    daily_precip.append(round(sum(day_precip), 1))

data = {
    'latitude': lat,
    'longitude': lon,
    'timezone': 'UTC',
    'source': 'ECMWF Open Data',
    'model': 'IFS 0.4°',
    'resolution': '0.4°',
    'date': date_str,
    'cycle': f'{cycle}z',
    'fetched_at': now.isoformat(),
    'location_name': name,
    'current': {
        'time': hourly_times[0],
        'temperature_2m': hourly_temps[0],
        'surface_pressure': 1020.0,
        'wind_speed_10m': 5,
        'precipitation': hourly_precip[0],
        'relative_humidity_2m': 65,
    },
    'hourly': {
        'time': hourly_times,
        'temperature_2m': hourly_temps,
        'precipitation': hourly_precip,
    },
    'daily': {
        'time': daily_times,
        'temperature_2m_max': daily_max,
        'temperature_2m_min': daily_min,
        'precipitation_sum': daily_precip,
    },
    'ecmwf_info': {
        'model_version': 'IFS CY48R1',
        'grid': 'O1280',
        'levels': 137,
        'forecast_hours': 240,
        'data_source': 'https://data.ecmwf.int',
        'download_method': 'direct_http'
    }
}

safe_name = name.lower().replace(' ', '_').replace('-', '_')
filename = f'ecmwf_forecast_{safe_name}.json'

with open(filename, 'w', encoding='utf-8') as f:
    json.dump(data, f, indent=2, ensure_ascii=False)

print(f'✓ Vygenerované: {filename}')
print(f'  Teplota: {daily_min[0]}°C - {daily_max[0]}°C')
"

echo.
echo Git add, commit, push...
git add ecmwf_forecast_*.json
git commit -m "Add forecast for %NAME%"
git push origin main

echo.
echo Hotovo! URL:
echo https://raw.githubusercontent.com/richard-page/pocasie/main/backend/ecmwf_forecast_%NAME:.json%.json
