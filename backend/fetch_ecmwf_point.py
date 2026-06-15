#!/usr/bin/env python3
"""Stiahne oficiálne ECMWF Open Data pre jeden bod (ľubovoľné lat/lon)."""

import argparse
import json
import os
import sys
import tempfile

from fetch_ecmwf_real import (
    download_with_ecmwf_opendata,
    generate_forecast_for_location_with_grib,
    download_global_grib,
)


def fetch_point(lat: float, lon: float, name: str | None = None) -> dict:
    loc = {
        'name': name or f'point_{lat:.2f}_{lon:.2f}',
        'lat': round(lat, 2),
        'lon': round(lon, 2),
    }
    with tempfile.TemporaryDirectory() as tmpdir:
        grib_files = download_global_grib(tmpdir)
        if not grib_files:
            grib_files = download_with_ecmwf_opendata(loc, tmpdir)
        if not grib_files:
            raise RuntimeError('Nepodarilo sa stiahnuť ECMWF GRIB dáta')
        forecast = generate_forecast_for_location_with_grib(loc, grib_files)
        forecast['latitude'] = lat
        forecast['longitude'] = lon
        if name:
            forecast['location_name'] = name
        return forecast


def main():
    parser = argparse.ArgumentParser(description='ECMWF Open Data — jeden bod')
    parser.add_argument('--lat', type=float, required=True)
    parser.add_argument('--lon', type=float, required=True)
    parser.add_argument('--name', type=str, default=None)
    parser.add_argument('--output', type=str, default='ecmwf_forecast_point.json')
    args = parser.parse_args()

    print(f'ECMWF point fetch: {args.lat}, {args.lon}')
    data = fetch_point(args.lat, args.lon, args.name)
    with open(args.output, 'w', encoding='utf-8') as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    print(f'Uložené: {args.output}')
    hourly = data.get('hourly', {})
    precips = hourly.get('precipitation', [])
    codes = hourly.get('weather_code', [])
    rain_hours = sum(1 for p in precips if (p or 0) > 0.05)
    print(f'  Hodín so zrážkami (>0.05 mm): {rain_hours}/{len(precips)}')
    if codes:
        print(f'  Weather codes: min={min(codes)}, max={max(codes)}')


if __name__ == '__main__':
    try:
        main()
    except Exception as e:
        print(f'Chyba: {e}', file=sys.stderr)
        sys.exit(1)
