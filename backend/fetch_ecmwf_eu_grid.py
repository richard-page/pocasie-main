#!/usr/bin/env python3
"""ECMWF Open Data — grid pre celú EÚ (3 regióny, 1.0°). Jeden GRIB download na tile."""

import argparse
import json
import os
import tempfile
from datetime import datetime

from fetch_ecmwf_real import (
    create_hourly_forecast,
    download_global_grib,
)

EU_STEP = 1.0

EU_TILES = [
    {
        'file': 'ecmwf_forecast_eu_west_grid.json',
        'type': 'eu_west_grid',
        'lat_min': 35.0,
        'lat_max': 72.0,
        'lon_min': -25.0,
        'lon_max': 5.0,
    },
    {
        'file': 'ecmwf_forecast_eu_central_grid.json',
        'type': 'eu_central_grid',
        'lat_min': 35.0,
        'lat_max': 72.0,
        'lon_min': 5.0,
        'lon_max': 28.0,
    },
    {
        'file': 'ecmwf_forecast_eu_east_grid.json',
        'type': 'eu_east_grid',
        'lat_min': 35.0,
        'lat_max': 72.0,
        'lon_min': 28.0,
        'lon_max': 45.0,
    },
]


def generate_locations(lat_min, lat_max, lon_min, lon_max, step=EU_STEP):
    locations = []
    lat = lat_min
    idx = 0
    while lat <= lat_max + 1e-9:
        lon = lon_min
        while lon <= lon_max + 1e-9:
            locations.append({
                'name': f'eu_{idx}',
                'lat': round(lat, 2),
                'lon': round(lon, 2),
            })
            idx += 1
            lon += step
        lat += step
    return locations


def build_tile_forecasts(locations, grib_files):
    import xarray as xr

    ds_temp = xr.open_dataset(
        grib_files['temp'],
        engine='cfgrib',
        filter_by_keys={'type': 'fc', 'stepType': 'instant'},
    )
    ds_precip = xr.open_dataset(
        grib_files['precip'],
        engine='cfgrib',
        filter_by_keys={'type': 'fc', 'stepType': 'accum'},
    )
    ds_tcc = None
    if grib_files.get('tcc') and os.path.exists(grib_files['tcc']):
        try:
            ds_tcc = xr.open_dataset(
                grib_files['tcc'],
                engine='cfgrib',
                filter_by_keys={'type': 'fc', 'stepType': 'instant'},
            )
        except Exception as e:
            print(f'  TCC open failed: {e}')

    grid_data = []
    for i, loc in enumerate(locations):
        lat, lon = loc['lat'], loc['lon']
        lon_norm = lon % 360
        try:
            pt_temp = ds_temp.sel(latitude=lat, longitude=lon_norm, method='nearest')
            pt_precip = ds_precip.sel(latitude=lat, longitude=lon_norm, method='nearest')
            temps = [float(v) - 273.15 for v in pt_temp.t2m.values]
            precip_m = [float(v) for v in pt_precip.tp.values]
            precip_cum_mm = [max(0.0, float(v) * 1000.0) for v in precip_m]
            downloaded = {
                'temperature': temps,
                'precipitation_cumulative': precip_cum_mm,
            }
            if ds_tcc is not None:
                pt_tcc = ds_tcc.sel(latitude=lat, longitude=lon_norm, method='nearest')
                var = 'tcc' if 'tcc' in pt_tcc else next(iter(pt_tcc.data_vars))
                downloaded['tcc'] = [float(v) for v in pt_tcc[var].values]
            forecast = create_hourly_forecast(loc, downloaded)
            grid_data.append({'lat': lat, 'lon': lon, 'forecast': forecast})
        except Exception as e:
            print(f'  skip {loc["lat"]},{loc["lon"]}: {e}')
        if (i + 1) % 100 == 0:
            print(f'  {i + 1}/{len(locations)}')

    ds_temp.close()
    ds_precip.close()
    if ds_tcc is not None:
        ds_tcc.close()
    return grid_data


def generate_tile(tile_cfg):
    now = datetime.utcnow()
    locations = generate_locations(
        tile_cfg['lat_min'],
        tile_cfg['lat_max'],
        tile_cfg['lon_min'],
        tile_cfg['lon_max'],
    )
    print(f"{tile_cfg['file']}: {len(locations)} bodov ({EU_STEP}°)")

    with tempfile.TemporaryDirectory() as tmpdir:
        grib_files = download_global_grib(tmpdir)
        if not grib_files:
            raise SystemExit('GRIB download failed')
        grid_data = build_tile_forecasts(locations, grib_files)

    output = {
        'type': tile_cfg['type'],
        'generated_at': now.isoformat(),
        'date': now.strftime('%Y%m%d'),
        'grid_resolution': f'{EU_STEP}°',
        'total_points': len(grid_data),
        'bounds': {
            'lat_min': tile_cfg['lat_min'],
            'lat_max': tile_cfg['lat_max'],
            'lon_min': tile_cfg['lon_min'],
            'lon_max': tile_cfg['lon_max'],
        },
        'locations': grid_data,
    }

    out_file = tile_cfg['file']
    with open(out_file, 'w', encoding='utf-8') as f:
        json.dump(output, f, ensure_ascii=False)
    print(f'Uložené: {out_file} ({os.path.getsize(out_file) // 1024} KB)')


def main():
    parser = argparse.ArgumentParser(description='ECMWF EU grid tiles')
    parser.add_argument(
        '--tile',
        choices=['west', 'central', 'east', 'all'],
        default='all',
    )
    args = parser.parse_args()

    tiles = EU_TILES
    if args.tile == 'west':
        tiles = [EU_TILES[0]]
    elif args.tile == 'central':
        tiles = [EU_TILES[1]]
    elif args.tile == 'east':
        tiles = [EU_TILES[2]]

    for tile in tiles:
        generate_tile(tile)


if __name__ == '__main__':
    main()
