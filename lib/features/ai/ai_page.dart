import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../domain/market_snapshot.dart';

class AiPage extends StatefulWidget {
  const AiPage({
    super.key,
    required this.snapshots,
    required this.onOpenRisk,
    required this.onOpenReview,
  });

  final List<MarketSnapshot> snapshots;
  final VoidCallback onOpenRisk;
  final VoidCallback onOpenReview;

  @override
  State<AiPage> createState() => _AiPageState();
}

class _AiPageState extends State<AiPage> {
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<String> _questions = [];

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
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
    final snapshot = widget.snapshots.first;
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
        const _AssistantIntro(),
        const SizedBox(height: 14),
        _AnalysisCard(snapshot: snapshot),
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

class _AssistantIntro extends StatelessWidget {
  const _AssistantIntro();

  @override
  Widget build(BuildContext context) {
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
              '早上好。我已整理最新的 BTC 市场快照。先看结构，再决定是否需要承担风险。',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
      ],
    );
  }
}

class _AnalysisCard extends StatelessWidget {
  const _AnalysisCard({required this.snapshot});

  final MarketSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
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
                child: Metric(label: '市场状态', value: '震荡偏弱'),
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Divider(height: 1),
          const SizedBox(height: 8),
          ...snapshot.trends
              .skip(1)
              .map((trend) => TrendLine(trend: trend, compact: true)),
          const SizedBox(height: 8),
          const Divider(height: 1),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Metric(
                  label: '关键支撑',
                  value: r'$76,200',
                  valueColor: AppColors.teal,
                ),
              ),
              Expanded(
                child: Metric(
                  label: '关键压力',
                  value: r'$78,400',
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
            child: const Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  color: AppColors.amber,
                  size: 19,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '风险：15M 与 4H 方向分歧，短线反弹不等于回调已经结束。',
                    style: TextStyle(fontSize: 12, height: 1.45),
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
  final MarketSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final lower = question.toLowerCase();
    late final String title;
    late final String answer;
    late final String tag;
    if (lower.contains('支撑')) {
      title = '关键支撑判断';
      answer = '第一观察位是 76,200–76,600。若 4H 收盘有效跌破，下一观察位在 75,300；触及支撑不代表必须做多。';
      tag = r'$76,200';
    } else if (lower.contains('4小时') || lower.contains('4h')) {
      title = '4H 结构';
      answer = '4H 仍处于从前高回落后的调整段，价格尚未重新站稳 78,400，因此当前更适合定义为回调中的震荡。';
      tag = '回调 ↓';
    } else if (lower.contains('波动') || lower.contains('为什么')) {
      title = '波动来源';
      answer = '短周期成交量放大，同时多周期方向分歧。临近关键支撑时，多空换手会放大盘中波动。';
      tag = 'ATR 偏高';
    } else {
      title = '回调 vs. 反转';
      answer = '目前更接近 4H 回调，而不是日线反转。只有关键支撑失守、日线结构转弱后，反转风险才会明显上升。';
      tag = snapshot.state;
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
