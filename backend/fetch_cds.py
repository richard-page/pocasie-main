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

# CDS API klient
CDS_API_KEY = 'e1f7a29a-8a37-494c-86ff-8795fea9b426'
c = Client(
    url='https://cds.climate.copernicus.eu/api',
    key=CDS_API_KEY,
    verify=True
)

all_data = {}

for loc in locations:
    print(f"Sťahujem: {loc['name']}...")
    
    # ECMWF predpoveď z CDS
    c.retrieve(
        'operational-archive',
        {
            'class': 'od',
            'stream': 'oper',
            'type': 'fc',
            'date': datetime.utcnow().strftime('%Y-%m-%d'),
            'time': '00:00',
            'levtype': 'sfc',
            'params': [
                '167.128',  # 2m teplota
                '165.128',  # 10m vietor U
                '166.128',  # 10m vietor V
                '151.128',  # tlak
                '228.128',  # zrážky
                '164.128',  # oblačnosť
            ],
            'area': [loc['lat']+0.5, loc['lon']-0.5, loc['lat']-0.5, loc['lon']+0.5],
            'grid': '0.4/0.4',
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
