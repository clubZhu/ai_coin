import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../data/binance_asset_catalog.dart';
import '../data/binance_coin_recommendation_repository.dart';
import '../data/binance_market_repository.dart';
import '../data/coin_recommendation_repository.dart';
import '../data/cross_exchange_repository.dart';
import '../data/live_price_service.dart';
import '../data/market_repository.dart';
import '../data/position_repository.dart';
import '../data/public_cross_exchange_repository.dart';
import '../data/trading_asset_repository.dart';
import '../domain/trading_assets.dart';
import 'ai/ai_page.dart';
import 'assets/asset_manager_page.dart';
import 'home/home_page.dart';
import 'journal/review_page.dart';
import 'market/market_page.dart';
import 'profile/profile_page.dart';
import 'risk/risk_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({
    super.key,
    this.positionRepository,
    this.livePriceService,
    this.marketRepository,
    this.crossExchangeRepository,
    this.tradingAssetRepository,
    this.tradingAssetCatalog,
    this.coinRecommendationRepository,
  });

  final PositionRepository? positionRepository;
  final LivePriceService? livePriceService;
  final MarketRepository? marketRepository;
  final CrossExchangeRepository? crossExchangeRepository;
  final TradingAssetRepository? tradingAssetRepository;
  final TradingAssetCatalog? tradingAssetCatalog;
  final CoinRecommendationRepository? coinRecommendationRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late MarketRepository _marketRepository;
  late final PositionRepository _positionRepository =
      widget.positionRepository ?? LocalPositionRepository();
  late final LivePriceService _livePriceService =
      widget.livePriceService ?? const BinanceLivePriceService();
  late final CrossExchangeRepository _crossExchangeRepository =
      widget.crossExchangeRepository ??
      (widget.marketRepository == null
          ? PublicCrossExchangeRepository()
          : const EmptyCrossExchangeRepository());
  late final TradingAssetRepository _tradingAssetRepository =
      widget.tradingAssetRepository ?? LocalTradingAssetRepository();
  late final TradingAssetCatalog _tradingAssetCatalog =
      widget.tradingAssetCatalog ?? BinanceAssetCatalog();
  late final CoinRecommendationRepository _coinRecommendationRepository =
      widget.coinRecommendationRepository ??
      BinanceCoinRecommendationRepository();
  List<String> _symbols = List<String>.of(TradingAssets.defaultSymbols);
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _marketRepository =
        widget.marketRepository ??
        BinanceMarketRepository(symbols: List<String>.unmodifiable(_symbols));
    _loadTradingAssets();
  }

  Future<void> _loadTradingAssets() async {
    try {
      final symbols = await _tradingAssetRepository.load();
      if (!mounted || _sameSymbols(_symbols, symbols)) return;
      setState(() {
        _symbols = List<String>.of(symbols);
        if (widget.marketRepository == null) {
          _marketRepository = BinanceMarketRepository(
            symbols: List<String>.unmodifiable(_symbols),
          );
        }
      });
    } on Exception {
      // Defaults remain available when local preferences cannot be read.
    }
  }

  Future<void> _openAssetManager() async {
    final symbols = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute<List<String>>(
        builder: (_) => AssetManagerPage(
          symbols: _symbols,
          catalog: _tradingAssetCatalog,
          recommendationRepository: _coinRecommendationRepository,
        ),
      ),
    );
    if (!mounted || symbols == null || _sameSymbols(_symbols, symbols)) return;
    setState(() {
      _symbols = List<String>.of(symbols);
      if (widget.marketRepository == null) {
        _marketRepository = BinanceMarketRepository(
          symbols: List<String>.unmodifiable(_symbols),
        );
      }
    });
    try {
      await _tradingAssetRepository.save(_symbols);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('币种顺序保存失败，请稍后重试')));
    }
  }

  bool _sameSymbols(List<String> first, List<String> second) {
    if (first.length != second.length) return false;
    for (var index = 0; index < first.length; index++) {
      if (first[index] != second[index]) return false;
    }
    return true;
  }

  void _openRisk() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const RiskPage()));
  }

  void _openReview() {
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => const ReviewPage()));
  }

  @override
  Widget build(BuildContext context) {
    final pages = [
      HomePage(
        symbols: _symbols,
        positionRepository: _positionRepository,
        livePriceService: _livePriceService,
        onManageSymbols: _openAssetManager,
      ),
      MarketPage(
        repository: _marketRepository,
        livePriceService: _livePriceService,
      ),
      AiPage(
        repository: _marketRepository,
        crossExchangeRepository: _crossExchangeRepository,
        positionRepository: _positionRepository,
        active: _index == 2,
        onOpenRisk: _openRisk,
        onOpenReview: _openReview,
      ),
      ProfilePage(onOpenReview: _openReview),
    ];

    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: _BottomNavigation(
        selectedIndex: _index,
        onSelected: (value) => setState(() => _index = value),
      ),
    );
  }
}

class _BottomNavigation extends StatelessWidget {
  const _BottomNavigation({
    required this.selectedIndex,
    required this.onSelected,
  });

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    const items = [
      (Icons.home_rounded, '首页'),
      (Icons.candlestick_chart_rounded, '行情'),
      (Icons.auto_awesome_rounded, 'AI'),
      (Icons.person_rounded, '我的'),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.line, width: .5)),
        boxShadow: [
          BoxShadow(
            color: Color(0x0623314A),
            blurRadius: 16,
            offset: Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Material(
          color: Colors.transparent,
          child: SizedBox(
            height: 68,
            child: Row(
              children: List.generate(items.length, (index) {
                final selected = index == selectedIndex;
                return Expanded(
                  child: Semantics(
                    button: true,
                    selected: selected,
                    label: items[index].$2,
                    child: InkWell(
                      key: ValueKey('nav-$index'),
                      onTap: () => onSelected(index),
                      child: SizedBox.expand(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              curve: Curves.easeOutCubic,
                              width: 44,
                              height: 28,
                              decoration: BoxDecoration(
                                color: selected
                                    ? AppColors.tealSoft
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                items[index].$1,
                                size: 21,
                                color: selected
                                    ? AppColors.teal
                                    : AppColors.muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 180),
                              style: TextStyle(
                                color: selected
                                    ? AppColors.teal
                                    : AppColors.muted,
                                fontSize: 11,
                                height: 1.2,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                              child: Text(items[index].$2),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }
}
