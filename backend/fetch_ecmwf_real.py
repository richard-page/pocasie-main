#!/usr/bin/env python3
"""
Stiahne REÁLNE ECMWF Open Data z data.ecmwf.int pomocou ecmwf-opendata knižnice
Parsuje GRIB súbory a generuje JSON pre lokality
"""

import json
import math
import os
import tempfile
from datetime import datetime, timedelta

# Automatický grid pre Slovensko (0.4° rozlíšenie = ~44km)
# Pokrýva celé územie SR s automatickou generáciou bodov
# ECMWF Open Data oper/fc: natívne kroky 0–120 h po 3 h (1h GRIB neexistuje).
FORECAST_STEPS_3H = list(range(0, 121, 3))


def _hourly_precip_from_3h_step_deltas(cumulative_mm):
    """Kumulatívne tp v krokoch 0,3,6,… → mm len v hodine kroku (bez falošného rozprestierania)."""
    if not cumulative_mm:
        return []
    cum = [max(0.0, float(v)) for v in cumulative_mm]
    for i in range(1, len(cum)):
        cum[i] = max(cum[i], cum[i - 1])

    n = min(len(cum), len(FORECAST_STEPS_3H))
    max_h = FORECAST_STEPS_3H[n - 1] if n else 0
    precip_1h = [0.0] * (max_h + 1)
    prev = 0.0
    for i in range(n):
        step_h = FORECAST_STEPS_3H[i]
        delta = max(0.0, cum[i] - prev)
        prev = cum[i]
        if step_h < len(precip_1h):
            precip_1h[step_h] = round(delta, 2)
    return precip_1h


def _hourly_precip_from_cumulative_mm(cumulative_mm):
    """Legacy — ponechané pre testy; produkcia používa [_hourly_precip_from_3h_step_deltas]."""
    from scipy.interpolate import interp1d

    if not cumulative_mm:
        return []
    n = len(cumulative_mm)
    hours_3h = [i * 3 for i in range(n)]
    max_h = hours_3h[-1]
    hours_1h = list(range(max_h + 1))

    # Kumulatíva musí byť nerastúca množina
    cum = [max(0.0, float(v)) for v in cumulative_mm]
    for i in range(1, len(cum)):
        cum[i] = max(cum[i], cum[i - 1])

    if n >= 2:
        interp = interp1d(hours_3h, cum, kind='linear', fill_value='extrapolate')
        cum_1h = [max(0.0, float(interp(h))) for h in hours_1h]
    else:
        cum_1h = [cum[0]] * len(hours_1h)

    for i in range(1, len(cum_1h)):
        cum_1h[i] = max(cum_1h[i], cum_1h[i - 1])

    precip_1h = [max(0.0, cum_1h[0])]
    for i in range(1, len(cum_1h)):
        precip_1h.append(max(0.0, cum_1h[i] - cum_1h[i - 1]))
    return [round(p, 2) for p in precip_1h]


def _hourly_temps_from_3h(temps_3h, num_hours):
    """Teplota 3h → každá hodina (kubická interpolácia)."""
    from scipy.interpolate import interp1d

    n = min(len(temps_3h), len(FORECAST_STEPS_3H))
    if n == 0:
        return [20.0] * num_hours
    hours_3h = FORECAST_STEPS_3H[:n]
    if n >= 4:
        temp_interp = interp1d(hours_3h, temps_3h[:n], kind='cubic', fill_value='extrapolate')
        return [round(float(temp_interp(h)), 1) for h in range(num_hours)]
    return [round(float(t), 1) for t in temps_3h[:num_hours]]


def _wind_from_uv_ms(u, v):
    """Rýchlosť (km/h) a smer (°) z u/v komponentov v m/s."""
    speed_kmh = math.hypot(float(u), float(v)) * 3.6
    direction = (270.0 - math.degrees(math.atan2(float(v), float(u)))) % 360.0
    return round(speed_kmh, 1), round(direction)


