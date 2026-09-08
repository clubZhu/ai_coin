abstract final class TradingAssets {
  static const defaultSymbols = ['BTC', 'ETH'];

  /// Kept as the default value for existing call sites. The user's actual
  /// watchlist is loaded from local storage by [AppShell].
  static const symbols = defaultSymbols;

  static const names = {
    'BTC': 'Bitcoin',
    'ETH': 'Ethereum',
    'ZEC': 'Zcash',
    'BNB': 'BNB',
  };

  static String glyph(String symbol) => switch (symbol) {
    'BTC' => '₿',
    'ETH' => 'Ξ',
    'ZEC' => 'Z',
    'BNB' => 'B',
    _ => symbol.isEmpty ? '?' : symbol.substring(0, 1),
  };
}
