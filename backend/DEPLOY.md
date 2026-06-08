# Nasadenie ECMWF Backendu

## Bezplatné možnosti (Free Tier)

### 1. Render.com (Najjednoduchšie)
1. Zaregistruj sa na [render.com](https://render.com) (zadarmo)
2. Vytvor **New Web Service**
3. Pripoj GitHub repozitár s `backend/` priečinkom
4. Build command: `docker build -t ecmwf-backend .`
5. Start command: `docker run -p 5000:5000 ecmwf-backend`
6. **Zadarmo:** 750 hodín mesačne (stačí)

URL bude: `https://ecmwf-backend-xxxxx.onrender.com`

### 2. Railway.app
1. [railway.app](https://railway.app) - prihlásenie cez GitHub
2. New project → Deploy from GitHub repo
3. Vyber `backend/` priečinok
4. Automaticky detekuje Dockerfile
5. **Zadarmo:** $5 kredit mesačne (stačí na 500+ hodín)

### 3. Fly.io
```bash
# Inštalácia CLI
winget install Flyio.flyctl

# Login
fly auth signup  # alebo login

# Vytvor app
fly launch --name pocasie-ecmwf --region fra

# Nasadenie
fly deploy
```
**Zadarmo:** 3 shared-cpu-1 VMs (stačí)

---

## Vlastný VPS (Odporúčam pre produkciu)

Najlacnejšie VPS (~3€/mesiac):
- [Hetzner Cloud](https://www.hetzner.com/cloud) - 3.29€/mesiac
- [Contabo](https://contabo.com) - 3.99€/mesiac  
- [DigitalOcean](https://www.digitalocean.com) - $4/mesiac

### Inštalácia na VPS:

```bash
# 1. Pripoj sa na server
ssh root@tvoj-server-ip

# 2. Inštalácia Docker
apt update && apt install -y docker.io docker-compose

# 3. Vytvor priečinok
mkdir /opt/ecmwf-backend && cd /opt/ecmwf-backend

# 4. Skopíruj súbory (scp z lokálneho PC)
# alebo vytvor priamo:
cat > docker-compose.yml << 'EOF'
version: '3'
services:
  ecmwf:
    build: .
    ports:
      - "5000:5000"
    restart: unless-stopped
    environment:
      - PYTHONUNBUFFERED=1
EOF

# 5. Spusti
docker-compose up -d

# 6. Nginx reverse proxy (pre HTTPS)
apt install -y nginx certbot

# Nginx config
cat > /etc/nginx/sites-available/ecmwf << 'EOF'
server {
    listen 80;
    server_name ecmwf.tvoja-domena.sk;
    
    location / {
        proxy_pass http://localhost:5000;
        proxy_set_header Host $host;
        proxy_set_header X-Real-IP $remote_addr;
    }
}
EOF

ln -s /etc/nginx/sites-available/ecmwf /etc/nginx/sites-enabled/
nginx -t && systemctl restart nginx

# 7. HTTPS (certbot)
certbot --nginx -d ecmwf.tvoja-domena.sk
```

---

## Konfigurácia Flutter

Po nasadení uprav `main.dart`:

```dart
// Pre Render.com:
const String kEcmwfBackendUrl = 'https://ecmwf-backend-xxxxx.onrender.com/forecast';

// Pre vlastný VPS:
const String kEcmwfBackendUrl = 'https://ecmwf.tvoja-domena.sk/forecast';
```

---

## Testovanie

```bash
# Lokálne test
python start_server.py
curl "http://localhost:5000/forecast?lat=48.85&lon=2.35"
```

---

## Architektúra

```
[Flutter App] → [Render/Railway/Fly/VPS] → [ECMWF data.ecmwf.int]
     ↑              ↑                           ↑
   User         Tvoj backend              ECMWF Open Data
               (GRIB2 → JSON)
```

**Výhody:**
- ✓ Používatelia vidia len appku
- ✓ Ty kontroluješ backend
- ✓ Žiadne API kľúče pre používateľov
- ✓ Oficiálny ECMWF IFS model
- ✓ Žiadne limity (iba tvoje infra limity)

**Náklady:**
- Render.com: **ZADARMO** (750h/mes)
- Vlastný VPS: **3-4€/mesiac**
