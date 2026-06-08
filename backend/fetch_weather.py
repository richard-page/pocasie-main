#!/usr/bin/env python3
"""
Stiahne predpoveď z Open-Meteo API (zadarmo, bez API kľúča).
Open-Meteo používa ECMWF IFS model + ďalšie modely.
"""

import json
import os
import requests
from datetime import datetime

OUTPUT_FILE = os.path.join(os.path.dirname(__file__), 'ecmwf_forecast.json')
LOCATIONS_FILE = os.path.join(os.path.dirname(__file__), 'locations.json')

def fetch_location(name, lat, lon):
    """Stiahne predpoveď pre lokáciu"""
    print(f"Sťahujem: {name}...")
    
    # Open-Meteo API - ECMWF IFS model
    url = "https://api.open-meteo.com/v1/forecast"
    params = {
        'latitude': lat,
        'longitude': lon,
        'hourly': [
            'temperature_2m',
            'relative_humidity_2m',
            'apparent_temperature',
            'precipitation',
            'rain',
            'snowfall',
            'cloud_cover',
            'pressure_msl',
            'surface_pressure',
            'wind_speed_10m',
            'wind_direction_10m',
            'wind_gusts_10m',
            'uv_index',
        ],
        'daily': [
            'weather_code',
            'temperature_2m_max',
            'temperature_2m_min',
            'apparent_temperature_max',
            'apparent_temperature_min',
            'precipitation_sum',
            'precipitation_probability_max',
            'snowfall_sum',
            'wind_speed_10m_max',
            'wind_gusts_10m_max',
            'wind_direction_10m_dominant',
            'uv_index_max',
        ],
        'timezone': 'Europe/Bratislava',
        'forecast_days': 10,
        'models': 'ecmwf_ifs04',  # ECMWF IFS 0.4° model
    }
    
    response = requests.get(url, params=params, timeout=60)
    response.raise_for_status()
    
    return response.json()

def main():
    print("=" * 50)
    print("Open-Meteo ECMWF Fetcher")
    print("=" * 50)
    
    # Načítaj lokality
    with open(LOCATIONS_FILE) as f:
        locations = json.load(f)['locations']
    
    # Hlavné mesto (prvá lokalita) ako default
    main_loc = locations[0]
    print(f"\nHlavná lokalita: {main_loc['name']}\n")
    
    data = fetch_location(main_loc['name'], main_loc['lat'], main_loc['lon'])
    
    # Pridaj metadata
    data['source'] = 'Open-Meteo'
    data['model'] = 'ECMWF IFS 0.4°'
    data['fetched_at'] = datetime.utcnow().isoformat()
    data['ecmwf_info'] = {
        'model_version': 'IFS CY48R1',
        'grid': 'O1280',
        'resolution': '0.4°',
        'levels': 137,
        'forecast_hours': 240,
        'data_source': 'https://open-meteo.com'
    }
    
    # Ulož
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(data, f, indent=2)
    
    print(f"\n✓ Uložené do: {OUTPUT_FILE}")
    print(f"  Teplota teraz: {data['current']['temperature_2m']}°C")
    print(f"  Dní predpovede: {len(data['daily']['time'])}")
    
    return data

if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f"\n✗ Chyba: {e}")
        import traceback
        traceback.print_exc()
        exit(1)
