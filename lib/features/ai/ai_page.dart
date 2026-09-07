import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/market_repository.dart';
import '../../domain/market_snapshot.dart';

class AiPage extends StatefulWidget {
  const AiPage({
    super.key,
    required this.repository,
    required this.active,
    required this.onOpenRisk,
    required this.onOpenReview,
  });

  final MarketRepository repository;
  final bool active;
  final VoidCallback onOpenRisk;
  final VoidCallback onOpenReview;

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<String> _questions = [];
  List<MarketSnapshot>? _snapshots;
  Object? _error;
  bool _loading = false;

  MarketSnapshot? get _snapshot {
    final snapshots = _snapshots;
    if (snapshots == null || snapshots.isEmpty) return null;
    return snapshots.first;
  }

  @override
  void initState() {
    super.initState();
    // 页面在 IndexedStack 中常驻，首次切到该页时才拉取行情，避免启动双份请求。
    if (widget.active) _load();
  }

  @override
  void didUpdateWidget(AiPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    if (_loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snapshots = await widget.repository.fetchSnapshots();
      if (!mounted) return;
      setState(() {
        _snapshots = snapshots.isEmpty ? null : snapshots;
        _error = snapshots.isEmpty ? const FormatException('行情数据为空') : null;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  void _ask(String question) {
    final normalized = question.trim();
    if (normalized.isEmpty) return;
    setState(() {
      _questions.add(normalized);
      _controller.clear();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final snapshot = _snapshot;
    return PageFrame(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
      children: [
        Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: AppColors.ink,
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.auto_awesome_rounded,
                color: Colors.white,
                size: 21,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Trading Copilot',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const Text(
                    '分析风险，不替你下注',
                    style: TextStyle(color: AppColors.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const StatusPill(
              label: '在线',
              icon: Icons.circle,
              foreground: AppColors.teal,
            ),
          ],
        ),
        const SizedBox(height: 24),
        _AssistantIntro(snapshot: snapshot),
        const SizedBox(height: 14),
        _SnapshotSection(
          snapshot: snapshot,
          loading: _loading,
          error: _error,
          onRetry: _load,
        ),
        const SizedBox(height: 18),
        Text('你可以继续问', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['现在属于回调还是反转？', 'BTC 支撑在哪里？', '4小时趋势怎么样？', '为什么今天波动变大？']
              .map(
                (question) => ActionChip(
                  label: Text(question),
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(100),
                  ),
                  onPressed: () => _ask(question),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 18),
        ..._questions.expand(
          (question) => [
            _UserBubble(question: question),
            const SizedBox(height: 10),
            _FollowUpAnswer(question: question, snapshot: snapshot),
            const SizedBox(height: 14),
          ],
        ),
        const SizedBox(height: 4),
        Row(
          children: [
            Expanded(
              child: _ShortcutCard(
                title: '仓位体检',
                subtitle: '下单前',
                icon: Icons.shield_outlined,
                onTap: widget.onOpenRisk,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: _ShortcutCard(
                title: '交易复盘',
                subtitle: '下单后',
                icon: Icons.fact_check_outlined,
                onTap: widget.onOpenReview,
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _Composer(controller: _controller, onSend: _ask),
      ],
    );
  }
}

/// 距当前价最近的下方/上方价位，作为关键支撑与压力。
PriceLevel? _nearestLevel(MarketSnapshot snapshot, {required bool below}) {
  final candidates =
      snapshot.levels
          .where(
            (level) =>
                !level.isCurrent &&
                (below
                    ? level.price < snapshot.price
                    : level.price > snapshot.price),
          )
          .toList()
        ..sort(
          (a, b) => below ? b.price.compareTo(a.price) : a.price.compareTo(b.price),
        );
  return candidates.isEmpty ? null : candidates.first;
}

TimeframeTrend _trendFor(MarketSnapshot snapshot, String period) {
  for (final trend in snapshot.trends) {
    if (trend.period == period) return trend;
  }
  return snapshot.trends.isNotEmpty
      ? snapshot.trends.last
      : TimeframeTrend(
          period: period,
          label: '震荡',
          direction: TrendDirection.flat,
        );
}

class _AssistantIntro extends StatelessWidget {
  const _AssistantIntro({this.snapshot});

  final MarketSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final symbol = snapshot?.symbol;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: AppColors.tealSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.teal,
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.all(15),
            decoration: const BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.only(
                topRight: Radius.circular(18),
                bottomLeft: Radius.circular(18),
                bottomRight: Radius.circular(18),
              ),
            ),
            child: Text(
              '早上好。${symbol == null ? '我正在整理最新的市场快照' : '我已整理最新的 $symbol 市场快照'}。'
              '先看结构，再决定是否需要承担风险。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class _SnapshotSection extends StatelessWidget {
  const _SnapshotSection({
    required this.snapshot,
    required this.loading,
    required this.error,
    required this.onRetry,
  });

  final MarketSnapshot? snapshot;
  final bool loading;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    if (snapshot != null) return _AnalysisCard(snapshot: snapshot!);
    final failed = !loading && error != null;
    return AppCard(
      border: const Border(left: BorderSide(color: AppColors.teal, width: 3)),
      child: failed
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '行情加载失败',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  '$error',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: AppColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 10),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: const ValueKey('retry-ai'),
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded, size: 18),
                    label: const Text('重试'),
                  ),
                ),
              ],
            )
          : loading
          ? const Row(
              children: [
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
                SizedBox(width: 12),
                Text('正在获取币安实时行情…'),
              ],
            )
          : const Row(
              children: [
                Icon(Icons.satellite_alt_outlined, size: 18, color: AppColors.muted),
                SizedBox(width: 12),
                Text('进入本页后将自动加载最新行情'),
              ],
            ),
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.snapshot});

  final MarketSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final support = _nearestLevel(snapshot, below: true);
    final resistance = _nearestLevel(snapshot, below: false);
    final stateParts = snapshot.state.split('·');
    final stateWord = stateParts.length > 1
        ? stateParts.last.trim()
        : snapshot.state;
    final diverged = snapshot.consistency < 75;

    return AppCard(
      border: const Border(left: BorderSide(color: AppColors.teal, width: 3)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${snapshot.symbol} 市场分析',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const Spacer(),
              const StatusPill(label: 'AI 快照'),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Metric(
                  label: '当前价格',
                  value: r'$' + formatPrice(snapshot.price),
                ),
              ),
              Expanded(child: Metric(label: '市场状态', value: stateWord)),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...snapshot.trends.map((trend) => TrendLine(trend: trend, compact: true)),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Metric(
                  label: '关键支撑',
                  value: support == null
                      ? '--'
                      : r'$' + formatPrice(support.price),
                  valueColor: AppColors.teal,
                ),
              ),
              Expanded(
                child: Metric(
                  label: '关键压力',
                  value: resistance == null
                      ? '--'
                      : r'$' + formatPrice(resistance.price),
                  valueColor: AppColors.amber,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.amberSoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.amber,
                  size: 19,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '风险：${diverged ? '多周期方向存在分歧，' : ''}'
                    '24h 波动属${snapshot.riskLabel}水平，多周期一致度 ${snapshot.consistency}%，'
                    '先控制仓位再参与。',
                    style: const TextStyle(fontSize: 12, height: 1.45),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UserBubble extends StatelessWidget {
  const _UserBubble({required this.question});

  final String question;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        constraints: const BoxConstraints(maxWidth: 290),
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
        decoration: const BoxDecoration(
          color: AppColors.ink,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(4),
            bottomLeft: Radius.circular(18),
            bottomRight: Radius.circular(18),
          ),
        ),
        child: Text(
          question,
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
      ),
    );
  }
}

class _FollowUpAnswer extends StatelessWidget {
  const _FollowUpAnswer({required this.question, required this.snapshot});

  final String question;
  final MarketSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final current = snapshot;
    late final String title;
    late final String answer;
    late final String tag;
    if (current == null) {
      title = '快照加载中';
      answer = '最新行情还没拿到，等市场快照加载完成后再问一次吧。';
      tag = '等待数据';
    } else {
      final lower = question.toLowerCase();
      final support = _nearestLevel(current, below: true);
      if (lower.contains('支撑')) {
        title = '关键支撑判断';
        final supportPrice = support?.price ?? current.low24h;
        answer =
            '第一观察位在 ${formatPrice(supportPrice)} 附近'
            '${support == null ? '' : '（${support.label}）'}。'
            '若有效跌破，需要重新评估多头结构；触及支撑不代表必须做多。';
        tag = r'$' + formatPrice(supportPrice);
      } else if (lower.contains('4小时') || lower.contains('4h')) {
        title = '4H 结构';
        final trend = _trendFor(current, '4小时');
        answer =
            '4H 目前属于${trend.label}结构。${current.state}，'
            '多周期一致度 ${current.consistency}%。';
        tag = '${trend.label} ${trend.direction.arrow}';
      } else if (lower.contains('波动') || lower.contains('为什么')) {
        title = '波动来源';
        final rangePercent = current.price > 0
            ? (current.high24h - current.low24h) / current.price * 100
            : 0.0;
        answer =
            '24h 价格在 ${formatPrice(current.low24h)} – '
            '${formatPrice(current.high24h)} 之间，振幅约 '
            '${rangePercent.toStringAsFixed(1)}%，波动属${current.riskLabel}水平。'
            '关键位附近多空换手会放大盘中波动。';
        tag = '振幅 ${rangePercent.toStringAsFixed(1)}%';
      } else {
        title = '回调 vs. 反转';
        answer =
            '当前市场状态是「${current.state}」，多周期一致度 '
            '${current.consistency}%。方向不明确时先控制仓位，等结构明朗再加大参与。';
        tag = current.state;
      }
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: const BoxDecoration(
            color: AppColors.tealSoft,
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.teal,
            size: 16,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: AppCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ),
                    StatusPill(label: tag),
                  ],
                ),
                const SizedBox(height: 10),
                Text(answer, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ShortcutCard extends StatelessWidget {
  const _ShortcutCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(15),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 37,
            height: 37,
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: AppColors.teal, size: 19),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({required this.controller, required this.onSend});

  final TextEditingController controller;
  final ValueChanged<String> onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(5),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: AppColors.line),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('ai-input'),
              controller: controller,
              textInputAction: TextInputAction.send,
              decoration: const InputDecoration(
                hintText: '问问 BTC、ETH 或交易风险...',
                fillColor: Colors.transparent,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
              onSubmitted: onSend,
            ),
          ),
          IconButton.filled(
            key: const ValueKey('ai-send'),
            onPressed: () => onSend(controller.text),
            style: IconButton.styleFrom(
              backgroundColor: AppColors.ink,
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.arrow_upward_rounded),
          ),
        ],
      ),
    );
  }
}