def _estimate_hourly_wind_kmh(temps, num_hours):
    """Odhad 10m vetra (km/h) — kým chýbajú u/v z GRIB."""
    speeds = []
    directions = []
    for i in range(num_hours):
        temp = temps[i] if i < len(temps) else 15.0
        hour = i % 24
        base = 5.0 + max(0.0, (temp - 8.0) * 0.35)
        if 9 <= hour <= 17:
            base += 3.0
        elif hour >= 22 or hour <= 4:
            base -= 1.5
        speeds.append(round(max(2.0, base), 1))
        directions.append(int((210 + (i * 23) % 100) % 360))
    return speeds, directions


def _hourly_winds_from_3h(u_3h, v_3h, num_hours):
    """u/v v krokoch 3h → hodinové rýchlosť a smer."""
    u_1h = _hourly_temps_from_3h(u_3h, num_hours)
    v_1h = _hourly_temps_from_3h(v_3h, num_hours)
    speeds = []
    directions = []
    for u, v in zip(u_1h, v_1h):
        s, d = _wind_from_uv_ms(u, v)
        speeds.append(s)
        directions.append(d)
    return speeds, directions


def _sky_wmo_from_cloud_cover(cloud_pct):
    """WMO 0–3 z total cloud cover (%), rovnaké prahy ako Flutter app."""
    if cloud_pct is None:
        return 1
    c = float(cloud_pct)
    if c < 12:
        return 0
    if c < 28:
        return 1
    if c < 62:
        return 2
    return 3


def _wmo_from_precip_mm(p_mm, cloud_pct=None):
    p = float(p_mm)
    if p >= 5.0:
        return 65
    if p >= 2.0:
        return 63
    if p >= 0.5:
        return 61
    if p >= 0.1:
        return 51
    return _sky_wmo_from_cloud_cover(cloud_pct)


def _weather_code_for_hour(p_mm, cloud_pct):
    """Uložený WMO — obloha; dážď v appke len pri mm + šanca ≥ 50 %."""
    if float(p_mm) >= 0.5:
        return _wmo_from_precip_mm(p_mm, cloud_pct)
    return _sky_wmo_from_cloud_cover(cloud_pct)


def _hourly_cloud_from_3h(tcc_3h, num_hours):
    """TCC 0–1 v krokoch 3h → percentá pre každú hodinu."""
    if not tcc_3h:
        return []
    pct_3h = [max(0.0, min(100.0, float(v) * 100.0)) for v in tcc_3h]
    pct_1h = _hourly_temps_from_3h(pct_3h, num_hours)
    return [max(0.0, min(100.0, round(float(v), 1))) for v in pct_1h]


def generate_slovakia_grid():
    """Grid — stredná Európa + Pobaltie (SK, PL, Baltikum vrátane Madony)."""
    lat_min, lat_max = 47.5, 58.0
    lon_min, lon_max = 16.5, 28.5
    step = 0.4  # ECMWF 0.4° rozlíšenie
    
    locations = []
    lat = lat_min
    idx = 0
    while lat <= lat_max:
        lon = lon_min
        while lon <= lon_max:
            locations.append({
                'name': f'grid_{idx}',
                'lat': round(lat, 2),
                'lon': round(lon, 2),
                'display_name': f'{lat:.1f}°N {lon:.1f}°E'
            })
            idx += 1
            lon += step
        lat += step
    
    print(f"Generated {len(locations)} grid points (CE + Baltic)")
    return locations

# Generuj grid automaticky
LOCATIONS = generate_slovakia_grid()

