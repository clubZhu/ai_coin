import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';

class ReviewPage extends StatelessWidget {
  const ReviewPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        title: const Text(
          '今日交易复盘',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 16),
            child: Center(
              child: Text('9月3日', style: Theme.of(context).textTheme.bodySmall),
            ),
          ),
        ],
      ),
      body: PageFrame(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 40),
        children: [
          const _SummaryHero(),
          const SizedBox(height: 16),
          const _ScoresCard(),
          const SizedBox(height: 16),
          const _BehaviorAlert(),
          const SizedBox(height: 16),
          const _LossPattern(),
          const SizedBox(height: 16),
          const _TomorrowPlan(),
        ],
      ),
    );
  }
}

class _SummaryHero extends StatelessWidget {
  const _SummaryHero();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text(
                '今日盈亏',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .09),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: const Text(
                  '已复盘',
                  style: TextStyle(
                    color: Color(0xFF8AD3C7),
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '+42.00 USDT',
            style: TextStyle(
              color: Colors.white,
              fontSize: 31,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.8,
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              _DarkMetric(label: '交易次数', value: '26'),
              _DarkDivider(),
              _DarkMetric(label: '胜率', value: '53.8%'),
              _DarkDivider(),
              _DarkMetric(label: '盈亏比', value: '1 : 1.6'),
            ],
          ),
        ],
      ),
    );
  }
}

class _DarkMetric extends StatelessWidget {
  const _DarkMetric({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: TextStyle(
              color: Colors.white.withValues(alpha: .5),
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkDivider extends StatelessWidget {
  const _DarkDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 36,
      margin: const EdgeInsets.only(right: 16),
      color: Colors.white.withValues(alpha: .12),
    );
  }
}

class _ScoresCard extends StatelessWidget {
  const _ScoresCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionTitle(title: 'AI 交易评分', eyebrow: 'NOT JUST P&L'),
              ),
              Container(
                width: 58,
                height: 58,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.amberSoft,
                  shape: BoxShape.circle,
                ),
                child: const Text(
                  '54',
                  style: TextStyle(
                    color: AppColors.amber,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const ScoreBar(label: '策略执行', value: 72),
          const ScoreBar(label: '风险控制', value: 45, color: AppColors.amber),
          const ScoreBar(label: '交易纪律', value: 38, color: AppColors.red),
          const ScoreBar(label: '情绪稳定', value: 61, color: AppColors.blue),
        ],
      ),
    );
  }
}

class _BehaviorAlert extends StatelessWidget {
  const _BehaviorAlert();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.redSoft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .7),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: const Icon(
                  Icons.psychology_alt_outlined,
                  color: AppColors.red,
                  size: 21,
                ),
              ),
              const SizedBox(width: 11),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'AI 发现一个重要问题',
                      style: TextStyle(fontWeight: FontWeight.w700),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '可能存在追回亏损行为',
                      style: TextStyle(
                        color: AppColors.red,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '你在连续两次亏损后，交易间隔从平均 24 分钟缩短至 6 分钟，并将杠杆提高了 38%。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 15),
          const Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              StatusPill(
                label: '#过度交易',
                foreground: AppColors.red,
                background: Colors.white,
              ),
              StatusPill(
                label: '#追回亏损',
                foreground: AppColors.red,
                background: Colors.white,
              ),
              StatusPill(
                label: '#高杠杆',
                foreground: AppColors.red,
                background: Colors.white,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _LossPattern extends StatelessWidget {
  const _LossPattern();

  @override
  Widget build(BuildContext context) {
    const steps = [
      ('小币暴涨', Icons.trending_up_rounded),
      ('逆势做空', Icons.swap_vert_rounded),
      ('亏损加仓', Icons.add_circle_outline_rounded),
      ('大额亏损', Icons.warning_amber_rounded),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '最大亏损模式', eyebrow: 'BEHAVIOR LOOP'),
          const SizedBox(height: 18),
          ...List.generate(steps.length, (index) {
            final last = index == steps.length - 1;
            return Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Column(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: last ? AppColors.redSoft : AppColors.background,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        steps[index].$2,
                        color: last ? AppColors.red : AppColors.ink,
                        size: 18,
                      ),
                    ),
                    if (!last)
                      Container(width: 1, height: 25, color: AppColors.line),
                  ],
                ),
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    steps[index].$1,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: last ? AppColors.red : AppColors.ink,
                    ),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}

class _TomorrowPlan extends StatelessWidget {
  const _TomorrowPlan();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '明日行动', eyebrow: 'ONE SMALL CHANGE'),
          const SizedBox(height: 17),
          const _PlanRow(number: '01', text: '连续亏损 2 次后，强制休息 30 分钟'),
          const SizedBox(height: 12),
          const _PlanRow(number: '02', text: '单笔杠杆不超过 20X'),
          const SizedBox(height: 12),
          const _PlanRow(number: '03', text: '全天交易控制在 15 笔以内'),
          const SizedBox(height: 20),
          FilledButton(
            onPressed: () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('已保存为明日交易规则'))),
            child: const Text('保存为明日规则'),
          ),
        ],
      ),
    );
  }
}

class _PlanRow extends StatelessWidget {
  const _PlanRow({required this.number, required this.text});

  final String number;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.tealSoft,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            number,
            style: const TextStyle(
              color: AppColors.teal,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
      ],
    );
  }
}
