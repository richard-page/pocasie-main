#!/usr/bin/env python3
"""
Jednoduchý Flask server pre ECMWF Open Data
Spustí sa lokálne, poskytuje JSON API pre Flutter appku.

Inštalácia:
    pip install flask flask-cors

Použitie:
    python start_server.py

API:
    GET http://localhost:5000/forecast?lat=48.85&lon=2.35
"""

from flask import Flask, request, jsonify
from flask_cors import CORS
import json
import os
from datetime import datetime, timedelta

from ecmwf_parser import EcmwfOpenDataParser

app = Flask(__name__)
CORS(app)  # Povol CORS pre Flutter

CACHE_FILE = '/tmp/ecmwf_cache.json'
CACHE_DURATION_MINUTES = 30  # Cache na 30 minút


def _is_cache_valid():
    """Skontroluje či cache ešte platí"""
    if not os.path.exists(CACHE_FILE):
        return False
    
    file_time = datetime.fromtimestamp(os.path.getmtime(CACHE_FILE))
    age = datetime.now() - file_time
    
    return age < timedelta(minutes=CACHE_DURATION_MINUTES)


def _get_cached_or_fetch(lat: float, lon: float):
    """Získa predpoveď z cache alebo stiahne novú"""
    
    # Skontroluj cache
    if _is_cache_valid():
        try:
            with open(CACHE_FILE, 'r') as f:
                cached = json.load(f)
                # Over či cache je pre rovnakú lokáciu (približne)
                cached_lat = cached.get('latitude', 0)
                cached_lon = cached.get('longitude', 0)
                
                if abs(cached_lat - lat) < 0.1 and abs(cached_lon - lon) < 0.1:
                    print(f"[CACHE] Používam cache pre {lat}, {lon}")
                    return cached
        except:
            pass
    
    # Stiahni novú predpoveď
    print(f"[FETCH] Sťahujem novú predpoveď pre {lat}, {lon}")
    parser = EcmwfOpenDataParser()
    forecast = parser.fetch_forecast(lat, lon)
    
    # Ulož do cache
    with open(CACHE_FILE, 'w') as f:
        json.dump(forecast, f)
    
    return forecast


@app.route('/')
def index():
    return jsonify({
        'service': 'ECMWF Open Data Server',
        'endpoints': {
            '/forecast': 'GET lat, lon - Predpoveď počasia'
        }
    })


@app.route('/forecast')
def forecast():
    """Hlavný endpoint pre predpoveď"""
    try:
        lat = float(request.args.get('lat', 48.8566))
        lon = float(request.args.get('lon', 2.3522))
        
        data = _get_cached_or_fetch(lat, lon)
        
        return jsonify(data)
        
    except Exception as e:
        return jsonify({'error': str(e)}), 500


@app.route('/health')
def health():
    """Health check endpoint"""
    return jsonify({'status': 'ok', 'timestamp': datetime.now().isoformat()})


if __name__ == '__main__':
    print("=" * 50)
    print("ECMWF Open Data Server")
    print("=" * 50)
    print(f"Server beží na: http://localhost:5000")
    print(f"Test: http://localhost:5000/forecast?lat=48.85&lon=2.35")
    print("=" * 50)
    
    app.run(host='0.0.0.0', port=5000, debug=False)