def download_with_ecmwf_opendata(loc, tmpdir):
    """Stiahne ECMWF dáta pomocou ecmwf-opendata knižnice"""
    try:
        from ecmwf.opendata import Client
        
        client = Client(source="ecmwf")
        
        # Súbor pre teplotu
        target_temp = os.path.join(tmpdir, f"{loc['name']}_temp.grib2")
        
        client.retrieve(
            date=0,  # Dnes
            time=0,  # 00z
            step=FORECAST_STEPS_3H,
            stream="oper",
            type="fc",
            param="2t",  # 2m teplota
            target=target_temp,
        )
        
        # Súbor pre zrážky
        target_precip = os.path.join(tmpdir, f"{loc['name']}_precip.grib2")
        
        client.retrieve(
            date=0,
            time=0,
            step=FORECAST_STEPS_3H,
            stream="oper",
            type="fc",
            param="tp",  # Total precipitation
            target=target_precip,
        )

        target_wind_u = os.path.join(tmpdir, f"{loc['name']}_wind_u.grib2")
        target_wind_v = os.path.join(tmpdir, f"{loc['name']}_wind_v.grib2")
        target_tcc = os.path.join(tmpdir, f"{loc['name']}_tcc.grib2")
        client.retrieve(
            date=0, time=0, step=FORECAST_STEPS_3H,
            stream="oper", type="fc", param="10u", target=target_wind_u,
        )
        client.retrieve(
            date=0, time=0, step=FORECAST_STEPS_3H,
            stream="oper", type="fc", param="10v", target=target_wind_v,
        )
        client.retrieve(
            date=0, time=0, step=FORECAST_STEPS_3H,
            stream="oper", type="fc", param="tcc", target=target_tcc,
        )

        return {
            'temp': target_temp,
            'precip': target_precip,
            'wind_u': target_wind_u,
            'wind_v': target_wind_v,
            'tcc': target_tcc,
        }
        
    except Exception as e:
        print(f"  Chyba s ecmwf-opendata: {e}")
        import traceback
        traceback.print_exc()
        return None

def parse_grib_file(grib_file, param_name, lat, lon):
    """Parsuje GRIB súbor a extrahuje hodnoty pre danú lokalitu"""
    try:
        import xarray as xr
        import numpy as np
        
        ds = xr.open_dataset(grib_file, engine='cfgrib',
                            backend_kwargs={'filter_by_keys': {'typeOfLevel': 'surface'}})
        
        # Normalizuj longitude (0-360)
        lon_norm = lon % 360
        
        # Extrahuj hodnoty pre konkrétne súradnice pomocou nearest
        if param_name == 'temperature':
            var_name = 't2m' if 't2m' in ds else '2t'
            if var_name in ds:
                da = ds[var_name]
                # Vyber najbližší bod a konvertuj na Python float
                values = da.sel(latitude=lat, longitude=lon_norm, method='nearest')
                # Konvertuj na °C a potom na Python list s float hodnotami
                temps = [float(v) for v in (values.values - 273.15)]
                return temps
        elif param_name == 'precipitation':
            var_name = 'tp'
            if var_name in ds:
                da = ds[var_name]
                values = da.sel(latitude=lat, longitude=lon_norm, method='nearest')
                return [max(0.0, float(v) * 1000.0) for v in values.values]
        
        return None
        
    except Exception as e:
        print(f"  Chyba pri parsovaní GRIB: {e}")
        import traceback
        traceback.print_exc()
        return None


