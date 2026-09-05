import 'package:flutter/material.dart';

import '../core/app_theme.dart';
import '../data/binance_market_repository.dart';
import '../data/live_price_service.dart';
import '../data/market_repository.dart';
import '../data/mock_market_repository.dart';
import '../data/position_repository.dart';
import 'ai/ai_page.dart';
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
  });

  final PositionRepository? positionRepository;
  final LivePriceService? livePriceService;
  final MarketRepository? marketRepository;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  final _repository = const MockMarketRepository();
  late final MarketRepository _marketRepository =
      widget.marketRepository ?? BinanceMarketRepository();
  late final PositionRepository _positionRepository =
      widget.positionRepository ?? LocalPositionRepository();
  late final LivePriceService _livePriceService =
      widget.livePriceService ?? const BinanceLivePriceService();
  int _index = 0;

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
    final snapshots = _repository.snapshots;
    final pages = [
      HomePage(
        snapshots: snapshots,
        positionRepository: _positionRepository,
        livePriceService: _livePriceService,
      ),
      MarketPage(
        repository: _marketRepository,
        livePriceService: _livePriceService,
      ),
      AiPage(
        snapshots: snapshots,
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
        boxShadow: [
          BoxShadow(
            color: Color(0x0A23314A),
            blurRadius: 20,
            offset: Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 76,
          child: Row(
            children: List.generate(items.length, (index) {
              final selected = index == selectedIndex;
              final isAi = index == 2;
              return Expanded(
                child: Semantics(
                  button: true,
                  selected: selected,
                  label: items[index].$2,
                  child: InkWell(
                    key: ValueKey('nav-$index'),
                    onTap: () => onSelected(index),
                    child: Center(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 60,
                        height: 58,
                        decoration: BoxDecoration(
                          color: isAi ? AppColors.tealSoft : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              items[index].$1,
                              size: isAi ? 23 : 21,
                              color: isAi
                                  ? AppColors.teal
                                  : selected
                                  ? AppColors.teal
                                  : AppColors.muted,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              items[index].$2,
                              style: TextStyle(
                                color: selected
                                    ? AppColors.ink
                                    : AppColors.muted,
                                fontSize: 11,
                                fontWeight: selected
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}
