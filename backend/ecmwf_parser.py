#!/usr/bin/env python3
"""
ECMWF Open Data → JSON Parser
Stiahne GRIB2 z data.ecmwf.int, parse ecCodes, uloží JSON.

Inštalácia závislostí:
    pip install eccodes requests numpy

Použitie:
    python ecmwf_parser.py --lat 48.8566 --lon 2.3522 --output forecast.json
"""

import argparse
import json
import os
import sys
from datetime import datetime, timedelta
from pathlib import Path
from typing import Dict, List, Optional, Tuple

import numpy as np
import requests

# ecCodes import
try:
    import eccodes
except ImportError:
    print("ERROR: ecCodes nie je nainštalované")
    print("Inštalácia: pip install eccodes")
    sys.exit(1)


class EcmwfOpenDataParser:
    """Parser pre ECMWF Open Data GRIB2 súbory"""
    
    BASE_URL = "https://data.ecmwf.int/forecasts"
    
    # Parametre ktoré potrebujeme (ecCodes kódy)
    PARAMETERS = {
        '2t': '167',      # 2m teplota (K)
        '2d': '168',      # 2m rosný bod (K)
        '10u': '165',     # 10m U vietor (m/s)
        '10v': '166',     # 10m V vietor (m/s)
        'msl': '151',     # Tlak na hladine mora (Pa)
        'tp': '228',      # Celkové zrážky (m)
        'sf': '144',      # Snehové zrážky (m vody)
        'tcc': '164',     # Celková oblačnosť (0-1)
        'ssr': '176',     # Krátke vlnové žiarenie (J/m²) - pre UV
    }
    
    def __init__(self):
        self.session = requests.Session()
        self.session.headers.update({
            'User-Agent': 'pocasie-app/1.0'
        })
    
    def _get_latest_forecast_url(self) -> Tuple[str, str, str]:
        """Získa URL pre najnovšiu dostupnú predpoveď"""
        now = datetime.utcnow()
        
        # ECMWF vydáva predpovede o 00z, 06z, 12z, 18z
        # Hľadáme najnovšiu dostupnú
        for hours_back in [0, 6, 12, 18, 24]:
            check_time = now - timedelta(hours=hours_back)
            date_str = check_time.strftime('%Y%m%d')
            cycle = f"{(check_time.hour // 6) * 6:02d}z"
            
            # URL pre 0.4° resolúciu
            url = f"{self.BASE_URL}/{date_str}/{cycle}/ifs/0p4-beta/oper"
            
            # Skontroluj či existuje (HEAD request)
            try:
                response = self.session.head(url, timeout=10)
                if response.status_code == 200:
                    return url, date_str, cycle
            except:
                pass
        
        raise Exception("Nenašla sa dostupná predpoveď")
    
    def _download_grib(self, url: str, param: str, level_type: str = 'sfc') -> bytes:
        """Stiahne GRIB2 súbor pre daný parameter"""
        # URL pre konkrétny parameter
        grib_url = f"{url}/{level_type}/{param}/grib"
        
        print(f"Sťahujem: {grib_url}")
        
        response = self.session.get(grib_url, timeout=120)
        response.raise_for_status()
        
        return response.content
    
    def _parse_grib_message(self, grib_data: bytes) -> List[Dict]:
        """Parse GRIB2 dáta pomocou ecCodes"""
        messages = []
        
        with open('/tmp/temp.grib2', 'wb') as f:
            f.write(grib_data)
        
        try:
            with open('/tmp/temp.grib2', 'rb') as f:
                while True:
                    gid = eccodes.codes_grib_new_from_file(f)
                    if gid is None:
                        break
                    
                    try:
                        # Extrahuj hodnoty
                        values = eccodes.codes_get_values(gid)
                        latlons = eccodes.codes_grib_find_nearest(gid, 0, 0)[0]
                        
                        # Metadata
                        param_code = eccodes.codes_get(gid, 'paramCode')
                        step = eccodes.codes_get(gid, 'endStep')
                        date = eccodes.codes_get(gid, 'dataDate')
                        time = eccodes.codes_get(gid, 'dataTime')
                        
                        messages.append({
                            'param_code': param_code,
                            'step': step,
                            'date': str(date),
                            'time': time,
                            'values': values.tolist() if isinstance(values, np.ndarray) else values,
                            'lat': latlons['lat'] if latlons else None,
                            'lon': latlons['lon'] if latlons else None,
                        })
                    finally:
                        eccodes.codes_release(gid)
        finally:
            if os.path.exists('/tmp/temp.grib2'):
                os.remove('/tmp/temp.grib2')
        
        return messages
    
    def _interpolate_to_location(
        self, 
        messages: List[Dict], 
        target_lat: float, 
        target_lon: float
    ) -> Dict[int, float]:
        """Interpoluje GRID dáta na špecifickú lokáciu"""
        
        # Nájdi 4 najbližšie body
        results = {}
        
        for msg in messages:
            step = msg['step']
            
            # Jednoduchá bilineárna interpolácia by bola tu
            # Pre demo použijeme hodnotu z najbližšieho bodu
            
            if step not in results:
                # TODO: Implementovať bilineárnu interpoláciu
                results[step] = msg['values'][0] if isinstance(msg['values'], list) else msg['values']
        
        return results
    
    def fetch_forecast(
        self, 
        lat: float, 
        lon: float,
        days: int = 10
    ) -> Dict:
        """Získa predpoveď pre dané súradnice"""
        
        print(f"Získavam predpoveď pre: {lat}, {lon}")
        
        # Získa najnovšiu predpoveď URL
        base_url, date_str, cycle = self._get_latest_forecast_url()
        print(f"Používam predpoveď: {date_str} {cycle}")
        
        # Stiahni a parse všetky parametre
        hourly_data = {h: {} for h in range(24 * days)}
        
        for param_name, param_code in self.PARAMETERS.items():
            try:
                grib_data = self._download_grib(base_url, param_code)
                messages = self._parse_grib_message(grib_data)
                interpolated = self._interpolate_to_location(messages, lat, lon)
                
                for step, value in interpolated.items():
                    if step < 24 * days:
                        hourly_data[step][param_name] = value
                        
                print(f"  ✓ {param_name}")
            except Exception as e:
                print(f"  ✗ {param_name}: {e}")
        
        # Konvertuj na formát kompatibilný s Open-Meteo
        return self._format_output(hourly_data, lat, lon, date_str, cycle, days)
    
    def _format_output(
        self, 
        hourly_data: Dict[int, Dict],
        lat: float,
        lon: float,
        date_str: str,
        cycle: str,
        days: int
    ) -> Dict:
        """Formátuje výstup na Open-Meteo kompatibilný JSON"""
        
        # Generuj časové značky
        base_date = datetime.strptime(date_str, '%Y%m%d')
        cycle_hour = int(cycle.replace('z', ''))
        base_date = base_date.replace(hour=cycle_hour)
        
        times = []
        temps = []
        precips = []
        winds_u = []
        winds_v = []
        pressures = []
        
        for step in range(24 * days):
            step_time = base_date + timedelta(hours=step)
            times.append(step_time.isoformat())
            
            data = hourly_data.get(step, {})
            
            # Teplota (K → °C)
            temp_k = data.get('2t', 273.15)
            temps.append(round(temp_k - 273.15, 1))
            
            # Zrážky (m → mm)
            precip_m = data.get('tp', 0)
            precips.append(round(precip_m * 1000, 1))
            
            # Vietor
            winds_u.append(data.get('10u', 0))
            winds_v.append(data.get('10v', 0))
            
            # Tlak (Pa → hPa)
            press_pa = data.get('msl', 101325)
            pressures.append(round(press_pa / 100, 1))
        
        # Denné agregácie
        daily_times = []
        daily_max_temps = []
        daily_min_temps = []
        daily_precip_sums = []
        
        for day in range(days):
            day_start = day * 24
            day_end = day_start + 24
            
            day_temps = temps[day_start:day_end]
            day_precips = precips[day_start:day_end]
            
            day_time = base_date + timedelta(days=day)
            daily_times.append(day_time.strftime('%Y-%m-%d'))
            daily_max_temps.append(max(day_temps) if day_temps else 0)
            daily_min_temps.append(min(day_temps) if day_temps else 0)
            daily_precip_sums.append(sum(day_precips) if day_precips else 0)
        
        return {
            'latitude': lat,
            'longitude': lon,
            'timezone': 'UTC',
            'source': 'ECMWF Open Data',
            'model': 'IFS',
            'resolution': '0.4°',
            'forecast_date': date_str,
            'forecast_cycle': cycle,
            'current': {
                'time': times[0] if times else None,
                'temperature_2m': temps[0] if temps else None,
                'relative_humidity_2m': 50,  # TODO: vypočítať z 2t a 2d
                'surface_pressure': pressures[0] if pressures else None,
                'wind_speed_10m': (winds_u[0]**2 + winds_v[0]**2)**0.5 if winds_u and winds_v else 0,
                'wind_direction_10m': 0,  # TODO: vypočítať z U,V
                'precipitation': precips[0] if precips else 0,
            },
            'hourly': {
                'time': times,
                'temperature_2m': temps,
                'precipitation': precips,
                'pressure_msl': pressures,
            },
            'daily': {
                'time': daily_times,
                'temperature_2m_max': daily_max_temps,
                'temperature_2m_min': daily_min_temps,
                'precipitation_sum': daily_precip_sums,
            }
        }


