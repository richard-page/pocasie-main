# ECMWF Open Data - Jednoduché riešenie

## Čo potrebuješ

1. **ecCodes** - GRIB2 parser (jednorazová inštalácia)
2. **Python** 3.8+
3. **Tento script** - stiahne ECMWF a uloží JSON

## Inštalácia ecCodes

### Windows (Najjednoduchšie):
```bash
# 1. Inštaluj Anaconda/Miniconda
# 2. V Anaconda Prompt:
conda install -c conda-forge eccodes
```

### Linux:
```bash
sudo apt-get install libeccodes0 libeccodes-dev
pip install requests
```

### macOS:
```bash
brew install eccodes
pip install requests
```

## Použitie

```bash
# Stiahni ECMWF predpoveď
python fetch_ecmwf.py

# Výstup: ecmwf_forecast.json
```

## Automatizácia (cron job)

### Linux/macOS:
```bash
# Otvor crontab
crontab -e

# Pridaj riadok (každých 6 hodín):
0 */6 * * * cd /path/to/backend && python fetch_ecmwf.py
```

### Windows (Task Scheduler):
1. Otvor Task Scheduler
2. Create Basic Task
3. Trigger: Daily, repeat every 6 hours
4. Action: Start program `python.exe`
5. Arguments: `fetch_ecmwf.py`
6. Start in: `C:\path\to\backend`

## Flutter

```dart
// Načítaj lokálny JSON súbor
import 'dart:io';
import 'dart:convert';

Future<Map<String, dynamic>> loadEcmwfForecast() async {
  final file = File('backend/ecmwf_forecast.json');
  final json = await file.readAsString();
  return jsonDecode(json);
}
```

## Architektúra

```
[ECMWF data.ecmwf.int] 
        ↓ (GRIB2)
[fetch_ecmwf.py] 
        ↓ (konvertuje)
[ecmwf_forecast.json]
        ↓ (číta)
[Flutter App]
```

Žiadne servery, žiadne API kľúče, žiadne tretie strany.
Len: ECMWF → Python → JSON → Flutter.
