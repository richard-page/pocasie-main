import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

/// ECMWF CDS (Copernicus Data Store) API Service
/// 
/// Oficiálny zdroj predpovedí počasia z ECMWF.
/// Vyžaduje API kľúč z https://cds.climate.copernicus.eu/
class EcmwfService {
  static const String _baseUrl = 'https://cds.climate.copernicus.eu/api/v2';
  static const String _apiKey = 'ECMWF_API_KEY'; // TODO: Načítať zo secure storage
  
  /// Načíta predpoveď počasia z ECMWF IFS modelu
  /// 
  /// [lat] - zemepisná šírka
  /// [lon] - zemepisná dĺžka  
  /// [days] - počet dní predpovede (max 10 pre ECMWF IFS)
  static Future<Map<String, dynamic>?> fetchForecast(
    double lat,
    double lon, {
    int days = 10,
  }) async {
    try {
      // ECMWF CDS API vyžaduje POST požiadavku na dataset
      final url = Uri.parse('$_baseUrl/resources/reanalysis-era5-pressure-levels');
      
      // Pre jednoduchú predpoveď použijeme momentálne dostupné dáta
      // ECMWF IFS je dostupný cez CDS API
      final requestBody = {
        'dataset': 'operational-ecmwf-forecast',
        'type': 'forecast',
        'variable': [
          '2m_temperature',
          '2m_dewpoint_temperature',
          'total_precipitation',
          'surface_pressure',
          '10m_u_component_of_wind',
          '10m_v_component_of_wind',
          'total_cloud_cover',
        ],
        'latitude': lat,
        'longitude': lon,
        'format': 'json',
      };
      
      final response = await http.post(
        url,
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Basic ${base64Encode(utf8.encode('$_apiKey:'))}',
        },
        body: json.encode(requestBody),
      ).timeout(const Duration(seconds: 30));
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      } else {
        debugPrint('ECMWF API error: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      debugPrint('ECMWF fetch error: $e');
      return null;
    }
  }
  
  /// Jednoduchšia alternatíva - ECMWF Open Data (bez API kľúča)
  /// Používa sa pre rýchlejšie načítanie bez autentifikácie
  static Future<Map<String, dynamic>?> fetchOpenDataForecast(
    double lat,
    double lon, {
    int days = 10,
  }) async {
    try {
      // ECMWF Open Data - dostupné bez API kľúča
      // Použijeme meteoblue ako oficiálneho partnera ECMWF
      // alebo NOAA GFS ktorý redistribuuje ECMWF dáta
      
      // Pre tento príklad použijeme jednoduchý endpoint
      // V produkcii by sa malo použiť oficiálne ECMWF API s kľúčom
      
      final url = Uri.parse(
        'https://api.ecmwf.int/v1/forecasts?'
        'lat=$lat&lon=$lon&days=$days&format=json'
      );
      
      final response = await http.get(
        url,
        headers: {
          'Accept': 'application/json',
          'User-Agent': 'pocasie-app/1.0 (flutter)',
        },
      ).timeout(const Duration(seconds: 25));
      
      if (response.statusCode == 200) {
        return json.decode(response.body) as Map<String, dynamic>;
      }
      return null;
    } catch (e) {
      debugPrint('ECMWF Open Data error: $e');
      return null;
    }
  }
}
