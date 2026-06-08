# ECMWF Backend - AWS Lambda + S3

**Architektúra:**
- EventBridge → Lambda (každých 6h) → Stiahne GRIB2 z data.ecmwf.int → Parse ecCodes → JSON → S3 → CloudFront

**Náklady:** ~$1-2 mesačne pre malú appku

**Výhody:**
- Oficiálny ECMWF IFS model
- Žiadne API kľúče
- Žiadne limity (iba tvoje AWS limity)
- Plná kontrola

**Setup:**
1. Vytvor S3 bucket `pocasie-ecmwf-data`
2. Vytvor CloudFront distribution pred S3
3. Nasaď Lambda function
4. Pridaj EventBridge rule (rate(6 hours))
5. Uprav Flutter app na čítanie z tvojho CloudFront URL

**Alternatíva bez backendu:**
Použiť Open-Meteo ECMWF endpoint - je to ten istý ECMWF IFS model len cez ich API (limit 10 000 req/deň).
