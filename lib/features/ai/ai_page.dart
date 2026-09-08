import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/cross_exchange_repository.dart';
import '../../data/market_repository.dart';
import '../../data/position_repository.dart';
import '../../domain/cross_exchange_analysis.dart';
import '../../domain/market_snapshot.dart';
import '../../domain/position_record.dart';
import '../../domain/trading_assets.dart';

class AiPage extends StatefulWidget {
  const AiPage({
    super.key,
    required this.repository,
    required this.crossExchangeRepository,
    required this.positionRepository,
    required this.active,
    required this.onOpenRisk,
    required this.onOpenReview,
  });

  final MarketRepository repository;
  final CrossExchangeRepository crossExchangeRepository;
  final PositionRepository positionRepository;
  final bool active;
  final VoidCallback onOpenRisk;
  final VoidCallback onOpenReview;

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _controller = TextEditingController();
  final _positionController = TextEditingController(text: '100');
  final _scrollController = ScrollController();
  final List<String> _questions = [];
  List<MarketSnapshot>? _snapshots;
  List<CrossExchangeAnalysis> _crossExchangeAnalyses = const [];
  List<PositionRecord> _records = const [];
  Object? _error;
  Object? _crossExchangeError;
  bool _loading = false;
  bool _loadedOnce = false;
  int _loadGeneration = 0;
  int _selectedSignalIndex = 0;
  int _engineLeverage = 5;

  MarketSnapshot? get _snapshot {
    final snapshots = _snapshots;
    if (snapshots == null || snapshots.isEmpty) return null;
    return snapshots.first;
  }

  double get _enginePositionValue {
    final parsed = double.tryParse(_positionController.text.trim());
    return parsed != null && parsed.isFinite && parsed > 0 ? parsed : 0;
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
    if (oldWidget.repository != widget.repository) {
      _loadGeneration++;
      _loading = false;
      _loadedOnce = false;
      _snapshots = null;
      _crossExchangeAnalyses = const [];
      if (widget.active) _load(force: true);
      return;
    }
    if (widget.active && !oldWidget.active) _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    _positionController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    if (_loading && !force) return;
    final generation = ++_loadGeneration;
    final repository = widget.repository;
    final crossExchangeRepository = widget.crossExchangeRepository;
    final positionRepository = widget.positionRepository;
    setState(() {
      _loading = true;
      _error = null;
      _crossExchangeError = null;
    });
    var records = _records;
    try {
      records = await positionRepository.load();
    } on Exception {
      records = _records;
    }
    try {
      final snapshots = await repository.fetchSnapshots();
      var analyses = <CrossExchangeAnalysis>[];
      Object? crossExchangeError;
      if (snapshots.isNotEmpty) {
        try {
          analyses = await crossExchangeRepository.fetchAnalyses(snapshots);
        } on Object catch (error) {
          crossExchangeError = error;
        }
      }
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _snapshots = snapshots.isEmpty ? null : snapshots;
        _crossExchangeAnalyses = analyses;
        _crossExchangeError = crossExchangeError;
        _error = snapshots.isEmpty ? const FormatException('行情数据为空') : null;
        _records = records;
        _loadedOnce = true;
        _loading = false;
        final signalCount = _opportunitySignals(
          _snapshots ?? const [],
          _crossExchangeAnalyses,
        ).length;
        if (_selectedSignalIndex >= signalCount) _selectedSignalIndex = 0;
      });
    } on Object catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _records = records;
        _error = error;
        _loadedOnce = true;
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
    final signals = _opportunitySignals(
      _snapshots ?? const [],
      _crossExchangeAnalyses,
    );
    final selectedIndex = signals.isEmpty
        ? 0
        : math.min(_selectedSignalIndex, signals.length - 1);
    final selectedSignal = signals.isEmpty ? null : signals[selectedIndex];
    final selectedAnalysis =
        selectedSignal?.crossExchangeAnalysis ??
        (_crossExchangeAnalyses.isEmpty ? null : _crossExchangeAnalyses.first);
    final behaviorProfile = _BehaviorProfile.fromRecords(_records);
    final snapshot = _snapshot;
    return RefreshIndicator(
      onRefresh: _load,
      child: PageFrame(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          _AiHeader(
            loading: _loading,
            loadedOnce: _loadedOnce,
            onRefresh: _load,
          ),
          const SizedBox(height: 14),
          const _WorkflowStrip(),
          const SizedBox(height: 14),
          _ExchangeConsensusCard(
            analysis: selectedAnalysis,
            loading: _loading,
            error: _crossExchangeError,
          ),
          const SizedBox(height: 12),
          _OpportunityRadarCard(
            signals: signals,
            selectedIndex: selectedIndex,
            loading: _loading,
            error: _error,
            onRetry: _load,
            onSelected: (index) => setState(() => _selectedSignalIndex = index),
          ),
          if (selectedSignal != null) ...[
            const SizedBox(height: 12),
            _OpenGateCard(signal: selectedSignal, profile: behaviorProfile),
            const SizedBox(height: 12),
            _RiskEngineCard(
              signal: selectedSignal,
              positionController: _positionController,
              positionValue: _enginePositionValue,
              leverage: _engineLeverage,
              onPositionChanged: (_) => setState(() {}),
              onLeverageChanged: (value) =>
                  setState(() => _engineLeverage = value),
            ),
          ],
          const SizedBox(height: 12),
          _ReviewLoopCard(records: _records, onOpenReview: widget.onOpenReview),
          const SizedBox(height: 12),
          _BehaviorModelCard(profile: behaviorProfile),
          const SizedBox(height: 12),
          _AssistantToolsCard(
            controller: _controller,
            onAsk: _ask,
            onOpenRisk: widget.onOpenRisk,
            onOpenReview: widget.onOpenReview,
          ),
          ..._questions
              .take(2)
              .expand(
                (question) => [
                  const SizedBox(height: 12),
                  _UserBubble(question: question),
                  const SizedBox(height: 10),
                  _FollowUpAnswer(question: question, snapshot: snapshot),
                ],
              ),
        ],
      ),
    );
  }
}

