#!/usr/bin/env python3
"""Rýchly ECMWF grid len pre Pobaltie (Lotyšsko, Litva, Estónsko) — Madona atď."""

import json
import os
import tempfile
from datetime import datetime

from fetch_ecmwf_real import (
    download_global_grib,
    generate_forecast_for_location_with_grib,
)


def generate_baltic_grid():
    lat_min, lat_max = 53.5, 58.0
    lon_min, lon_max = 20.0, 28.5
    step = 0.4
    locations = []
    lat = lat_min
    idx = 0
    while lat <= lat_max:
        lon = lon_min
        while lon <= lon_max:
            locations.append({
                'name': f'baltic_{idx}',
                'lat': round(lat, 2),
                'lon': round(lon, 2),
            })
            idx += 1
            lon += step
        lat += step
    print(f'Baltic grid: {len(locations)} bodov')
    return locations


def main():
    now = datetime.utcnow()
    locations = generate_baltic_grid()
    with tempfile.TemporaryDirectory() as tmpdir:
        grib_files = download_global_grib(tmpdir)
        if not grib_files:
            raise SystemExit('GRIB download failed')
        grid_data = []
        for i, loc in enumerate(locations):
            try:
                data = generate_forecast_for_location_with_grib(loc, grib_files)
                grid_data.append({'lat': loc['lat'], 'lon': loc['lon'], 'forecast': data})
                if (i + 1) % 20 == 0:
                    print(f'  {i + 1}/{len(locations)}')
            except Exception as e:
                print(f'  skip {loc}: {e}')
    output = {
        'type': 'baltic_grid',
        'generated_at': now.isoformat(),
        'date': now.strftime('%Y%m%d'),
        'grid_resolution': '0.4°',
        'total_points': len(grid_data),
        'bounds': {'lat_min': 53.5, 'lat_max': 58.0, 'lon_min': 20.0, 'lon_max': 28.5},
        'locations': grid_data,
    }
    out_file = 'ecmwf_forecast_baltic_grid.json'
    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, indent=2, ensure_ascii=False)
    print(f'Uložené: {out_file} ({os.path.getsize(out_file) // 1024} KB)')


if __name__ == '__main__':
    main()
