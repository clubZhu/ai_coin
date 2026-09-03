import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../domain/market_snapshot.dart';

class MarketPage extends StatefulWidget {
  const MarketPage({super.key, required this.snapshots});

  final List<MarketSnapshot> snapshots;

  @override
  State<MarketPage> createState() => _MarketPageState();
}

class _MarketPageState extends State<MarketPage> {
  int _selectedAsset = 0;
  int _selectedRange = 2;

  @override
  Widget build(BuildContext context) {
    final snapshot = widget.snapshots[_selectedAsset];
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
        Text('BTC / ETH 市场快照', style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 22),
        _AssetSelector(
          snapshots: widget.snapshots,
          selectedIndex: _selectedAsset,
          onSelected: (value) => setState(() => _selectedAsset = value),
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
                r'$' + formatPrice(snapshot.price),
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(height: 7),
              Text(
                '${positive ? '+' : ''}${snapshot.changePercent.toStringAsFixed(2)}%  24h',
                style: TextStyle(
                  color: positive ? AppColors.teal : AppColors.red,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 170,
                child: MarketLineChart(
                  points: snapshot.chartPoints,
                  color: positive ? AppColors.teal : AppColors.red,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: List.generate(5, (index) {
                  const ranges = ['1H', '4H', '1D', '1W', '1M'];
                  final selected = index == _selectedRange;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedRange = index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 160),
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? AppColors.ink : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          ranges[index],
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  );
                }),
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
                  value: r'$' + formatPrice(snapshot.high24h),
                ),
              ),
              Container(width: 1, height: 38, color: AppColors.line),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 18),
                  child: Metric(
                    label: '24h 最低',
                    value: r'$' + formatPrice(snapshot.low24h),
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
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: List.generate(snapshots.length, (index) {
          final selected = selectedIndex == index;
          return Expanded(
            child: GestureDetector(
              key: ValueKey('asset-${snapshots[index].symbol}'),
              onTap: () => onSelected(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 12),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.ink : Colors.transparent,
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Text(
                  snapshots[index].symbol,
                  style: TextStyle(
                    color: selected ? Colors.white : AppColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          );
        }),
      ),
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
        symbol == 'BTC' ? '₿' : 'Ξ',
        style: const TextStyle(
          color: AppColors.teal,
          fontSize: 22,
          fontWeight: FontWeight.w700,
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
                  value: r'$' + formatPrice(resistance.price),
                  icon: Icons.vertical_align_top_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _LevelTile(
                  label: '下方支撑',
                  value: r'$' + formatPrice(support.price),
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