List<_OpportunitySignal> _opportunitySignals(
  List<MarketSnapshot> snapshots,
  List<CrossExchangeAnalysis> analyses,
) {
  final bySymbol = {for (final analysis in analyses) analysis.symbol: analysis};
  final signals =
      snapshots
          .map(
            (snapshot) => _OpportunitySignal.fromSnapshot(
              snapshot,
              crossExchangeAnalysis: bySymbol[snapshot.symbol],
            ),
          )
          .toList()
        ..sort((a, b) => b.score.compareTo(a.score));
  return signals;
}

class _AiHeader extends StatelessWidget {
  const _AiHeader({
    required this.loading,
    required this.loadedOnce,
    required this.onRefresh,
  });

  final bool loading;
  final bool loadedOnce;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(13),
          ),
          child: const Icon(
            Icons.auto_awesome_rounded,
            color: AppColors.teal,
            size: 20,
          ),
        ),
        const SizedBox(width: 11),
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AI 工作台',
                style: TextStyle(
                  color: AppColors.ink,
                  fontSize: 26,
                  height: 1.2,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(height: 2),
              Text(
                '机会到复盘，一条线看清',
                style: TextStyle(color: AppColors.muted, fontSize: 12),
              ),
            ],
          ),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: loading ? null : onRefresh,
          visualDensity: VisualDensity.compact,
          icon: loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(
                  loadedOnce ? Icons.refresh_rounded : Icons.sync_rounded,
                  color: AppColors.muted,
                  size: 21,
                ),
        ),
      ],
    );
  }
}

class _WorkflowStrip extends StatelessWidget {
  const _WorkflowStrip();

  static const _steps = [
    ('机会雷达', Icons.radar_rounded),
    ('开仓闸门', Icons.rule_rounded),
    ('风险引擎', Icons.shield_outlined),
    ('交易复盘', Icons.fact_check_outlined),
    ('个人行为模型', Icons.psychology_alt_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        children: [
          for (var index = 0; index < _steps.length; index++) ...[
            _FlowStep(label: _steps[index].$1, icon: _steps[index].$2),
            if (index != _steps.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 5),
                child: Icon(
                  Icons.chevron_right_rounded,
                  color: AppColors.muted,
                  size: 16,
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _FlowStep extends StatelessWidget {
  const _FlowStep({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 36,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFF0F1F4)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.teal),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}

class _AiPanel extends StatelessWidget {
  const _AiPanel({
    required this.child,
    this.padding = const EdgeInsets.all(16),
  });

  final Widget child;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFF0F1F4)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0523314A),
            blurRadius: 18,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(11),
          ),
          child: Icon(icon, color: AppColors.teal, size: 18),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 15,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  height: 1.4,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
        if (trailing != null) ...[const SizedBox(width: 10), trailing!],
      ],
    );
  }
}

class _MiniPill extends StatelessWidget {
  const _MiniPill({
    required this.label,
    this.color = AppColors.teal,
    this.background,
  });