def generate_forecast_for_location(loc, tmpdir):
    """Generuje predpoveď pre jednu lokalitu z GRIB dát"""
    lat, lon = loc['lat'], loc['lon']
    
    print(f"\nSpracovávam {loc['name']} ({lat}, {lon})...")
    
    # Stiahni dáta pomocou ecmwf-opendata
    grib_files = download_with_ecmwf_opendata(loc, tmpdir)
    
    downloaded_data = {}
    
    if grib_files:
        if os.path.exists(grib_files['temp']):
            print(f"  ✓ Stiahnuté: teplota")
            data = parse_grib_file(grib_files['temp'], 'temperature', lat, lon)
            if data is not None:
                downloaded_data['temperature'] = data
                print(f"    Načítaných {len(data)} hodnôt teploty")
        
        if os.path.exists(grib_files['precip']):
            print(f"  ✓ Stiahnuté: zrážky")
            data = parse_grib_file(grib_files['precip'], 'precipitation', lat, lon)
            if data is not None:
                downloaded_data['precipitation_cumulative'] = data
                print(f"    Načítaných {len(data)} kumul. krokov zrážok (3h)")
    
    # Generuj časové značky (40 krokov = 120 hodín v 3h intervaloch)
    now = datetime.utcnow()
    base_date = now.replace(hour=0, minute=0, second=0, microsecond=0)
    times_3h = [(base_date + timedelta(hours=h*3)) for h in range(40)]
    
    # Priprav dáta (fallback na simulované ak nemáme reálne)
    temps_3h = downloaded_data.get('temperature', [20.0 + (h % 24 - 12) * 0.5 for h in range(40)])
    precip_cum = downloaded_data.get('precipitation_cumulative')
    if precip_cum is None:
        precip_cum = downloaded_data.get('precipitation', [0.0] * 40)
    
    min_len = min(len(temps_3h), len(precip_cum), len(FORECAST_STEPS_3H))
    temps_3h = temps_3h[:min_len]
    precip_cum = precip_cum[:min_len]
    
    max_h = FORECAST_STEPS_3H[min_len - 1] if min_len else 0
    hours_1h = list(range(max_h + 1))
    
    temps_1h = _hourly_temps_from_3h(temps_3h, len(hours_1h))
    precip_1h = _hourly_precip_from_3h_step_deltas(precip_cum)
    precip_1h = precip_1h[:len(hours_1h)]
    
    times = [(base_date + timedelta(hours=h)).isoformat() for h in hours_1h]
    temps = temps_1h
    precip = precip_1h
    pressure = [1013.0] * len(times)
    hourly_weather_code = [
        _weather_code_for_hour(float(p), None) for p in precip
    ]
    
    # Denné agregácie (z hodinových dát)
    daily_times = []
    daily_max = []
    daily_min = []
    daily_precip = []
    daily_weather_code = []
    
    hours_per_day = 24
    num_days = len(times) // hours_per_day
    
    for day in range(num_days):
        start = day * hours_per_day
        end = min(start + hours_per_day, len(times))
        if start < len(times):
            day_temps = temps[start:end]
            day_precip = precip[start:end]
            day_date = base_date + timedelta(days=day)
            
            daily_times.append(day_date.strftime('%Y-%m-%d'))
            daily_max.append(round(max(day_temps), 1))
            daily_min.append(round(min(day_temps), 1))
            daily_precip.append(round(sum(day_precip), 1))
            day_codes = hourly_weather_code[start:end]
            day_precip_codes = [c for c in day_codes if c >= 51]
            if day_precip_codes:
                daily_weather_code.append(max(day_precip_codes))
            elif day_codes:
                daily_weather_code.append(max(set(day_codes), key=day_codes.count))
            else:
                daily_weather_code.append(2)
    
    now = datetime.utcnow()
    
    return {
        'latitude': lat,
        'longitude': lon,
        'timezone': 'Europe/Bratislava',
        'timezone_abbreviation': 'CEST',
        'utc_offset_seconds': 7200,
        'source': 'ECMWF CDS (real GRIB data)',
        'model': 'IFS 0.4°',
        'resolution': '0.4°',
        'date': now.strftime('%Y%m%d'),
        'cycle': '00z',
        'fetched_at': now.isoformat(),
        'location_name': loc['name'],
        'current': {
            'time': times[0] if times else now.isoformat(),
            'temperature_2m': round(float(temps[0]), 1) if temps else 20.0,
            'surface_pressure': round(float(pressure[0]), 1) if pressure else 1013.0,
            'wind_speed_10m': 5,
            'wind_direction_10m': 180,
            'precipitation': round(float(precip[0]), 1) if precip else 0.0,
            'relative_humidity_2m': 65,
            'apparent_temperature': round(float(temps[0]), 1) if temps else 20.0,
            'wind_gusts_10m': 10,
            'dew_point_2m': round(float(temps[0]) - 5, 1) if temps else 15.0,
            'uv_index': 0,
        },
        'hourly': {
            'time': times,
            'temperature_2m': [round(float(t), 1) for t in temps],
            'pressure_msl': [round(float(p), 1) for p in pressure],
            'precipitation': [round(float(p), 1) for p in precip],
            'weather_code': hourly_weather_code,
            'relative_humidity_2m': [65] * len(times),
            'wind_speed_10m': [5] * len(times),
        },
        'daily': {
            'time': daily_times,
            'temperature_2m_max': daily_max,
            'temperature_2m_min': daily_min,
            'precipitation_sum': daily_precip,
            'weather_code': daily_weather_code,
        },
        'ecmwf_info': {
            'model_version': 'IFS CY48R1',
            'grid': 'O1280',
            'levels': 137,
            'forecast_hours': 120,
            'data_source': 'https://data.ecmwf.int',
            'download_method': 'ecmwf-opendata',
            'params_downloaded': list(downloaded_data.keys()),
        }
    }

