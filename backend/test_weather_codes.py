#!/usr/bin/env python3
"""Test čo sa generuje pre weather codes"""

import json
from datetime import datetime, timedelta

def test_weather_codes():
    # Simuluj 24 hodín
    now = datetime.utcnow()
    base_date = now.replace(hour=0, minute=0, second=0, microsecond=0)
    
    # Fake data
    temps = [20.0] * 24
    precip = [0.0] * 24  # Bez zrážok
    
    hourly_weather_code = []
    hourly_cloud_cover = []
    
    for i, p in enumerate(precip):
        if p > 0.5:
            code = 61
            cloud = 85
        else:
            # Bez zrážok
            day_cycle = (i // 24) % 5
            if day_cycle == 0:
                code = 0  # Jasno
                cloud = 10
            elif day_cycle == 1:
                code = 1  # Prevažne jasno
                cloud = 25
            elif day_cycle == 2:
                code = 2  # Polooblačno
                cloud = 50
            else:
                code = 3  # Zamračené
                cloud = 75
        
        hourly_weather_code.append(code)
        hourly_cloud_cover.append(cloud)
    
    print("HODINA | WEATHER_CODE | CLOUD_COVER | VÝZNAM")
    print("-" * 50)
    codes_map = {0: "Jasno ☀️", 1: "Prevažne jasno 🌤️", 2: "Polooblačno ⛅", 3: "Zamračené ☁️", 61: "Dážď 🌧️"}
    for i in range(min(24, len(hourly_weather_code))):
        code = hourly_weather_code[i]
        print(f"  {i:02d}   |      {code}       |     {hourly_cloud_cover[i]:2d}%    | {codes_map.get(code, '?')}")
    
    print(f"\nCURRENT (hour 0): weather_code={hourly_weather_code[0]} = {codes_map.get(hourly_weather_code[0], '?')}")
    
    # Ulož sample
    sample = {
        'current': {
            'weather_code': hourly_weather_code[0],
            'cloud_cover': hourly_cloud_cover[0],
        },
        'hourly': {
            'weather_code': hourly_weather_code[:6],
        }
    }
    with open('test_output.json', 'w') as f:
        json.dump(sample, f, indent=2)
    print("\nUložené do test_output.json")

if __name__ == '__main__':
    test_weather_codes()
