import 'dart:convert';
import 'dart:io';

typedef AssetCatalogFetcher = Future<Object?> Function(Uri url);

abstract interface class TradingAssetCatalog {
  Future<List<String>> fetchSymbols();
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
}
