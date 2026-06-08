#!/usr/bin/env python3
"""
Stiahne ECMWF dáta z Copernicus CDS pre všetky lokality.
Používa CDS API - potrebný API key.
"""

import json
import os
from datetime import datetime
from cdsapi import Client

# Načítaj lokality
with open(os.path.join(os.path.dirname(__file__), 'locations.json')) as f:
    locations = json.load(f)['locations']

# CDS API klient (číta konfiguráciu z ~/.cdsapirc)
c = Client()

all_data = {}

for loc in locations:
    print(f"Sťahujem: {loc['name']}...")
    
    # ECMWF predpoveď z CDS - Open Data API
    target_date = datetime.utcnow().strftime('%Y-%m-%d')
    c.retrieve(
        'ecmwf-open-data',
        {
            'date': target_date,
            'time': '00:00',
            'step': '0/to/240/by/6',
            'type': 'fc',
            'levtype': 'sfc',
            'params': [
                '2t',      # 2m teplota
                '10u',     # 10m vietor U
                '10v',     # 10m vietor V
                'msl',     # tlak
                'tp',      # zrážky
                'tcc',     # oblačnosť
            ],
            'area': [loc['lat']+0.5, loc['lon']-0.5, loc['lat']-0.5, loc['lon']+0.5],
            'format': 'grib',
        },
        f'/tmp/{loc["name"]}.grib'
    )
    
    all_data[loc['name']] = {
        'lat': loc['lat'],
        'lon': loc['lon'],
        'downloaded': datetime.utcnow().isoformat()
    }

# Ulož metadata
output = {
    'metadata': {
        'source': 'Copernicus CDS',
        'model': 'ECMWF IFS',
        'resolution': '0.4°',
        'fetched_at': datetime.utcnow().isoformat(),
        'locations': len(locations)
    },
    'locations': all_data
}

output_file = os.path.join(os.path.dirname(__file__), 'ecmwf_forecast.json')
with open(output_file, 'w') as f:
    json.dump(output, f, indent=2)

print(f"Hotovo! Uložené do {output_file}")