def main():
    """Hlavná funkcia - generuje jeden grid súbor pre celé Slovensko"""
    print("=" * 60)
    print("ECMWF REAL DATA FETCH - data.ecmwf.int (ecmwf-opendata)")
    print("=" * 60)
    
    now = datetime.utcnow()
    print(f"Dátum: {now.strftime('%Y%m%d')}")
    print(f"Grid bodov: {len(LOCATIONS)}")
    
    # Vytvor temp adresár
    with tempfile.TemporaryDirectory() as tmpdir:
        print(f"\nTemp adresár: {tmpdir}")
        
        # Stiahni GRIB súbory raz (global) pre všetky parametre
        print("\nSťahujem ECMWF dáta (jeden download pre všetky lokality)...")
        grib_files = download_global_grib(tmpdir)
        
        if not grib_files:
            print("✗ Nepodarilo sa stiahnuť GRIB súbory")
            return
        
        print(f"✓ Stiahnuté: {list(grib_files.keys())}")
        
        # Spracuj každú lokalitu z gridu
        grid_data = []
        for i, loc in enumerate(LOCATIONS):
            try:
                data = generate_forecast_for_location_with_grib(loc, grib_files)
                grid_data.append({
                    'lat': loc['lat'],
                    'lon': loc['lon'],
                    'forecast': data
                })
                if (i + 1) % 10 == 0:
                    print(f"  Spracovaných {i + 1}/{len(LOCATIONS)} bodov...")
            except Exception as e:
                print(f"  ✗ Chyba pri spracovaní {loc['name']}: {e}")
        
        # Ulož jeden veľký JSON so všetkými bodmi
        output = {
            'type': 'slovakia_grid',
            'generated_at': now.isoformat(),
            'date': now.strftime('%Y%m%d'),
            'grid_resolution': '0.4°',
            'total_points': len(grid_data),
            'bounds': {
                'lat_min': 47.5,
                'lat_max': 58.0,
                'lon_min': 16.5,
                'lon_max': 28.5
            },
            'locations': grid_data
        }
        
        output_file = "ecmwf_forecast_slovakia_grid.json"
        with open(output_file, 'w', encoding='utf-8') as f:
            json.dump(output, f, indent=2, ensure_ascii=False)
        
        print(f"\n  ✓ Uložené: {output_file}")
        print(f"    Body: {len(grid_data)}")
        print(f"    Veľkosť: {os.path.getsize(output_file) / 1024:.1f} KB")
    
    print("\n" + "=" * 60)
    print("HOTOVO!")
    print("=" * 60)


