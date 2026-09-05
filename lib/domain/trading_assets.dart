abstract final class TradingAssets {
  static const symbols = ['BTC', 'ETH', 'ZEC', 'BNB'];

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
