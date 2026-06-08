# Copernicus CDS Návod

## Krok 1: Registrácia (5 minút)

1. Choď na: https://cds.climate.copernicus.eu/
2. Klikni "Login / Register" (vpravo hore)
3. "Create new account" → vyplň email, heslo
4. Potvrď email (príde link)
5. Prihlás sa

## Krok 2: CDS API Key

1. Po prihlásení choď na: https://cds.climate.copernicus.eu/profile
2. Nájdi sekcie "API key"
3. Skopíruj celý riadok:
   ```
   url: https://cds.climate.copernicus.eu/api/v2
   key: tvoje-uuid-heslo
   ```

## Krok 3: GitHub Secret

1. Choď na: https://github.com/richard-pape/pocasie/settings/secrets/actions
2. "New repository secret"
3. Name: `CDS_API_KEY`
4. Value: tvoje-uuid-heslo (z kroku 2)
5. "Add secret"

## Krok 4: Hotovo

GitHub Actions automaticky spustí skript každých 6 hodín.

**Údaje:**
- Zdroj: Copernicus CDS (ECMWF)
- Model: IFS
- Rozlíšenie: 0.4°
- Aktualizácia: každých 6 hodín
- Cena: ZADARMO