  final String label;
  final Color color;
  final Color? background;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: background ?? color.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _ExchangeConsensusCard extends StatelessWidget {
  const _ExchangeConsensusCard({
    required this.analysis,
    required this.loading,
    required this.error,
  });

  final CrossExchangeAnalysis? analysis;
  final bool loading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    final data = analysis;
    return _AiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: '跨所胜算',
            subtitle: data == null
                ? '聚合主流交易所公开行情'
                : '${data.symbol} · 历史回测校准，非收益承诺',
            icon: Icons.hub_outlined,
            trailing: loading && data == null
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _MiniPill(
                    label: data == null
                        ? '--'
                        : '有效 ${data.validExchangeCount}/${data.expectedExchangeCount}',
                    color: data != null && data.validExchangeCount >= 3
                        ? AppColors.teal
                        : AppColors.amber,
                  ),
          ),
          const SizedBox(height: 14),
          if (data == null)
            _ConsensusEmptyState(loading: loading, error: error)
          else ...[
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                children: [
                  for (var index = 0; index < data.quotes.length; index++) ...[
                    _ExchangeQuoteChip(quote: data.quotes[index]),
                    if (index != data.quotes.length - 1)
                      const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: _ConsensusMetric(
                    label: '跨所一致',
                    value: '${data.directionAgreement}%',
                  ),
                ),
                Expanded(
                  child: _ConsensusMetric(
                    label: '预计胜算',
                    value: data.hasReliableProbability
                        ? '${data.winProbability!.toStringAsFixed(0)}%'
                        : '--',
                    color: data.hasReliableProbability
                        ? AppColors.teal
                        : AppColors.muted,
                  ),
                ),
                Expanded(
                  child: _ConsensusMetric(
                    label: '回测样本',
                    value: data.sampleCount <= 0
                        ? '--'
                        : '${data.sampleCount} 笔',
                    alignment: CrossAxisAlignment.end,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _ConsensusPlanTile(
                    label: '建议止损',
                    percent: data.stopLossPercent,
                    price: data.stopLossPrice,
                    color: AppColors.red,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ConsensusPlanTile(
                    label: '建议止盈',
                    percent: data.takeProfitPercent,
                    price: data.takeProfitPrice,
                    color: AppColors.teal,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(
                  data.hasReliableProbability
                      ? Icons.verified_outlined
                      : Icons.info_outline_rounded,
                  size: 15,
                  color: data.hasReliableProbability
                      ? AppColors.teal
                      : AppColors.amber,
                ),
                const SizedBox(width: 7),
                Expanded(
                  child: Text(
                    data.hasReliableProbability
                        ? '概率区间 ${data.probabilityLow!.toStringAsFixed(0)}%–${data.probabilityHigh!.toStringAsFixed(0)}% · 数据质量 ${data.dataQualityScore} · 盈亏比 ${data.rewardRiskRatio.toStringAsFixed(1)}:1'
                        : '${data.unavailableReason ?? '胜算暂不可评估'} · 止盈止损仍按实时波动估算',
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 11,
                      height: 1.4,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConsensusEmptyState extends StatelessWidget {
  const _ConsensusEmptyState({required this.loading, required this.error});

  final bool loading;
  final Object? error;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(
            error == null ? Icons.sync_rounded : Icons.cloud_off_rounded,
            size: 19,
            color: error == null ? AppColors.muted : AppColors.red,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              loading
                  ? '正在同步 Binance、OKX、Bybit 和 Coinbase…'
                  : error == null
                  ? '暂未获得跨所数据'
                  : '跨所行情加载失败，下拉可重新获取',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 12,
                height: 1.4,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExchangeQuoteChip extends StatelessWidget {
  const _ExchangeQuoteChip({required this.quote});

  final ExchangeQuote quote;

  @override
  Widget build(BuildContext context) {
    final change = quote.changePercent;
    final color = change == null
        ? AppColors.muted
        : change >= 0
        ? AppColors.teal
        : AppColors.red;
    return Container(
      width: 124,
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: const Color(0xFFF0F1F4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  quote.exchange,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Text(
                change == null
                    ? '--'
                    : '${change >= 0 ? '+' : ''}${change.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 10,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '\$${formatPrice(quote.price)}',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConsensusMetric extends StatelessWidget {
  const _ConsensusMetric({
    required this.label,
    required this.value,
    this.color = AppColors.ink,
    this.alignment = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final Color color;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 17,
            height: 1.2,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ConsensusPlanTile extends StatelessWidget {
  const _ConsensusPlanTile({
    required this.label,
    required this.percent,
    required this.price,
    required this.color,
  });

  final String label;
  final double percent;
  final double price;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${percent.toStringAsFixed(2)}%',
            style: TextStyle(
              color: color,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              '\$${formatPrice(price)}',
              style: const TextStyle(
                color: AppColors.muted,
                fontSize: 11,
                fontWeight: FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _OpportunitySignal {
  const _OpportunitySignal({
    required this.snapshot,
    required this.side,
    required this.score,
    required this.gateScore,
    required this.stopLossPercent,
    required this.takeProfitPercent,
    required this.alignedTrendCount,
    required this.crossExchangeAnalysis,
  });

  factory _OpportunitySignal.fromSnapshot(
    MarketSnapshot snapshot, {
    CrossExchangeAnalysis? crossExchangeAnalysis,
  }) {
    final upCount = snapshot.trends
        .where((trend) => trend.direction == TrendDirection.up)
        .length;
    final downCount = snapshot.trends
        .where((trend) => trend.direction == TrendDirection.down)
        .length;
    final side = downCount > upCount ? PositionSide.short : PositionSide.long;
    final alignedTrendCount = math.max(upCount, downCount);
    final momentum = math.min(snapshot.changePercent.abs() * 4, 18).round();
    final volatilityPenalty = snapshot.riskScore * 6;
    final flatPenalty = alignedTrendCount == 0 ? 12 : 0;
    final crossExchangeAdjustment = crossExchangeAnalysis == null
        ? 0
        : ((crossExchangeAnalysis.directionAgreement - 50) * .12).round() +
              (crossExchangeAnalysis.validExchangeCount >= 3 ? 3 : -8);
    final score =
        (46 +
                snapshot.consistency * .32 +
                alignedTrendCount * 5 +
                momentum -
                volatilityPenalty -
                flatPenalty +
                crossExchangeAdjustment)
            .round()
            .clamp(0, 99)
            .toInt();
    final fallbackStopLossPercent = switch (snapshot.riskScore) {
      <= 2 => 1.8,
      3 => 2.4,
      4 => 3.2,
      _ => 4.0,
    };
    final stopLossPercent =
        crossExchangeAnalysis?.stopLossPercent ?? fallbackStopLossPercent;
    final takeProfitPercent =
        crossExchangeAnalysis?.takeProfitPercent ??
        stopLossPercent * (score >= 70 ? 2.4 : 2.0);
    final gateScore = (score * .7 + (100 - snapshot.riskScore * 14) * .3)
        .round()
        .clamp(0, 100)
        .toInt();
    return _OpportunitySignal(
      snapshot: snapshot,
      side: side,
      score: score,
      gateScore: gateScore,
      stopLossPercent: stopLossPercent,
      takeProfitPercent: takeProfitPercent,
      alignedTrendCount: alignedTrendCount,
      crossExchangeAnalysis: crossExchangeAnalysis,
    );
  }

  final MarketSnapshot snapshot;
  final PositionSide side;
  final int score;
  final int gateScore;
  final double stopLossPercent;
  final double takeProfitPercent;
  final int alignedTrendCount;
  final CrossExchangeAnalysis? crossExchangeAnalysis;

  double get entryPrice =>
      crossExchangeAnalysis?.consensusPrice ?? snapshot.price;

  double get stopLossPrice => side == PositionSide.long
      ? entryPrice * (1 - stopLossPercent / 100)
      : entryPrice * (1 + stopLossPercent / 100);

  double get takeProfitPrice => side == PositionSide.long
      ? entryPrice * (1 + takeProfitPercent / 100)
      : entryPrice * (1 - takeProfitPercent / 100);

  double get rewardRiskRatio => takeProfitPercent / stopLossPercent;

  String get sideLabel => side == PositionSide.long ? '做多观察' : '做空观察';

  String get actionLabel {
    if (score >= 75 && gateScore >= 70) return '可进闸门';
    if (score >= 60) return '等待确认';
    return '暂不追价';
  }

  Color get scoreColor {
    if (score >= 75) return AppColors.teal;
    if (score >= 60) return AppColors.amber;
    return AppColors.red;
  }
}

enum _GateState { pass, watch, block }

class _GateCheck {
  const _GateCheck({
    required this.label,
    required this.detail,
    required this.state,
  });

  final String label;
  final String detail;
  final _GateState state;
}

class _OpportunityRadarCard extends StatelessWidget {
  const _OpportunityRadarCard({
    required this.signals,
    required this.selectedIndex,
    required this.loading,
    required this.error,
    required this.onRetry,
    required this.onSelected,
  });

  final List<_OpportunitySignal> signals;
  final int selectedIndex;
  final bool loading;
  final Object? error;
  final Future<void> Function() onRetry;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final hasError = error != null && signals.isEmpty && !loading;
    return _AiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: '机会雷达',
            subtitle: '按行情结构、波动和趋势一致度排序',
            icon: Icons.radar_rounded,
            trailing: loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : _MiniPill(
                    label: signals.isEmpty ? '--' : '${signals.length} 个币种',
                  ),
          ),
          const SizedBox(height: 14),
          if (signals.isEmpty)
            _RadarEmptyState(
              loading: loading,
              hasError: hasError,
              error: error,
              onRetry: onRetry,
            )
          else
            Column(
              children: List.generate(signals.length, (index) {
                return Padding(
                  padding: EdgeInsets.only(
                    bottom: index == signals.length - 1 ? 0 : 8,
                  ),
                  child: _OpportunityRow(
                    signal: signals[index],
                    selected: index == selectedIndex,
                    onTap: () => onSelected(index),
                  ),
                );
              }),
            ),
        ],
      ),
    );
  }
}

class _RadarEmptyState extends StatelessWidget {
  const _RadarEmptyState({
    required this.loading,
    required this.hasError,
    required this.error,
    required this.onRetry,
  });

  final bool loading;
  final bool hasError;
  final Object? error;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    final title = loading
        ? '正在扫描行情'
        : hasError
        ? '行情加载失败'
        : '等待行情数据';
    final detail = loading
        ? '机会雷达会在快照到达后自动排序。'
        : hasError
        ? '$error'
        : '切到本页后会自动获取最新市场快照。';
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(13),
      ),
      child: Row(
        children: [
          Icon(
            hasError ? Icons.cloud_off_rounded : Icons.satellite_alt_rounded,
            color: hasError ? AppColors.red : AppColors.muted,
            size: 19,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: AppColors.muted,
                    fontSize: 11,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          if (hasError) ...[
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.teal,
                textStyle: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
              child: const Text('重试'),
            ),
          ],
        ],
      ),
    );
  }
}

class _OpportunityRow extends StatelessWidget {
  const _OpportunityRow({
    required this.signal,
    required this.selected,
    required this.onTap,
  });

  final _OpportunitySignal signal;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final positive = signal.snapshot.changePercent >= 0;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? AppColors.tealSoft : AppColors.background,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected
                  ? AppColors.teal.withValues(alpha: .18)
                  : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Text(
                  TradingAssets.glyph(signal.snapshot.symbol),
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          signal.snapshot.symbol,
                          style: const TextStyle(
                            color: AppColors.ink,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          signal.sideLabel,
                          style: TextStyle(
                            color: signal.side == PositionSide.long
                                ? AppColors.teal
                                : AppColors.red,
                            fontSize: 11,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${signal.snapshot.state} · 24h ${positive ? '+' : ''}${signal.snapshot.changePercent.toStringAsFixed(2)}%',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${signal.score}',
                    style: TextStyle(
                      color: signal.scoreColor,
                      fontSize: 20,
                      height: 1.1,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    signal.actionLabel,
                    style: const TextStyle(
                      color: AppColors.muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OpenGateCard extends StatelessWidget {
  const _OpenGateCard({required this.signal, required this.profile});

  final _OpportunitySignal signal;
  final _BehaviorProfile profile;

  List<_GateCheck> get _checks {
    final crossExchange = signal.crossExchangeAnalysis;
    final range = signal.snapshot.high24h - signal.snapshot.low24h;
    final positionInRange = range <= 0
        ? .5
        : (signal.snapshot.price - signal.snapshot.low24h) / range;
    final priceState = signal.side == PositionSide.long
        ? positionInRange <= .35
              ? _GateState.pass
              : positionInRange >= .78
              ? _GateState.watch
              : _GateState.pass
        : positionInRange >= .65
        ? _GateState.pass
        : positionInRange <= .22
        ? _GateState.watch
        : _GateState.pass;
    return [
      _GateCheck(
        label: '方向一致',
        detail:
            '共振 ${signal.alignedTrendCount}/4 · ${signal.snapshot.consistency}%',
        state: signal.snapshot.consistency >= 50
            ? _GateState.pass
            : _GateState.watch,
      ),
      _GateCheck(
        label: '波动可控',
        detail: '24h 波动 ${signal.snapshot.riskLabel}',
        state: signal.snapshot.riskScore <= 3
            ? _GateState.pass
            : signal.snapshot.riskScore == 4
            ? _GateState.watch
            : _GateState.block,
      ),
      _GateCheck(
        label: '位置空间',
        detail: '盈亏比 ${signal.rewardRiskRatio.toStringAsFixed(1)} : 1',
        state: priceState,
      ),
      _GateCheck(
        label: '跨所共识',
        detail: crossExchange == null
            ? '数据未到'
            : '${crossExchange.validExchangeCount}/${crossExchange.expectedExchangeCount} 家 · ${crossExchange.directionAgreement}%',
        state: crossExchange == null || crossExchange.validExchangeCount < 3
            ? _GateState.block
            : crossExchange.directionAgreement >= 67
            ? _GateState.pass
            : _GateState.watch,
      ),
      _GateCheck(
        label: '行为冷却',
        detail: profile.lossStreak >= 2
            ? '最近连续亏损 ${profile.lossStreak} 笔'
            : '纪律分 ${profile.disciplineScore}',
        state: profile.lossStreak >= 2
            ? _GateState.block
            : profile.todayCount >= 8
            ? _GateState.watch
            : _GateState.pass,
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final checks = _checks;
    final blocked = checks
        .where((check) => check.state == _GateState.block)
        .length;
    final watching = checks
        .where((check) => check.state == _GateState.watch)
        .length;
    final gateColor = blocked > 0
        ? AppColors.red
        : watching > 0
        ? AppColors.amber
        : AppColors.teal;
    final gateLabel = blocked > 0
        ? '暂不开仓'
        : watching > 0
        ? '小仓观察'
        : '允许计划';
    return _AiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: '开仓闸门',
            subtitle: '${signal.snapshot.symbol} · ${signal.sideLabel}',
            icon: Icons.rule_rounded,
            trailing: _MiniPill(label: gateLabel, color: gateColor),
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: gateColor.withValues(alpha: .045),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Row(
              children: [
                Expanded(
                  child: _GateMetric(
                    label: '闸门分',
                    value: '${signal.gateScore}',
                    color: gateColor,
                  ),
                ),
                Expanded(
                  child: _GateMetric(
                    label: '参考开仓',
                    value: r'$' + formatPrice(signal.entryPrice),
                    color: AppColors.ink,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          ...checks.map(
            (check) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _GateCheckRow(check: check),
            ),
          ),
        ],
      ),
    );
  }
}

class _GateMetric extends StatelessWidget {
  const _GateMetric({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            height: 1.4,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 22,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _GateCheckRow extends StatelessWidget {
  const _GateCheckRow({required this.check});

  final _GateCheck check;

  @override
  Widget build(BuildContext context) {
    final color = switch (check.state) {
      _GateState.pass => AppColors.teal,
      _GateState.watch => AppColors.amber,
      _GateState.block => AppColors.red,
    };
    final icon = switch (check.state) {
      _GateState.pass => Icons.check_rounded,
      _GateState.watch => Icons.remove_rounded,
      _GateState.block => Icons.close_rounded,
    };
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: color.withValues(alpha: .08),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 15, color: color),
        ),
        const SizedBox(width: 9),
        Expanded(
          child: Text(
            check.label,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 13,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            check.detail,
            textAlign: TextAlign.right,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }
}

class _RiskEngineCard extends StatelessWidget {
  const _RiskEngineCard({
    required this.signal,
    required this.positionController,
    required this.positionValue,
    required this.leverage,
    required this.onPositionChanged,
    required this.onLeverageChanged,
  });

  final _OpportunitySignal signal;
  final TextEditingController positionController;
  final double positionValue;
  final int leverage;
  final ValueChanged<String> onPositionChanged;
  final ValueChanged<int> onLeverageChanged;

  @override
  Widget build(BuildContext context) {
    final estimatedLoss = positionValue * signal.stopLossPercent / 100;
    final estimatedProfit = positionValue * signal.takeProfitPercent / 100;
    final margin = leverage <= 0 ? 0.0 : positionValue / leverage;
    final riskScore =
        (signal.snapshot.riskScore * 12 +
                leverage * 1.3 +
                (positionValue >= 1000
                    ? 12
                    : positionValue >= 300
                    ? 6
                    : 0))
            .round()
            .clamp(0, 100)
            .toInt();
    final riskColor = riskScore >= 70
        ? AppColors.red
        : riskScore >= 45
        ? AppColors.amber
        : AppColors.teal;
    final riskLabel = riskScore >= 70
        ? '偏高'
        : riskScore >= 45
        ? '中等'
        : '可控';
    return _AiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: '风险引擎',
            subtitle: '开仓数量按已加杠杆后的实际数量计算',
            icon: Icons.shield_outlined,
            trailing: _MiniPill(label: riskLabel, color: riskColor),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _EngineNumberField(
                  controller: positionController,
                  onChanged: onPositionChanged,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _LeverageSelector(
                  value: leverage,
                  onChanged: onLeverageChanged,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _RiskTile(
                  label: '止损亏损',
                  value: positionValue <= 0 ? '--' : formatUsdt(-estimatedLoss),
                  detail:
                      '${_percent(signal.stopLossPercent)} · \$${formatPrice(signal.stopLossPrice)}',
                  color: AppColors.red,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RiskTile(
                  label: '止盈盈利',
                  value: positionValue <= 0
                      ? '--'
                      : formatUsdt(estimatedProfit),
                  detail:
                      '${_percent(signal.takeProfitPercent)} · \$${formatPrice(signal.takeProfitPrice)}',
                  color: AppColors.teal,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _InlineMeter(
                  label: '综合风险',
                  value: riskScore,
                  color: riskColor,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                margin <= 0 ? '保证金 --' : '保证金约 \$${formatPrice(margin)}',
                style: const TextStyle(
                  color: AppColors.muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w400,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _EngineNumberField extends StatelessWidget {
  const _EngineNumberField({required this.controller, required this.onChanged});

  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '开仓数量',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          key: const ValueKey('ai-engine-position-amount'),
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          textInputAction: TextInputAction.done,
          onTapOutside: (_) => FocusManager.instance.primaryFocus?.unfocus(),
          inputFormatters: [
            TextInputFormatter.withFunction((oldValue, newValue) {
              return RegExp(r'^\d*\.?\d*$').hasMatch(newValue.text)
                  ? newValue
                  : oldValue;
            }),
          ],
          onChanged: onChanged,
          style: const TextStyle(
            color: AppColors.ink,
            fontSize: 16,
            height: 1.25,
            fontWeight: FontWeight.w500,
          ),
          decoration: const InputDecoration(
            suffixText: 'USDT',
            isDense: true,
            fillColor: Color(0xFFFAFBFC),
            contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(13)),
              borderSide: BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(13)),
              borderSide: BorderSide(color: AppColors.teal),
            ),
          ),
        ),
      ],
    );
  }
}

class _LeverageSelector extends StatelessWidget {
  const _LeverageSelector({required this.value, required this.onChanged});

  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    const options = [3, 5, 10, 20];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '杠杆',
          style: TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          height: 48,
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: const Color(0xFFFAFBFC),
            borderRadius: BorderRadius.circular(13),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(
            children: [
              for (final option in options)
                Expanded(
                  child: GestureDetector(
                    onTap: () => onChanged(option),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: value == option
                            ? AppColors.tealSoft
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        '${option}X',
                        style: TextStyle(
                          color: value == option
                              ? AppColors.teal
                              : AppColors.muted,
                          fontSize: 12,
                          fontWeight: value == option
                              ? FontWeight.w600
                              : FontWeight.w400,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RiskTile extends StatelessWidget {
  const _RiskTile({
    required this.label,
    required this.value,
    required this.detail,
    required this.color,
  });

  final String label;
  final String value;
  final String detail;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
          const SizedBox(height: 5),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              style: TextStyle(
                color: color,
                fontSize: 22,
                height: 1.2,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 5),
          Text(
            detail,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 11,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _InlineMeter extends StatelessWidget {
  const _InlineMeter({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: LinearProgressIndicator(
              value: value / 100,
              minHeight: 6,
              color: color,
              backgroundColor: AppColors.line,
            ),
          ),
        ),
        const SizedBox(width: 9),
        Text(
          '$value',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ReviewLoopCard extends StatelessWidget {
  const _ReviewLoopCard({required this.records, required this.onOpenReview});

  final List<PositionRecord> records;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    final closed = records
        .where((record) => record.result != PositionResult.open)
        .toList();
    final openCount = records
        .where((record) => record.result == PositionResult.open)
        .length;
    final wins = closed
        .where((record) => record.result == PositionResult.profit)
        .length;
    final realized = closed.fold<double>(
      0,
      (total, record) => total + (record.realizedAmount ?? 0),
    );
    final winRate = closed.isEmpty ? null : wins * 100 / closed.length;
    return _AiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: '交易复盘',
            subtitle: '从已记录交易里提炼实际结果',
            icon: Icons.fact_check_outlined,
            trailing: _MiniPill(label: '持仓 $openCount'),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ReviewMetric(label: '已结算', value: '${closed.length} 笔'),
              ),
              Expanded(
                child: _ReviewMetric(
                  label: '实际盈亏',
                  value: closed.isEmpty ? '--' : formatUsdt(realized),
                  color: realized < 0 ? AppColors.red : AppColors.teal,
                ),
              ),
              Expanded(
                child: _ReviewMetric(
                  label: '胜率',
                  value: winRate == null
                      ? '--'
                      : '${winRate.toStringAsFixed(0)}%',
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          TextButton.icon(
            onPressed: onOpenReview,
            style: TextButton.styleFrom(
              minimumSize: const Size.fromHeight(36),
              foregroundColor: AppColors.teal,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              textStyle: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            icon: const Icon(Icons.arrow_forward_rounded, size: 15),
            label: const Text('打开完整复盘'),
          ),
        ],
      ),
    );
  }
}

class _ReviewMetric extends StatelessWidget {
  const _ReviewMetric({
    required this.label,
    required this.value,
    this.color = AppColors.ink,
    this.alignment = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final Color color;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: AppColors.muted,
            fontSize: 11,
            fontWeight: FontWeight.w400,
          ),
        ),
        const SizedBox(height: 5),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment == CrossAxisAlignment.end
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 16,
              height: 1.25,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _BehaviorProfile {
  const _BehaviorProfile({
    required this.closedCount,
    required this.todayCount,
    required this.lossStreak,
    required this.averageLeverage,
    required this.favoriteSymbol,
    required this.disciplineScore,
    required this.primaryLabel,
    required this.suggestion,
    required this.traits,
  });

  factory _BehaviorProfile.fromRecords(List<PositionRecord> records) {
    final sorted = [...records]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    final closed = sorted
        .where((record) => record.result != PositionResult.open)
        .toList();
    final today = DateTime.now();
    final todayCount = sorted.where((record) {
      final date = record.createdAt.toLocal();
      return date.year == today.year &&
          date.month == today.month &&
          date.day == today.day;
    }).length;
    var lossStreak = 0;
    for (final record in closed) {
      if (record.result != PositionResult.loss) break;
      lossStreak++;
    }
    final wins = closed
        .where((record) => record.result == PositionResult.profit)
        .length;
    final winRate = closed.isEmpty ? 0.0 : wins * 100 / closed.length;
    final averageLeverage = records.isEmpty
        ? 0.0
        : records.fold<double>(0, (total, record) => total + record.leverage) /
              records.length;
    final counts = <String, int>{};
    for (final record in records) {
      counts.update(record.symbol, (value) => value + 1, ifAbsent: () => 1);
    }
    final favoriteSymbol = counts.isEmpty
        ? '--'
        : counts.entries
              .reduce((best, item) => item.value > best.value ? item : best)
              .key;
    var score = closed.isEmpty ? 62 : 72;
    if (winRate >= 55) score += 8;
    if (winRate < 40 && closed.length >= 3) score -= 10;
    if (averageLeverage >= 50) {
      score -= 24;
    } else if (averageLeverage >= 20) {
      score -= 12;
    }
    if (lossStreak >= 2) score -= 16;
    if (todayCount >= 8) score -= 10;
    score = score.clamp(0, 100).toInt();
    final traits = [
      _BehaviorTrait(
        label: '杠杆倾向',
        value: averageLeverage >= 20 ? 72 : 38,
        color: averageLeverage >= 20 ? AppColors.amber : AppColors.teal,
      ),
      _BehaviorTrait(
        label: '连续亏损',
        value: math.min(lossStreak * 32, 100),
        color: lossStreak >= 2 ? AppColors.red : AppColors.teal,
      ),
      _BehaviorTrait(
        label: '交易频率',
        value: math.min(todayCount * 12, 100),
        color: todayCount >= 8 ? AppColors.amber : AppColors.teal,
      ),
    ];
    final primaryLabel = records.isEmpty
        ? '等待样本'
        : lossStreak >= 2
        ? '需要冷却'
        : averageLeverage >= 20
        ? '杠杆偏高'
        : '相对稳定';
    final suggestion = records.isEmpty
        ? '先积累几笔真实记录，模型会开始识别你的交易习惯。'
        : lossStreak >= 2
        ? '最近连续亏损，下一笔交易建议先降低仓位并延长观察时间。'
        : averageLeverage >= 20
        ? '平均杠杆偏高，先把默认杠杆压回 5X 到 10X 区间。'
        : '当前行为结构较稳定，继续保持先写计划再记录结果。';
    return _BehaviorProfile(
      closedCount: closed.length,
      todayCount: todayCount,
      lossStreak: lossStreak,
      averageLeverage: averageLeverage,
      favoriteSymbol: favoriteSymbol,
      disciplineScore: score,
      primaryLabel: primaryLabel,
      suggestion: suggestion,
      traits: traits,
    );
  }

  final int closedCount;
  final int todayCount;
  final int lossStreak;
  final double averageLeverage;
  final String favoriteSymbol;
  final int disciplineScore;
  final String primaryLabel;
  final String suggestion;
  final List<_BehaviorTrait> traits;
}

class _BehaviorTrait {
  const _BehaviorTrait({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;
}

class _BehaviorModelCard extends StatelessWidget {
  const _BehaviorModelCard({required this.profile});

  final _BehaviorProfile profile;

  @override
  Widget build(BuildContext context) {
    final scoreColor = profile.disciplineScore >= 70
        ? AppColors.teal
        : profile.disciplineScore >= 45
        ? AppColors.amber
        : AppColors.red;
    return _AiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            title: '个人行为模型',
            subtitle: '用记录识别你的交易习惯',
            icon: Icons.psychology_alt_outlined,
            trailing: _MiniPill(label: profile.primaryLabel, color: scoreColor),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ReviewMetric(
                  label: '纪律分',
                  value: '${profile.disciplineScore}',
                  color: scoreColor,
                ),
              ),
              Expanded(
                child: _ReviewMetric(
                  label: '偏好币种',
                  value: profile.favoriteSymbol,
                ),
              ),
              Expanded(
                child: _ReviewMetric(
                  label: '平均杠杆',
                  value: profile.averageLeverage == 0
                      ? '--'
                      : '${profile.averageLeverage.toStringAsFixed(0)}X',
                  alignment: CrossAxisAlignment.end,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...profile.traits.map(
            (trait) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: _InlineMeter(
                label: trait.label,
                value: trait.value,
                color: trait.color,
              ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            profile.suggestion,
            style: const TextStyle(
              color: AppColors.muted,
              fontSize: 12,
              height: 1.45,
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantToolsCard extends StatelessWidget {
  const _AssistantToolsCard({
    required this.controller,
    required this.onAsk,
    required this.onOpenRisk,
    required this.onOpenReview,
  });

  final TextEditingController controller;
  final ValueChanged<String> onAsk;
  final VoidCallback onOpenRisk;
  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    return _AiPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionHeader(
            title: '辅助工具',
            subtitle: '继续追问行情，也可以进入单项工具',
            icon: Icons.chat_bubble_outline_rounded,
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ['现在属于回调还是反转？', 'BTC 支撑在哪里？', '4小时趋势怎么样？']
                .map(
                  (question) => ActionChip(
                    label: Text(question),
                    labelStyle: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w400,
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    onPressed: () => onAsk(question),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _ToolLinkTile(
                  title: '仓位体检',
                  subtitle: '单项工具',
                  icon: Icons.shield_outlined,
                  onTap: onOpenRisk,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _ToolLinkTile(
                  title: '交易复盘',
                  subtitle: '完整页',
                  icon: Icons.fact_check_outlined,
                  onTap: onOpenReview,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _Composer(controller: controller, onSend: onAsk),
        ],
      ),
    );
  }
}

class _ToolLinkTile extends StatelessWidget {
  const _ToolLinkTile({
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
    return Material(
      color: AppColors.background,
      borderRadius: BorderRadius.circular(13),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(13),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(icon, color: AppColors.teal, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      subtitle,
                      style: const TextStyle(
                        color: AppColors.muted,
                        fontSize: 10,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _percent(double value) {
  final text = value % 1 == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text%';
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
          (a, b) =>
              below ? b.price.compareTo(a.price) : a.price.compareTo(b.price),
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
                Icon(
                  Icons.satellite_alt_outlined,
                  size: 18,
                  color: AppColors.muted,
                ),
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
              Expanded(
                child: Metric(label: '市场状态', value: stateWord),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...snapshot.trends.map(
            (trend) => TrendLine(trend: trend, compact: true),
          ),
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
