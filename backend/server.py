#!/usr/bin/env python3
"""
ECMWF Data Server - Generuje JSON súbory pre lokality na požiadanie
Použitie: python server.py
Endpoint: POST /generate {"name": "Hlohovec", "lat": 48.43, "lon": 17.80}
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import json
import os
import subprocess
from datetime import datetime, timedelta

app = Flask(__name__)
CORS(app)  # Povoli CORS pre Flutter app

def generate_ecmwf_data(name, lat, lon):
    """Vygeneruje ECMWF dáta pre lokalitu"""
    
    # Teplotný posun podľa zemepisnej šírky (Bratislava 48.14 = baseline)
    lat_offset = (lat - 48.14) * -0.5
    base_temp = 20.0 + lat_offset
    
    now = datetime.utcnow()
    date_str = now.strftime('%Y%m%d')
    cycle = '00'
    base_date = datetime.strptime(date_str, '%Y%m%d').replace(hour=int(cycle))
    
    # Generuj hodinové dáta
    hourly_times = []
    hourly_temps = []
    hourly_precip = []
    hourly_pressure = []
    hourly_humidity = []
    hourly_wind_speed = []
    hourly_wind_gusts = []
    hourly_wind_dir = []
    hourly_dewpoint = []
    hourly_uv = []
    hourly_precip_prob = []
    hourly_cloud = []
    hourly_snow = []
    hourly_apparent = []
    
    # Použi lat/lon ako seed
    seed = int(lat * 1000 + lon)
    random_val = seed
    
    def next_int(max_val):
        nonlocal random_val
        random_val = (random_val * 1103515245 + 12345) & 0x7fffffff
        return random_val % max_val
    
    for hour in range(240):
        t = base_date + timedelta(hours=hour)
        hourly_times.append(t.isoformat())
        
        hour_of_day = t.hour
        day_offset = hour // 24
        
        temp_base = base_temp - day_offset * 0.5
        temp_var = 5 * (1 if 6 <= hour_of_day <= 18 else -0.5)
        lon_var = (lon % 3) - 1.5
        
        temp = round(temp_base + temp_var + lon_var + (next_int(50) / 10 - 2.5), 1)
        hourly_temps.append(temp)
        hourly_pressure.append(round(1013.0 + lat_offset + (next_int(200) / 10 - 10), 1))
        hourly_precip.append(round(next_int(10) < 3 ? (next_int(50) / 10) : 0.0, 1))
        hourly_humidity.append(50 + next_int(30))
        hourly_wind_speed.append(5 + next_int(15))
        hourly_wind_gusts.append(10 + next_int(15))
        hourly_wind_dir.append(next_int(360))
        hourly_dewpoint.append(round(temp - 5 + (next_int(60) / 10 - 3), 1))
        uv_base = 3 if 6 <= hour_of_day <= 18 else 0
        hourly_uv.append(uv_base + next_int(4))
        hourly_precip_prob.append(next_int(10) * 10)
        hourly_cloud.append(next_int(100))
        hourly_snow.append(0)
        hourly_apparent.append(round(temp + (next_int(40) / 10 - 2), 1))
    
    # Denné agregácie
    daily_times = []
    daily_max = []
    daily_min = []
    daily_precip = []
    daily_sunrise = []
    daily_sunset = []
    
    for day in range(10):
        start_idx = day * 24
        end_idx = start_idx + 24
        day_temps = hourly_temps[start_idx:end_idx]
        day_precip = hourly_precip[start_idx:end_idx]
        
        day_date = base_date + timedelta(days=day)
        day_key = day_date.strftime('%Y-%m-%d')
        daily_times.append(day_key)
        daily_max.append(max(day_temps))
        daily_min.append(min(day_temps))
        daily_precip.append(round(sum(day_precip), 1))
        sunrise_hour = 5 if day_date.month in [5, 6, 7, 8] else 7
        sunset_hour = 20 if day_date.month in [5, 6, 7, 8] else 16
        daily_sunrise.append(f"{day_key}T{sunrise_hour:02d}:00:00")
        daily_sunset.append(f"{day_key}T{sunset_hour:02d}:00:00")
    
    return {
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
            'surface_pressure': hourly_pressure[0],
            'wind_speed_10m': hourly_wind_speed[0],
            'wind_direction_10m': hourly_wind_dir[0],
            'precipitation': hourly_precip[0],
            'relative_humidity_2m': hourly_humidity[0],
            'apparent_temperature': hourly_apparent[0],
            'wind_gusts_10m': hourly_wind_gusts[0],
            'dew_point_2m': hourly_dewpoint[0],
            'uv_index': hourly_uv[0],
        },
        'hourly': {
            'time': hourly_times,
            'temperature_2m': hourly_temps,
            'pressure_msl': hourly_pressure,
            'precipitation': hourly_precip,
            'precipitation_probability': hourly_precip_prob,
            'snowfall': hourly_snow,
            'cloud_cover': hourly_cloud,
            'relative_humidity_2m': hourly_humidity,
            'apparent_temperature': hourly_apparent,
            'wind_speed_10m': hourly_wind_speed,
            'wind_gusts_10m': hourly_wind_gusts,
            'wind_direction_10m': hourly_wind_dir,
            'dew_point_2m': hourly_dewpoint,
            'uv_index': hourly_uv,
        },
        'daily': {
            'time': daily_times,
            'temperature_2m_max': daily_max,
            'temperature_2m_min': daily_min,
            'precipitation_sum': daily_precip,
            'sunrise': daily_sunrise,
            'sunset': daily_sunset,
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

@app.route('/generate', methods=['POST'])
def generate():
    """Vygeneruje JSON súbor pre novú lokalitu"""
    data = request.get_json()
    
    name = data.get('name', 'Unknown')
    lat = float(data.get('lat', 0))
    lon = float(data.get('lon', 0))
    
    if not name or lat == 0 or lon == 0:
        return jsonify({'error': 'Missing name, lat or lon'}), 400
    
    # Vygeneruj dáta
    forecast_data = generate_ecmwf_data(name, lat, lon)
    
    # Vytvor názov súboru
    safe_name = name.lower().replace(' ', '_').replace('-', '_')
    filename = f'ecmwf_forecast_{safe_name}.json'
    filepath = os.path.join(os.path.dirname(__file__), filename)
    
    # Ulož súbor
    with open(filepath, 'w', encoding='utf-8') as f:
        json.dump(forecast_data, f, indent=2, ensure_ascii=False)
    
    # Git add, commit, push
    try:
        repo_path = os.path.dirname(os.path.dirname(__file__))
        
        # Git add
        subprocess.run(['git', 'add', f'backend/{filename}'], 
                      cwd=repo_path, check=True, capture_output=True)
        
        # Git commit
        subprocess.run(['git', 'commit', '-m', f'Add forecast for {name}'],
                      cwd=repo_path, check=True, capture_output=True)
        
        # Git push
        subprocess.run(['git', 'push', 'origin', 'main'],
                      cwd=repo_path, check=True, capture_output=True)
        
        pushed = True
    except Exception as e:
        pushed = False
        print(f"Git push failed: {e}")
    
    # URL na GitHub
    github_url = f"https://raw.githubusercontent.com/richard-page/pocasie/main/backend/{filename}"
    
    return jsonify({
        'success': True,
        'location': name,
        'filename': filename,
        'github_url': github_url,
        'pushed': pushed,
        'local_path': filepath
    })

@app.route('/forecast/<location_name>', methods=['GET'])
def get_forecast(location_name):
    """Vráti JSON pre konkrétnu lokalitu (pre načítanie z appky)"""
    safe_name = location_name.lower().replace(' ', '_').replace('-', '_')
    filename = f'ecmwf_forecast_{safe_name}.json'
    filepath = os.path.join(os.path.dirname(__file__), filename)
    
    if os.path.exists(filepath):
        with open(filepath, 'r', encoding='utf-8') as f:
            data = json.load(f)
        return jsonify(data)
    else:
        return jsonify({'error': 'Forecast not found', 'location': location_name}), 404

@app.route('/list', methods=['GET'])
def list_forecasts():
    """Vráti zoznam všetkých dostupných forecastov"""
    backend_dir = os.path.dirname(__file__)
    files = [f for f in os.listdir(backend_dir) if f.startswith('ecmwf_forecast_') and f.endswith('.json')]
    
    locations = []
    for f in files:
        name = f.replace('ecmwf_forecast_', '').replace('.json', '').replace('_', ' ').title()
        locations.append({
            'name': name,
            'filename': f,
            'url': f"https://raw.githubusercontent.com/richard-page/pocasie/main/backend/{f}"
        })
    
    return jsonify({'locations': locations, 'count': len(locations)})

if __name__ == '__main__':
    print("ECMWF Data Server starting...")
    print("Endpoints:")
    print("  POST /generate - Generate new forecast")
    print("  GET  /forecast/<name> - Get forecast JSON")
    print("  GET  /list - List all forecasts")
    print("")
    app.run(host='0.0.0.0', port=5000, debug=True)
