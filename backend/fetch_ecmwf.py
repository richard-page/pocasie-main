#!/usr/bin/env python3
"""
Jednoduchý script: Stiahne ECMWF Open Data → uloží ako JSON
Spustíš raz za 6 hodín cron jobom alebo ručne.

Výstup: ecmwf_forecast.json (Flutter číta tento súbor)
"""

import json
import os
import subprocess
import sys
from datetime import datetime, timedelta

import requests

# Nastavenie
OUTPUT_FILE = os.path.join(os.path.dirname(__file__), 'ecmwf_forecast.json')
ECMWF_URL = "https://data.ecmwf.int/forecasts"


def get_latest_run():
    """Nájde najnovší dostupný ECMWF beh"""
    now = datetime.utcnow()
    
    # Skontroluj viac dní dozadu - ECMWF má oneskorenie
    for days_back in [0, 1, 2, 3]:
        for cycle in ['00', '06', '12', '18']:
            check_time = now - timedelta(days=days_back)
            date_str = check_time.strftime('%Y%m%d')
            
            # Skús viac formátov URL
            urls_to_try = [
                f"{ECMWF_URL}/{date_str}/{cycle}z/ifs/0p4-beta/oper/",
                f"https://data.ecmwf.int/forecasts/{date_str}/{cycle}z/ifs/0p4/oper/",
            ]
            
            for url in urls_to_try:
                try:
                    r = requests.head(url, timeout=10, allow_redirects=True)
                    if r.status_code == 200:
                        print(f"Nájdené dáta: {date_str} {cycle}z")
                        return date_str, cycle
                except Exception as e:
                    pass
    
    # Fallback - vráť včerajšiu 00z ak nič nefunguje
    yesterday = now - timedelta(days=1)
    return yesterday.strftime('%Y%m%d'), '00'


def download_grib_param(date_str, cycle, param_code, output_path):
    """Stiahne GRIB2 súbor pre parameter"""
    urls_to_try = [
        f"{ECMWF_URL}/{date_str}/{cycle}z/ifs/0p4-beta/oper/sfc/{param_code}/grib",
        f"https://data.ecmwf.int/forecasts/{date_str}/{cycle}z/ifs/0p4/oper/sfc/{param_code}/grib",
    ]
    
    print(f"Sťahujem {param_code}...", end=" ")
    
    for url in urls_to_try:
        try:
            r = requests.get(url, timeout=120)
            if r.status_code == 200:
                with open(output_path, 'wb') as f:
                    f.write(r.content)
                print(f"OK ({len(r.content)} bajtov)")
                return True
        except:
            pass
    
    print("CHYBA - nenašlo sa")
    return False


def parse_grib_with_ecCodes(grib_path):
    """Parsuje GRIB2 pomocou ecCodes grib_dump"""
    try:
        result = subprocess.run(
            ['grib_dump', '-j', grib_path],  # JSON output
            capture_output=True,
            text=True,
            timeout=30
        )
        
        if result.returncode == 0:
            return json.loads(result.stdout)
    except:
        pass
    
    # Fallback: grib_ls
    try:
        result = subprocess.run(
            ['grib_ls', '-p', 'dataDate,dataTime,step,paramCode,value', grib_path],
            capture_output=True,
            text=True,
            timeout=30
        )
        
        lines = result.stdout.strip().split('\n')[2:-1]  # Skip header/footer
        values = []
        
        for line in lines:
            parts = line.split()
            if len(parts) >= 5:
                values.append({
                    'date': parts[0],
                    'time': parts[1],
                    'step': int(parts[2]),
                    'param': parts[3],
                    'value': float(parts[4]) if parts[4] != 'missing' else None
                })
        
        return values
    except Exception as e:
        print(f"Parse chyba: {e}")
        return []