def download_global_grib(tmpdir, dates_to_try=None):
    """Stiahne global GRIB súbory raz pre všetky lokality."""
    if dates_to_try is None:
        dates_to_try = [0, -1, -2]

    try:
        from ecmwf.opendata import Client

        client = Client(source="ecmwf")
        target_temp = os.path.join(tmpdir, "global_temp.grib2")
        target_precip = os.path.join(tmpdir, "global_precip.grib2")

        for date in dates_to_try:
            try:
                print(f"  Sťahujem teplotu (date={date})...")
                client.retrieve(
                    date=date,
                    time=0,
                    step=FORECAST_STEPS_3H,
                    stream="oper",
                    type="fc",
                    param="2t",
                    target=target_temp,
                )
                print(f"  Sťahujem zrážky (date={date})...")
                client.retrieve(
                    date=date,
                    time=0,
                    step=FORECAST_STEPS_3H,
                    stream="oper",
                    type="fc",
                    param="tp",
                    target=target_precip,
                )
                target_wind_u = os.path.join(tmpdir, "global_wind_u.grib2")
                target_wind_v = os.path.join(tmpdir, "global_wind_v.grib2")
                print(f"  Sťahujem vietor u/v (date={date})...")
                client.retrieve(
                    date=date,
                    time=0,
                    step=FORECAST_STEPS_3H,
                    stream="oper",
                    type="fc",
                    param="10u",
                    target=target_wind_u,
                )
                client.retrieve(
                    date=date,
                    time=0,
                    step=FORECAST_STEPS_3H,
                    stream="oper",
                    type="fc",
                    param="10v",
                    target=target_wind_v,
                )
                target_tcc = os.path.join(tmpdir, "global_tcc.grib2")
                print(f"  Sťahujem oblačnosť tcc (date={date})...")
                client.retrieve(
                    date=date,
                    time=0,
                    step=FORECAST_STEPS_3H,
                    stream="oper",
                    type="fc",
                    param="tcc",
                    target=target_tcc,
                )
                return {
                    'temp': target_temp,
                    'precip': target_precip,
                    'wind_u': target_wind_u,
                    'wind_v': target_wind_v,
                    'tcc': target_tcc,
                }
            except Exception as e:
                print(f"  GRIB date={date} zlyhal: {e}")
                continue
        return None
    except Exception as e:
        print(f"Chyba pri sťahovaní: {e}")
        return None


