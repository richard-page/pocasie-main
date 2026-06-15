#!/usr/bin/env python3
"""
Jednoduchý Flask server pre ECMWF Open Data — ľubovoľné lat/lon v EÚ.
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import json
import os
import hashlib
from datetime import datetime, timedelta

from fetch_ecmwf_point import fetch_point

app = Flask(__name__)
CORS(app)

CACHE_DIR = os.environ.get('ECMWF_CACHE_DIR', '/tmp/ecmwf_cache')
CACHE_DURATION_MINUTES = int(os.environ.get('ECMWF_CACHE_MINUTES', '90'))


def _cache_path(lat: float, lon: float) -> str:
    os.makedirs(CACHE_DIR, exist_ok=True)
    key = f'{lat:.2f}_{lon:.2f}'
    digest = hashlib.sha1(key.encode()).hexdigest()[:12]
    return os.path.join(CACHE_DIR, f'point_{digest}.json')


def _get_cached_or_fetch(lat: float, lon: float):
    path = _cache_path(lat, lon)
    if os.path.exists(path):
        age = datetime.now() - datetime.fromtimestamp(os.path.getmtime(path))
        if age < timedelta(minutes=CACHE_DURATION_MINUTES):
            try:
                with open(path, 'r', encoding='utf-8') as f:
                    print(f'[CACHE] {lat}, {lon}')
                    return json.load(f)
            except Exception:
                pass

    print(f'[FETCH] ECMWF Open Data {lat}, {lon}')
    forecast = fetch_point(lat, lon)
    with open(path, 'w', encoding='utf-8') as f:
        json.dump(forecast, f)
    return forecast


@app.route('/')
def index():
    return jsonify({
        'service': 'ECMWF Open Data Server',
        'endpoints': {'/forecast': 'GET lat, lon'},
    })


@app.route('/forecast')
def forecast():
    try:
        lat = float(request.args.get('lat', 48.8566))
        lon = float(request.args.get('lon', 2.3522))
        return jsonify(_get_cached_or_fetch(lat, lon))
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/health')
def health():
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})


if __name__ == '__main__':
    port = int(os.environ.get('PORT', 5000))
    print('=' * 50)
    print('ECMWF Open Data Server')
    print(f'http://0.0.0.0:{port}/forecast?lat=48.85&lon=2.35')
    print('=' * 50)
    app.run(host='0.0.0.0', port=port, debug=False)
