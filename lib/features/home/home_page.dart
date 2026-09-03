import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../domain/market_snapshot.dart';

class HomePage extends StatelessWidget {
  const HomePage({
    super.key,
    required this.snapshot,
    required this.onOpenMarket,
    required this.onOpenAi,
    required this.onOpenRisk,
    required this.onOpenReview,
  });

  final MarketSnapshot snapshot;
  final VoidCallback onOpenMarket;
  final VoidCallback onOpenAi;
  final VoidCallback onOpenRisk;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      children: [
        _Header(onNotification: () => _showMessage(context)),
        const SizedBox(height: 24),
        Text('早上好，交易者', style: Theme.of(context).textTheme.bodyLarge),
        const SizedBox(height: 4),
        Text('先看市场，再做决定。', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 20),
        _MarketHero(snapshot: snapshot, onTap: onOpenMarket),
        const SizedBox(height: 16),
        _AiMarketCard(snapshot: snapshot, onTap: onOpenAi),
        const SizedBox(height: 16),
        _TrendRadar(snapshot: snapshot),
        const SizedBox(height: 16),
        _PriceMap(snapshot: snapshot, onTap: onOpenMarket),
        const SizedBox(height: 24),
        const SectionTitle(title: '交易工具', eyebrow: 'DISCIPLINE'),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _ToolCard(
                title: '仓位风险',
                subtitle: '下单前先体检',
                icon: Icons.shield_outlined,
                color: AppColors.amberSoft,
                iconColor: AppColors.amber,
                onTap: onOpenRisk,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _ToolCard(
                title: '今日复盘',
                subtitle: '发现行为模式',
                icon: Icons.insights_rounded,
                color: AppColors.tealSoft,
                iconColor: AppColors.teal,
                onTap: onOpenReview,
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _PrincipleCard(),
      ],
    );
  }

  void _showMessage(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('目前没有新的风险提醒')));
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onNotification});

  final VoidCallback onNotification;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.ink,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.explore_rounded,
            color: Colors.white,
            size: 23,
          ),
        ),
        const SizedBox(width: 10),
        const Text(
          'CryptoPilot',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.3,
          ),
        ),
        const Spacer(),
        RoundIconButton(
          icon: Icons.notifications_none_rounded,
          onTap: onNotification,
        ),
      ],
    );
  }
}

class _MarketHero extends StatelessWidget {
  const _MarketHero({required this.snapshot, required this.onTap});

  final MarketSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      color: AppColors.navy,
      padding: const EdgeInsets.fromLTRB(20, 20, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .1),
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '₿',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    snapshot.symbol,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 16,
                    ),
                  ),
                  Text(
                    '${snapshot.name} · 实时快照',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: .55),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
              const Spacer(),
              Icon(
                Icons.arrow_forward_rounded,
                color: Colors.white.withValues(alpha: .65),
              ),
            ],
          ),
          const SizedBox(height: 26),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                r'$' + formatPrice(snapshot.price),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 31,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -1,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${snapshot.changePercent > 0 ? '+' : ''}${snapshot.changePercent.toStringAsFixed(2)}%',
                  style: const TextStyle(
                    color: Color(0xFFF09C95),
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 62,
            child: MarketLineChart(
              points: snapshot.chartPoints,
              color: const Color(0xFF70C8BA),
            ),
          ),
          const SizedBox(height: 5),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '00:00',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .42),
                  fontSize: 10,
                ),
              ),
              Text(
                '现在',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: .42),
                  fontSize: 10,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AiMarketCard extends StatelessWidget {
  const _AiMarketCard({required this.snapshot, required this.onTap});

  final MarketSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SectionTitle(
            eyebrow: 'AI MARKET VIEW',
            title: 'AI 市场判断',
            trailing: StatusPill(
              label: '刚刚更新',
              icon: Icons.bolt_rounded,
              foreground: AppColors.teal,
              background: AppColors.tealSoft,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            snapshot.state,
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              const Text(
                '风险等级',
                style: TextStyle(color: AppColors.muted, fontSize: 13),
              ),
              const SizedBox(width: 10),
              RiskDots(value: snapshot.riskScore),
              const SizedBox(width: 5),
              Text(
                snapshot.riskLabel,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 16),
          Text(
            snapshot.explanation,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 17),
          const Row(
            children: [
              Text(
                '查看完整分析',
                style: TextStyle(
                  color: AppColors.teal,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(width: 5),
              Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.teal,
                size: 17,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrendRadar extends StatelessWidget {
  const _TrendRadar({required this.snapshot});

  final MarketSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          const SectionTitle(title: '趋势雷达', eyebrow: 'MULTI-TIMEFRAME'),
          const SizedBox(height: 18),
          Row(
            children: [
              ConsistencyRing(value: snapshot.consistency),
              const SizedBox(width: 20),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '趋势一致度',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 5),
                    Text(
                      '当前周期存在明显分歧，降低单一方向的确定性。',
                      style: TextStyle(
                        color: AppColors.muted,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 5),
          ...snapshot.trends.map(
            (trend) => TrendLine(trend: trend, compact: true),
          ),
        ],
      ),
    );
  }
}

class _PriceMap extends StatelessWidget {
  const _PriceMap({required this.snapshot, required this.onTap});

  final MarketSnapshot snapshot;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '关键价格地图', eyebrow: 'KEY LEVELS'),
          const SizedBox(height: 18),
          ...snapshot.levels.map(
            (level) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 72,
                    child: Text(
                      formatPrice(level.price),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: level.isCurrent
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: level.isCurrent ? AppColors.teal : AppColors.ink,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Container(
                          height: 1,
                          color: level.isCurrent
                              ? AppColors.teal
                              : AppColors.line,
                        ),
                        if (level.isCurrent)
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: AppColors.teal,
                              shape: BoxShape.circle,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  SizedBox(
                    width: 64,
                    child: Text(
                      level.label,
                      textAlign: TextAlign.right,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.background,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Text(
              '76,200 是否失守将影响 4H 回调；78,400 重新站稳后，短线多头才可能恢复。',
              style: TextStyle(fontSize: 13, height: 1.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.iconColor,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final Color iconColor;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(height: 16),
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 3),
          Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _PrincipleCard extends StatelessWidget {
  const _PrincipleCard();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.ink,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.format_quote_rounded,
            color: Color(0xFF70C8BA),
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'AI 不替你下注。\nAI 帮你发现那些让你反复亏钱的交易习惯。',
              style: TextStyle(
                color: Colors.white.withValues(alpha: .92),
                fontSize: 15,
                fontWeight: FontWeight.w600,
                height: 1.55,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
