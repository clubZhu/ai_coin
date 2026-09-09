import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/live_price_service.dart';
import '../../data/market_repository.dart';
import '../../domain/market_snapshot.dart';
import '../../domain/trading_assets.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({
    super.key,
    required this.repository,
    this.livePriceService,
  });

  final MarketRepository repository;
  final LivePriceService? livePriceService;

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  final List<MarketSnapshot> _snapshots = [];

  StreamSubscription<double>? _priceSubscription;
  int _priceStreamGeneration = 0;
  int _snapshotGeneration = 0;

  MarketRange _selectedRange = MarketRange.day;
  int _selectedAsset = 0;
  bool _loadingChart = false;
  bool _hasLivePrice = false;
  List<double> _chartPoints = const [];
  double? _livePrice;
  Object? _error;

  bool get _hasData => _snapshots.isNotEmpty;
  MarketSnapshot get _snapshot => _snapshots[_selectedAsset];
  double get _displayPrice => _livePrice ?? _snapshot.price;

  @override
  void initState() {
    super.initState();
    _loadSnapshots();
  }

  @override
  void didUpdateWidget(MarketPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repository != widget.repository) {
      final selectedSymbol = _hasData ? _snapshot.symbol : null;
      _priceStreamGeneration++;
      _priceSubscription?.cancel();
      _loadSnapshots(preferredSymbol: selectedSymbol, clearExisting: true);
    }
  }

  @override
  void dispose() {
    _priceSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadSnapshots({
    String? preferredSymbol,
    bool clearExisting = false,
  }) async {
    final selectedSymbol =
        preferredSymbol ?? (_hasData ? _snapshot.symbol : null);
    final generation = ++_snapshotGeneration;
    setState(() {
      _error = null;
      if (clearExisting) {
        _snapshots.clear();
        _selectedAsset = 0;
        _livePrice = null;
        _hasLivePrice = false;
        _chartPoints = const [];
      }
    });
    try {
      final snapshots = await widget.repository.fetchSnapshots();
      if (snapshots.isEmpty) throw const FormatException('行情数据为空');
      if (!mounted || generation != _snapshotGeneration) return;
      setState(() {
        _snapshots
          ..clear()
          ..addAll(snapshots);
        final preferredIndex = selectedSymbol == null
            ? -1
            : _snapshots.indexWhere(
                (snapshot) => snapshot.symbol == selectedSymbol,
              );
        _selectedAsset = preferredIndex >= 0 ? preferredIndex : 0;
        _chartPoints = _snapshot.chartPoints;
      });
      _watchSelectedPrice();
    } on Object catch (error) {
      if (!mounted || generation != _snapshotGeneration) return;
      setState(() => _error = error);
      if (_hasData) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('行情刷新失败，请稍后重试')));
      }
    }
  }

  Future<void> _loadChart() async {
    if (!_hasData) return;
    final symbol = _snapshot.symbol;
    final range = _selectedRange;
    setState(() => _loadingChart = true);
    try {
      final points = await widget.repository.fetchChartPoints(
        symbol: symbol,
        range: range,
      );
      if (!mounted || symbol != _snapshot.symbol || range != _selectedRange) {
        return;
      }
      setState(() {
        _chartPoints = points;
        _loadingChart = false;
      });
    } on Object {
      if (!mounted || symbol != _snapshot.symbol || range != _selectedRange) {
        return;
      }
      setState(() {
        _chartPoints = _snapshot.chartPoints;
        _loadingChart = false;
      });
    }
  }

  void _selectAsset(int index) {
    if (index == _selectedAsset) return;
    setState(() {
      _selectedAsset = index;
      _livePrice = null;
      _hasLivePrice = false;
    });
    _watchSelectedPrice();
    _loadChart();
  }

  void _selectRange(MarketRange range) {
    if (range == _selectedRange) return;
    setState(() => _selectedRange = range);
    _loadChart();
  }

  void _watchSelectedPrice() {
    final service = widget.livePriceService;
    if (service == null || !_hasData) return;
    final generation = ++_priceStreamGeneration;
    _priceSubscription?.cancel();
    _priceSubscription = service
        .watchPrice(_snapshot.symbol)
        .listen(
          (price) {
            if (!mounted || generation != _priceStreamGeneration) return;
            setState(() {
              _livePrice = price;
              _hasLivePrice = true;
            });
          },
          onError: (Object _) {
            if (!mounted || generation != _priceStreamGeneration) return;
            setState(() => _hasLivePrice = false);
          },
        );
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: _loadSnapshots,
      child: _hasData ? _buildContent(context) : _buildPlaceholder(context),
    );
  }

  Widget _buildPlaceholder(BuildContext context) {
    if (_error != null) {
      return PageFrame(
        children: [
          SizedBox(
            height: 460,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 42,
                  color: AppColors.muted,
                ),
                const SizedBox(height: 12),
                const Text(
                  '行情加载失败',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '$_error',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  key: const ValueKey('retry-market'),
                  onPressed: _loadSnapshots,
                  icon: const Icon(Icons.refresh_rounded, size: 18),
                  label: const Text('重新加载'),
                ),
              ],
            ),
          ),
        ],
      );
    }
    return PageFrame(
      children: [
        Text('行情', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 22),
        const AppCard(
          child: SizedBox(
            height: 300,
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    final snapshot = _snapshot;
    final positive = snapshot.changePercent >= 0;

    return PageFrame(
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '行情',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
            const StatusPill(
              label: '市场开放',
              icon: Icons.circle,
              foreground: AppColors.teal,
            ),
          ],
        ),
        const SizedBox(height: 5),
        Text(
          '${_snapshots.map((snapshot) => snapshot.symbol).join(' / ')} 市场快照',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 22),
        _AssetSelector(
          snapshots: _snapshots,
          selectedIndex: _selectedAsset,
          onSelected: _selectAsset,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _AssetIcon(symbol: snapshot.symbol),
                  const SizedBox(width: 11),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${snapshot.symbol} / USDT',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        snapshot.name,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                  const Spacer(),
                  const Icon(Icons.star_border_rounded, color: AppColors.muted),
                ],
              ),
              const SizedBox(height: 25),
              Text(
                r'$' +
                    formatPrice(
                      _displayPrice,
                      decimals: snapshot.pricePrecision,
                    ),
                key: ValueKey('market-price-${snapshot.symbol}'),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  Text(
                    '${positive ? '+' : ''}${snapshot.changePercent.toStringAsFixed(2)}%  24h',
                    style: TextStyle(
                      color: positive ? AppColors.teal : AppColors.red,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (_hasLivePrice) ...[
                    const SizedBox(width: 8),
                    const StatusPill(label: '实时', icon: Icons.bolt_rounded),
                  ],
                ],
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 170,
                child: _loadingChart
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : MarketLineChart(
                        points: _chartPoints,
                        color: positive ? AppColors.teal : AppColors.red,
                      ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  for (final range in MarketRange.values)
                    Expanded(
                      child: GestureDetector(
                        key: ValueKey('range-${range.label}'),
                        onTap: () => _selectRange(range),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 160),
                          height: 34,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: range == _selectedRange
                                ? AppColors.ink
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            range.label,
                            style: TextStyle(
                              color: range == _selectedRange
                                  ? Colors.white
                                  : AppColors.muted,
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Row(
            children: [
              Expanded(
                child: Metric(
                  label: '24h 最高',
                  value:
                      r'$' +
                      formatPrice(
                        snapshot.high24h,
                        decimals: snapshot.pricePrecision,
                      ),
                ),
              ),
              Container(width: 1, height: 38, color: AppColors.line),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Metric(
                    label: '24h 最低',
                    value:
                        r'$' +
                        formatPrice(
                          snapshot.low24h,
                          decimals: snapshot.pricePrecision,
                        ),
                  ),
                ),
              ),
              Container(width: 1, height: 38, color: AppColors.line),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Metric(label: '24h 成交额', value: snapshot.volume24h),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionTitle(
                title: '多周期趋势',
                eyebrow: 'AI STRUCTURE',
                trailing: ConsistencyRing(
                  value: snapshot.consistency,
                  size: 56,
                ),
              ),
              const SizedBox(height: 10),
              ...snapshot.trends.map((trend) => TrendLine(trend: trend)),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _LevelCard(snapshot: snapshot),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.amberSoft,
            borderRadius: BorderRadius.circular(18),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.info_outline_rounded,
                color: AppColors.amber,
                size: 20,
              ),
              SizedBox(width: 10),
              Expanded(
                child: Text(
                  '行情结论用于辅助决策，不构成投资建议。请结合仓位与止损计划判断。',
                  style: TextStyle(fontSize: 12, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _AssetSelector extends StatelessWidget {
  const _AssetSelector({
    required this.snapshots,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<MarketSnapshot> snapshots;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final itemWidth = snapshots.length <= 4
            ? (constraints.maxWidth - 8) / snapshots.length
            : 76.0;
        return Container(
          height: 44,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: List.generate(snapshots.length, (index) {
                final selected = selectedIndex == index;
                return GestureDetector(
                  key: ValueKey('asset-${snapshots[index].symbol}'),
                  onTap: () => onSelected(index),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: itemWidth,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.tealSoft : Colors.transparent,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      snapshots[index].symbol,
                      style: TextStyle(
                        color: selected ? AppColors.teal : AppColors.muted,
                        fontSize: 13,
                        fontWeight: selected
                            ? FontWeight.w600
                            : FontWeight.w400,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

class _AssetIcon extends StatelessWidget {
  const _AssetIcon({required this.symbol});

  final String symbol;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        color: AppColors.tealSoft,
        shape: BoxShape.circle,
      ),
      child: Text(
        TradingAssets.glyph(symbol),
        style: const TextStyle(
          color: AppColors.teal,
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _LevelCard extends StatelessWidget {
  const _LevelCard({required this.snapshot});

  final MarketSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final resistance = snapshot.levels.firstWhere((level) => !level.isCurrent);
    final support = snapshot.levels.lastWhere((level) => !level.isCurrent);
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '关键位置', eyebrow: 'PRICE MAP'),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _LevelTile(
                  label: '上方压力',
                  value:
                      r'$' +
                      formatPrice(
                        resistance.price,
                        decimals: snapshot.pricePrecision,
                      ),
                  icon: Icons.vertical_align_top_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LevelTile(
                  label: '下方支撑',
                  value:
                      r'$' +
                      formatPrice(
                        support.price,
                        decimals: snapshot.pricePrecision,
                      ),
                  icon: Icons.vertical_align_bottom_rounded,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            snapshot.explanation,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

class _LevelTile extends StatelessWidget {
  const _LevelTile({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: AppColors.teal, size: 19),
          const SizedBox(height: 12),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16),
          ),
        ],
      ),
    );
  }
}