def generate_forecast_for_location_with_grib(loc, grib_files):
    """Generuje predpoveď pre lokalitu zo stiahnutých GRIB súborov"""
    import xarray as xr
    import numpy as np
    
    lat, lon = loc['lat'], loc['lon']
    downloaded_data = {}
    
    # Parsuj teplotu
    if os.path.exists(grib_files['temp']):
        try:
            ds = xr.open_dataset(grib_files['temp'], engine='cfgrib',
                                filter_by_keys={'type': 'fc', 'stepType': 'instant'})
            lon_norm = lon % 360
            
            # Debug: zobraz čo máme v datasete
            print(f"    DEBUG {loc['name']}: lat={lat}, lon={lon_norm}")
            print(f"    Dataset lat range: {float(ds.latitude.min().values):.2f} to {float(ds.latitude.max().values):.2f}")
            print(f"    Dataset lon range: {float(ds.longitude.min().values):.2f} to {float(ds.longitude.max().values):.2f}")
            
            point = ds.sel(latitude=lat, longitude=lon_norm, method='nearest')
            actual_lat = float(point.latitude.values)
            actual_lon = float(point.longitude.values)
            print(f"    Selected: lat={actual_lat:.2f}, lon={actual_lon:.2f}")
            
            # Konvertuj z Kelvinov na Celsius (ECMWF dáta sú v K)
            temps = [float(v) - 273.15 for v in point.t2m.values]
            print(f"    Temp range: {min(temps):.1f} to {max(temps):.1f}")
            downloaded_data['temperature'] = temps
            ds.close()  # DÔLEŽITÉ: zatvor dataset!
        except Exception as e:
            print(f"    Chyba teplota pre {loc['name']}: {e}")
            import traceback
            traceback.print_exc()
    
    # Parsuj zrážky
    if os.path.exists(grib_files['precip']):
        try:
            ds = xr.open_dataset(grib_files['precip'], engine='cfgrib',
                                filter_by_keys={'type': 'fc', 'stepType': 'accum'})
            lon_norm = lon % 360
            point = ds.sel(latitude=lat, longitude=lon_norm, method='nearest')
            precip_m = [float(v) for v in point.tp.values]
            precip_cum_mm = [max(0.0, v * 1000.0) for v in precip_m]
            downloaded_data['precipitation_cumulative'] = precip_cum_mm
            print(
                f"    Zrážky kumul. mm: max={max(precip_cum_mm):.2f}, "
                f"krokov={len(precip_cum_mm)} (3h → 1h)"
            )
            ds.close()  # DÔLEŽITÉ: zatvor dataset!
        except Exception as e:
            print(f"    Chyba zrážky pre {loc['name']}: {e}")
    
    if os.path.exists(grib_files.get('wind_u', '')):
        try:
            ds = xr.open_dataset(
                grib_files['wind_u'],
                engine='cfgrib',
                filter_by_keys={'type': 'fc', 'stepType': 'instant'},
            )
            lon_norm = lon % 360
            point = ds.sel(latitude=lat, longitude=lon_norm, method='nearest')
            var = 'u10' if 'u10' in ds else '10u'
            downloaded_data['wind_u'] = [float(v) for v in point[var].values]
            ds.close()
        except Exception as e:
            print(f"    Chyba vetor u pre {loc['name']}: {e}")

    if os.path.exists(grib_files.get('wind_v', '')):
        try:
            ds = xr.open_dataset(
                grib_files['wind_v'],
                engine='cfgrib',
                filter_by_keys={'type': 'fc', 'stepType': 'instant'},
            )
            lon_norm = lon % 360
            point = ds.sel(latitude=lat, longitude=lon_norm, method='nearest')
            var = 'v10' if 'v10' in ds else '10v'
            downloaded_data['wind_v'] = [float(v) for v in point[var].values]
            ds.close()
        except Exception as e:
            print(f"    Chyba vetor v pre {loc['name']}: {e}")

    if os.path.exists(grib_files.get('tcc', '')):
        try:
            ds = xr.open_dataset(
                grib_files['tcc'],
                engine='cfgrib',
                filter_by_keys={'type': 'fc', 'stepType': 'instant'},
            )
            lon_norm = lon % 360
            point = ds.sel(latitude=lat, longitude=lon_norm, method='nearest')
            var = 'tcc' if 'tcc' in ds else next(iter(ds.data_vars))
            downloaded_data['tcc'] = [float(v) for v in point[var].values]
            print(
                f"    TCC: min={min(downloaded_data['tcc']):.2f}, "
                f"max={max(downloaded_data['tcc']):.2f}"
            )
            ds.close()
        except Exception as e:
            print(f"    Chyba oblačnosť tcc pre {loc['name']}: {e}")
    
    # Generuj hodinovú predpoveď s interpoláciou (rovnaká logika ako predtým)
    return create_hourly_forecast(loc, downloaded_data)


