FROM python:3.11-slim

# Inštalácia systémových závislostí pre ecCodes
RUN apt-get update && apt-get install -y \
    libeccodes0 \
    libeccodes-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# Python závislosti
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Aplikácia
COPY ecmwf_parser.py .
COPY fetch_ecmwf_real.py .
COPY fetch_ecmwf_point.py .
COPY start_server.py .

# Port
EXPOSE 5000

# Spustenie
CMD ["python", "start_server.py"]
