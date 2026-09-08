import 'package:shared_preferences/shared_preferences.dart';

import '../domain/trading_assets.dart';

abstract interface class TradingAssetRepository {
  Future<List<String>> load();

  Future<void> save(List<String> symbols);
}

class LocalTradingAssetRepository implements TradingAssetRepository {
  static const _storageKey = 'cryptopilot.trading_assets.v1';
  static final _symbolPattern = RegExp(r'^[A-Z0-9]{2,12}$');

  @override
  Future<List<String>> load() async {
    final preferences = await SharedPreferences.getInstance();
    final saved = preferences.getStringList(_storageKey);
    return _normalize(saved ?? TradingAssets.defaultSymbols);
  }

  @override
  Future<void> save(List<String> symbols) async {
    final normalized = _normalize(symbols);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setStringList(_storageKey, normalized);
  }

  List<String> _normalize(Iterable<String> symbols) {
    final normalized = <String>[];
    for (final value in symbols) {
      final symbol = value.trim().toUpperCase();
      if (!_symbolPattern.hasMatch(symbol) || normalized.contains(symbol)) {
        continue;
      }
      normalized.add(symbol);
    }
    return normalized.isEmpty
        ? List<String>.of(TradingAssets.defaultSymbols)
        : normalized;
  }
}