def create_hourly_forecast(loc, downloaded_data):
    """Vytvorí hodinovú predpoveď — teplota + zrážky po 1 h (z 3h GRIB krokov)."""
    lat, lon = loc['lat'], loc['lon']
    
    now = datetime.utcnow()
    base_date = now.replace(hour=0, minute=0, second=0, microsecond=0)
    
    temps_3h = downloaded_data.get('temperature', [20.0] * len(FORECAST_STEPS_3H))
    precip_cum = downloaded_data.get('precipitation_cumulative')
    if precip_cum is None:
        # Spätná kompatibilita: staré JSON mali 3h úhrny
        legacy = downloaded_data.get('precipitation', [0.0] * len(FORECAST_STEPS_3H))
        precip_cum = [0.0]
        for val in legacy:
            precip_cum.append(precip_cum[-1] + max(0.0, float(val)))
        precip_cum = precip_cum[1:]
    
    min_len = min(len(temps_3h), len(precip_cum), len(FORECAST_STEPS_3H))
    temps_3h = temps_3h[:min_len]
    precip_cum = precip_cum[:min_len]
    
    max_h = FORECAST_STEPS_3H[min_len - 1] if min_len else 0
    hours_1h = list(range(max_h + 1))
    
    temps_1h = _hourly_temps_from_3h(temps_3h, len(hours_1h))
    precip_1h = _hourly_precip_from_3h_step_deltas(precip_cum)[:len(hours_1h)]
    
    times = [(base_date + timedelta(hours=h)).isoformat() for h in hours_1h]
    temps = temps_1h
    precip = precip_1h

    tcc_3h = downloaded_data.get('tcc')
    hourly_cloud_cover = _hourly_cloud_from_3h(tcc_3h, len(hours_1h))

    hourly_weather_code = []
    for i, p in enumerate(precip):
        cloud = hourly_cloud_cover[i] if i < len(hourly_cloud_cover) else None
        hourly_weather_code.append(_weather_code_for_hour(float(p), cloud))
    
    u_3h = downloaded_data.get('wind_u')
    v_3h = downloaded_data.get('wind_v')
    if u_3h and v_3h:
        w_len = min(len(u_3h), len(v_3h), min_len)
        wind_speed_1h, wind_dir_1h = _hourly_winds_from_3h(
            u_3h[:w_len], v_3h[:w_len], len(hours_1h)
        )
    else:
        wind_speed_1h, wind_dir_1h = _estimate_hourly_wind_kmh(temps, len(hours_1h))
    
    # Denné agregácie
    daily_times, daily_max, daily_min, daily_precip = [], [], [], []
    daily_weather_code = []
    hours_per_day = 24
    num_days = len(times) // hours_per_day
    
    for day in range(num_days):
        start = day * hours_per_day
        end = min(start + hours_per_day, len(times))
        if start < len(times):
            daily_times.append((base_date + timedelta(days=day)).strftime('%Y-%m-%d'))
            daily_max.append(round(max(temps[start:end]), 1))
            daily_min.append(round(min(temps[start:end]), 1))
            daily_precip.append(round(sum(precip[start:end]), 1))
            # Najčastejší weather code v daný deň (alebo najvyšší ak sú zrážky)
            day_codes = hourly_weather_code[start:end]
            day_precip_codes = [c for c in day_codes if c >= 51]
            if day_precip_codes:
                # Ak sú zrážky, použij najvyšší kód (najsilnejšie)
                daily_weather_code.append(max(day_precip_codes))
            else:
                # Inak najčastejší
                daily_weather_code.append(max(set(day_codes), key=day_codes.count))
    
    return {
        'latitude': lat,
        'longitude': lon,
        'timezone': 'Europe/Bratislava',
        'timezone_abbreviation': 'CEST',
        'utc_offset_seconds': 7200,
        'source': 'ECMWF IFS 0.4° (real GRIB data)',
        'model': 'IFS 0.4°',
        'resolution': '0.4°',
        'temporal_resolution': '1h (from 3h GRIB steps)',
        'precipitation_probability_available': False,
        'date': now.strftime('%Y%m%d'),
        'cycle': '00z',
        'fetched_at': now.isoformat(),
        'current': {
            'time': times[0] if times else now.isoformat(),
            'temperature_2m': round(float(temps[0]), 1) if temps else 20.0,
            'surface_pressure': 1013.0,
            'wind_speed_10m': wind_speed_1h[0] if wind_speed_1h else 5,
            'wind_direction_10m': wind_dir_1h[0] if wind_dir_1h else 180,
            'precipitation': round(float(precip[0]), 1) if precip else 0.0,
            'weather_code': hourly_weather_code[0] if hourly_weather_code else 0,
            'cloud_cover': hourly_cloud_cover[0] if hourly_cloud_cover else 50,
            'is_day': 1 if (datetime.utcnow().hour >= 6 and datetime.utcnow().hour < 20) else 0,
        },
        'hourly': {
            'time': times,
            'temperature_2m': temps,
            'precipitation': precip,
            'weather_code': hourly_weather_code,
            'cloud_cover': hourly_cloud_cover,
            'wind_speed_10m': wind_speed_1h,
            'wind_direction_10m': wind_dir_1h,
        },
        'daily': {
            'time': daily_times,
            'temperature_2m_max': daily_max,
            'temperature_2m_min': daily_min,
            'precipitation_sum': daily_precip,
            'weather_code': daily_weather_code,
        }
    }

if __name__ == '__main__':
    main()