def fetch_forecast():
    """Hlavná funkcia - stiahne všetky parametre"""
    print("=" * 50)
    print("ECMWF Open Data Fetcher")
    print("=" * 50)
    
    # Zisti najnovší beh
    date_str, cycle = get_latest_run()
    print(f"Predpoveď: {date_str} {cycle}z\n")
    
    # Parametre: (kód, názov, jednotka, konverzia)
    params = [
        ('167', '2t', 'K', lambda x: round(x - 273.15, 1)),  # Teplota K→°C
        ('165', '10u', 'm/s', lambda x: round(x, 1)),       # Vietor U
        ('166', '10v', 'm/s', lambda x: round(x, 1)),       # Vietor V
        ('151', 'msl', 'Pa', lambda x: round(x / 100, 1)),  # Tlak Pa→hPa
        ('228', 'tp', 'm', lambda x: round(x * 1000, 1)),   # Zrážky m→mm
        ('144', 'sf', 'm', lambda x: round(x * 1000, 1)),   # Sneh m→mm
        ('164', 'tcc', '0-1', lambda x: round(x * 100, 0)), # Oblačnosť 0-1→%
    ]
    
    all_data = {
        'metadata': {
            'source': 'ECMWF Open Data',
            'model': 'IFS',
            'resolution': '0.4°',
            'date': date_str,
            'cycle': cycle,
            'fetched_at': datetime.utcnow().isoformat(),
        },
        'hourly': {}
    }
    
    tmp_dir = '/tmp/ecmwf_fetch'
    os.makedirs(tmp_dir, exist_ok=True)
    
    for param_code, param_name, unit, converter in params:
        grib_file = f"{tmp_dir}/{param_code}.grib2"
        
        if not download_grib_param(date_str, cycle, param_code, grib_file):
            continue
        
        # Parse GRIB
        parsed = parse_grib_with_ecCodes(grib_file)
        
        for item in parsed:
            if isinstance(item, dict) and 'step' in item:
                step = item['step']
                value = item.get('value')
                
                if value is not None:
                    if step not in all_data['hourly']:
                        all_data['hourly'][step] = {}
                    
                    all_data['hourly'][step][param_name] = converter(value)
        
        # Vymaž dočasný súbor
        os.remove(grib_file)
    
    # Generuj časové značky
    base_date = datetime.strptime(date_str, '%Y%m%d')
    base_date = base_date.replace(hour=int(cycle))
    
    hours = sorted(all_data['hourly'].keys())
    times = []
    temps = []
    wind_u = []
    wind_v = []
    pressures = []
    precips = []
    snows = []
    clouds = []
    
    for step in range(240):  # 10 dní
        step_time = base_date + timedelta(hours=step)
        times.append(step_time.isoformat())
        
        data = all_data['hourly'].get(step, {})
        temps.append(data.get('2t', None))
        wind_u.append(data.get('10u', 0))
        wind_v.append(data.get('10v', 0))
        pressures.append(data.get('msl', None))
        precips.append(data.get('tp', 0))
        snows.append(data.get('sf', 0))
        clouds.append(data.get('tcc', None))
    
    # Denné agregácie
    daily = []
    for day in range(10):
        start = day * 24
        end = start + 24
        
        day_temps = [t for t in temps[start:end] if t is not None]
        day_precips = precips[start:end]
        
        daily.append({
            'date': (base_date + timedelta(days=day)).strftime('%Y-%m-%d'),
            'temp_max': max(day_temps) if day_temps else None,
            'temp_min': min(day_temps) if day_temps else None,
            'precip_sum': sum(day_precips),
        })
    
    # Výsledný formát kompatibilný s Flutter
    output = {
        'latitude': 0.0,  # Globálny grid
        'longitude': 0.0,
        'timezone': 'UTC',
        'source': 'ECMWF Open Data',
        'model': 'IFS',
        'resolution': '0.4°',
        'date': date_str,
        'cycle': f"{cycle}z",
        'current': {
            'time': times[0] if times else None,
            'temperature_2m': temps[0] if temps else None,
            'surface_pressure': pressures[0] if pressures else None,
            'wind_speed_10m': (wind_u[0]**2 + wind_v[0]**2)**0.5 if wind_u and wind_v else 0,
            'precipitation': precips[0] if precips else 0,
        },
        'hourly': {
            'time': times,
            'temperature_2m': temps,
            'pressure_msl': pressures,
            'precipitation': precips,
            'snowfall': snows,
            'cloud_cover': clouds,
        },
        'daily': {
            'time': [d['date'] for d in daily],
            'temperature_2m_max': [d['temp_max'] for d in daily],
            'temperature_2m_min': [d['temp_min'] for d in daily],
            'precipitation_sum': [d['precip_sum'] for d in daily],
        }
    }
    
    # Ulož JSON
    with open(OUTPUT_FILE, 'w') as f:
        json.dump(output, f, indent=2)
    
    print(f"\n✓ Uložené do: {OUTPUT_FILE}")
    print(f"  Hodín: {len(times)}")
    print(f"  Teplota teraz: {temps[0]}°C")
    
    return output


if __name__ == '__main__':
    try:
        fetch_forecast()
    except Exception as e:
        print(f"\n✗ Chyba: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)
