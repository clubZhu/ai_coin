import 'dart:convert';
import 'dart:io';

typedef AssetCatalogFetcher = Future<Object?> Function(Uri url);

abstract interface class TradingAssetCatalog {
  Future<List<String>> fetchSymbols();

  Future<Map<String, int>> fetchPricePrecisions(Iterable<String> symbols);
}

/// Loads currently tradable Binance spot pairs quoted in USDT.
class BinanceAssetCatalog implements TradingAssetCatalog {
  BinanceAssetCatalog({
    AssetCatalogFetcher? fetcher,
    this.baseUrl = 'https://data-api.binance.vision',
  }) : _fetcher = fetcher ?? _httpFetcher;

  final String baseUrl;
  final AssetCatalogFetcher _fetcher;

  static Future<Object?> _httpFetcher(Uri url) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 10);
    try {
      final request = await client
          .getUrl(url)
          .timeout(const Duration(seconds: 10));
      final response = await request.close().timeout(
        const Duration(seconds: 10),
      );
      if (response.statusCode != HttpStatus.ok) {
        throw HttpException('币安接口返回 ${response.statusCode}', uri: url);
      }
      return jsonDecode(await response.transform(utf8.decoder).join());
    } finally {
      client.close();
    }
  }

  @override
  Future<List<String>> fetchSymbols() async {
    final payload = await _fetcher(Uri.parse('$baseUrl/api/v3/exchangeInfo'));
    if (payload is! Map) throw const FormatException('币种列表格式异常');
    final rows = payload['symbols'];
    if (rows is! List) throw const FormatException('币种列表为空');

    final symbols = <String>{};
    for (final row in rows) {
      if (row is! Map ||
          row['quoteAsset'] != 'USDT' ||
          row['status'] != 'TRADING' ||
          row['isSpotTradingAllowed'] == false) {
        continue;
      }
      final symbol = row['baseAsset'];
      if (symbol is String && symbol.isNotEmpty) {
        symbols.add(symbol.toUpperCase());
      }
    }
    final sorted = symbols.toList()..sort();
    if (sorted.isEmpty) throw const FormatException('暂无可添加币种');
    return sorted;
  }

  @override
  Future<Map<String, int>> fetchPricePrecisions(
    Iterable<String> symbols,
  ) async {
    final normalized = symbols
        .map((symbol) => symbol.trim().toUpperCase())
        .where((symbol) => symbol.isNotEmpty)
        .toSet();
    if (normalized.isEmpty) return const {};
    final pairs = normalized.map((symbol) => '${symbol}USDT').toList();
    final uri = Uri.parse(
      '$baseUrl/api/v3/exchangeInfo',
    ).replace(queryParameters: {'symbols': jsonEncode(pairs)});
    final payload = await _fetcher(uri);
    if (payload is! Map || payload['symbols'] is! List) {
      throw const FormatException('币种精度格式异常');
    }

    final precisions = <String, int>{};
    for (final row in payload['symbols'] as List) {
      if (row is! Map || row['quoteAsset'] != 'USDT') continue;
      final asset = row['baseAsset'];
      if (asset is! String || !normalized.contains(asset.toUpperCase())) {
        continue;
      }
      final precision = _pricePrecision(row);
      if (precision != null) precisions[asset.toUpperCase()] = precision;
    }
    return precisions;
  }

  int? _pricePrecision(Map<dynamic, dynamic> row) {
    final filters = row['filters'];
    if (filters is List) {
      for (final filter in filters) {
        if (filter is! Map || filter['filterType'] != 'PRICE_FILTER') continue;
        final tickSize = filter['tickSize'];
        if (tickSize is String) return _decimalPlaces(tickSize);
      }
    }
    final fallback = row['quoteAssetPrecision'];
    return fallback is num ? fallback.toInt().clamp(0, 12).toInt() : null;
  }

  int _decimalPlaces(String value) {
    if (!value.contains('.')) return 0;
    final fraction = value.split('.').last.replaceFirst(RegExp(r'0+$'), '');
    return fraction.length.clamp(0, 12).toInt();
  }
}