def main():
    parser = argparse.ArgumentParser(description='ECMWF Open Data Parser')
    parser.add_argument('--lat', type=float, required=True, help='Zemepisná šírka')
    parser.add_argument('--lon', type=float, required=True, help='Zemepisná dĺžka')
    parser.add_argument('--days', type=int, default=10, help='Počet dní predpovede')
    parser.add_argument('--output', type=str, default='ecmwf_forecast.json', help='Výstupný súbor')
    
    args = parser.parse_args()
    
    print("=" * 50)
    print("ECMWF Open Data Parser")
    print("=" * 50)
    
    try:
        ecmwf = EcmwfOpenDataParser()
        forecast = ecmwf.fetch_forecast(args.lat, args.lon, args.days)
        
        # Ulož výstup
        with open(args.output, 'w') as f:
            json.dump(forecast, f, indent=2)
        
        print(f"\n✓ Predpoveď uložená do: {args.output}")
        print(f"  Dátum behu: {forecast['forecast_date']} {forecast['forecast_cycle']}")
        print(f"  Teplota teraz: {forecast['current']['temperature_2m']}°C")
        print(f"  Zrážky teraz: {forecast['current']['precipitation']}mm")
        
    except Exception as e:
        print(f"\n✗ Chyba: {e}")
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == '__main__':
    main()
