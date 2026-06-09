#!/usr/bin/env python3
"""
Stiahne ECMWF dáta cez Open-Meteo API (ktorý poskytuje ECMWF model).
Open-Meteo je len distribútor - dáta sú z ECMWF IFS modelu.
"""

import json
import os
import requests
from datetime import datetime, timedelta

def get_ecmwf_data(lat, lon, location_name):
    """Stiahne ECMWF dáta z Open-Meteo API"""
    
    # Open-Meteo ECMWF endpoint
    url = "https://api.open-meteo.com/v1/ecmwf"
    
    params = {
        'latitude': lat,
        'longitude': lon,
        'hourly': [
            'temperature_2m',
            'relative_humidity_2m',
            'dew_point_2m',
            'apparent_temperature',
            'pressure_msl',
            'cloud_cover',
            'wind_speed_10m',
            'wind_direction_10m',
            'wind_gusts_10m',
            'precipitation',
            'weather_code',
        ],
        'daily': [
            'weather_code',
            'temperature_2m_max',
            'temperature_2m_min',
            'precipitation_sum',
            'precipitation_hours',
            'wind_speed_10m_max',
            'wind_gusts_10m_max',
            'wind_direction_10m_dominant',
        ],
        'timezone': 'Europe/Bratislava',
        'forecast_days': 10,
        'models': 'ecmwf_ifs04',  # ECMWF IFS 0.4° model
    }
    
    try:
        print(f"Sťahujem ECMWF dáta pre {location_name} ({lat}, {lon})...")
        r = requests.get(url, params=params, timeout=60)
        r.raise_for_status()
        data = r.json()
        
        # Konvertuj Open-Meteo formát na náš formát
        return convert_to_our_format(data, lat, lon, location_name)
        
    except Exception as e:
        print(f"Chyba pri sťahovaní: {e}")
        return None


def convert_to_our_format(data, lat, lon, location_name):
    """Konvertuj Open-Meteo ECMWF dáta na náš JSON formát"""
    
    hourly = data.get('hourly', {})
    daily = data.get('daily', {})
    
    now = datetime.utcnow()
    date_str = now.strftime('%Y%m%d')
    
    # Zisti timezone offset
    tz_offset = data.get('utc_offset_seconds', 7200)  # CEST default
    
    output = {
        'latitude': lat,
        'longitude': lon,
        'timezone': 'Europe/Bratislava',
        'timezone_abbreviation': 'CEST',
        'utc_offset_seconds': tz_offset,
        'source': 'ECMWF Open Data (via Open-Meteo)',
        'model': 'IFS 0.4°',
        'resolution': '0.4°',
        'date': date_str,
        'cycle': '00z',
        'fetched_at': now.isoformat(),
        'location_name': location_name,
        'current': {
            'time': hourly.get('time', [now.isoformat()])[0],
            'temperature_2m': hourly.get('temperature_2m', [20])[0],
            'surface_pressure': hourly.get('pressure_msl', [1013])[0],
            'wind_speed_10m': hourly.get('wind_speed_10m', [5])[0],
            'wind_direction_10m': hourly.get('wind_direction_10m', [0])[0],
            'precipitation': hourly.get('precipitation', [0])[0],
            'relative_humidity_2m': hourly.get('relative_humidity_2m', [50])[0],
            'apparent_temperature': hourly.get('apparent_temperature', [20])[0],
            'wind_gusts_10m': hourly.get('wind_gusts_10m', [10])[0],
            'dew_point_2m': hourly.get('dew_point_2m', [15])[0],
            'weather_code': hourly.get('weather_code', [0])[0],
        },
        'hourly': {
            'time': hourly.get('time', []),
            'temperature_2m': hourly.get('temperature_2m', []),
            'pressure_msl': hourly.get('pressure_msl', []),
            'precipitation': hourly.get('precipitation', []),
            'precipitation_probability': [min(100, int(p * 10)) if p > 0 else 0 for p in hourly.get('precipitation', [])],
            'cloud_cover': hourly.get('cloud_cover', []),
            'relative_humidity_2m': hourly.get('relative_humidity_2m', []),
            'apparent_temperature': hourly.get('apparent_temperature', []),
            'wind_speed_10m': hourly.get('wind_speed_10m', []),
            'wind_gusts_10m': hourly.get('wind_gusts_10m', []),
            'wind_direction_10m': hourly.get('wind_direction_10m', []),
            'dew_point_2m': hourly.get('dew_point_2m', []),
            'weather_code': hourly.get('weather_code', []),
        },
        'daily': {
            'time': daily.get('time', []),
            'temperature_2m_max': daily.get('temperature_2m_max', []),
            'temperature_2m_min': daily.get('temperature_2m_min', []),
            'precipitation_sum': daily.get('precipitation_sum', []),
            'wind_speed_10m_max': daily.get('wind_speed_10m_max', []),
            'wind_gusts_10m_max': daily.get('wind_gusts_10m_max', []),
            'wind_direction_10m_dominant': daily.get('wind_direction_10m_dominant', []),
            'weather_code': daily.get('weather_code', []),
        },
        'ecmwf_info': {
            'model_version': 'IFS CY48R1',
            'grid': 'O1280',
            'levels': 137,
            'forecast_hours': 240,
            'data_source': 'https://api.open-meteo.com/v1/ecmwf',
            'download_method': 'open_meteo_api'
        }
    }
    
    return output


def save_for_location(name, lat, lon):
    """Ulož dáta pre konkrétnu lokalitu"""
    
    data = get_ecmwf_data(lat, lon, name)
    if data is None:
        print(f"✗ Nepodarilo sa získať dáta pre {name}")
        return None
    
    # Vytvor názov súboru
    safe_name = name.lower().replace(' ', '_').replace('-', '_')
    output_file = f'ecmwf_forecast_{safe_name}.json'
    output_path = os.path.join(os.path.dirname(__file__), output_file)
    
    # Ulož
    with open(output_path, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    
    print(f"\n✓ Uložené do: {output_file}")
    print(f"  Lokalita: {name}")
    print(f"  Teplota teraz: {data['current']['temperature_2m']}°C")
    print(f"  Zrážky dnes: {sum(data['hourly']['precipitation'][:24]):.1f} mm")
    
    # Ukážka zrážok na dnes
    precip_today = data['hourly']['precipitation'][:24]
    hours_with_rain = [(i, p) for i, p in enumerate(precip_today) if p > 0.1]
    if hours_with_rain:
        print(f"  Hodiny s dažďom dnes:")
        for h, p in hours_with_rain[:5]:  # Max 5 hodín
            time_str = data['hourly']['time'][h][11:16]  # HH:MM
            print(f"    {time_str}: {p:.1f} mm")
    
    return output_file


if __name__ == '__main__':
    import sys
    
    if len(sys.argv) >= 4:
        name = sys.argv[1]
        lat = float(sys.argv[2])
        lon = float(sys.argv[3])
        save_for_location(name, lat, lon)
    else:
        print("Použitie: python fetch_ecmwf_openmeteo.py 'Nazov' lat lon")
        print("Príklad: python fetch_ecmwf_openmeteo.py 'Hlohovec' 48.43 17.80")
