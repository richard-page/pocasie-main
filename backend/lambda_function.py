"""
ECMWF Open Data → JSON Converter
AWS Lambda function

Stiahne GRIB2 z data.ecmwf.int, parse ecCodes, uloží JSON na S3.
Spúšťa sa cez EventBridge každých 6 hodín.
"""

import boto3
import requests
import json
import os
from datetime import datetime, timedelta
import subprocess

S3_BUCKET = os.environ.get('S3_BUCKET', 'pocasie-ecmwf-data')
S3_KEY = 'forecast/latest.json'

def lambda_handler(event, context):
    # ECMWF Open Data URL pre aktuálnu predpoveď
    # IFS 0.4° resolúcia
    date_str = datetime.utcnow().strftime('%Y%m%d')
    cycle = '00'  # 00 UTC run
    
    # Základné URL pre ECMWF Open Data
    base_url = f"https://data.ecmwf.int/forecasts/{date_str}/{cycle}z/ifs/0p4-beta"
    
    # Parametre ktoré potrebujeme
    params = {
        'type': 'fc',
        'levtype': 'sfc',
        'param': '167.128',  # 2m teplota
        'step': '0/to/240/by/1',
    }
    
    try:
        # Stiahni GRIB2
        grib_url = f"{base_url}/grib_file.grib2"
        response = requests.get(grib_url, timeout=120)
        
        if response.status_code != 200:
            return {'statusCode': 500, 'body': f'Download failed: {response.status_code}'}
        
        grib_data = response.content
        
        # Parse GRIB2 pomocou ecCodes (potrebné v Lambda layer)
        # Tu by bola konverzia - ecCodes Python API
        # Pre demo vrátime štruktúru
        
        forecast_data = {
            'metadata': {
                'source': 'ECMWF Open Data',
                'model': 'IFS',
                'resolution': '0.4°',
                'date': date_str,
                'cycle': cycle,
                'downloaded_at': datetime.utcnow().isoformat(),
            },
            'grib_size_bytes': len(grib_data),
            'note': 'GRIB2 parsing requires ecCodes library'
        }
        
        # Ulož na S3
        s3 = boto3.client('s3')
        s3.put_object(
            Bucket=S3_BUCKET,
            Key=S3_KEY,
            Body=json.dumps(forecast_data),
            ContentType='application/json',
            CacheControl='max-age=21600'  # 6 hodín
        )
        
        return {
            'statusCode': 200,
            'body': json.dumps({'message': 'Forecast updated', 'size': len(grib_data)})
        }
        
    except Exception as e:
        return {'statusCode': 500, 'body': str(e)}
