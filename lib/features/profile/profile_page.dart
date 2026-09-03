import 'package:flutter/material.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';

class ProfilePage extends StatefulWidget {
  const ProfilePage({super.key, required this.onOpenReview});

  final VoidCallback onOpenReview;

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final List<(String, bool)> _rules = [
    ('不交易小币', true),
    ('不亏损加仓', true),
    ('连续亏损 3 次停止交易', true),
    ('每笔必须有交易理由', true),
    ('不因为“涨太多”做空', false),
  ];

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      children: [
        Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: const BoxDecoration(
                color: AppColors.ink,
                shape: BoxShape.circle,
              ),
              child: const Text(
                'T',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('我的交易系统', style: Theme.of(context).textTheme.titleLarge),
                  Text(
                    '已持续记录 86 天',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            RoundIconButton(
              icon: Icons.settings_outlined,
              onTap: () => ScaffoldMessenger.of(
                context,
              ).showSnackBar(const SnackBar(content: Text('设置功能即将上线'))),
            ),
          ],
        ),
        const SizedBox(height: 24),
        const _HealthCard(),
        const SizedBox(height: 16),
        _WeeklyReport(onOpenReview: widget.onOpenReview),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SectionTitle(title: '我的交易规则', eyebrow: 'DISCIPLINE SYSTEM'),
              const SizedBox(height: 10),
              ...List.generate(_rules.length, (index) {
                final rule = _rules[index];
                return Column(
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      title: Text(
                        rule.$1,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      subtitle: index == 2
                          ? const Text(
                              '今日已连续亏损 2 次',
                              style: TextStyle(
                                fontSize: 11,
                                color: AppColors.amber,
                              ),
                            )
                          : null,
                      value: rule.$2,
                      activeTrackColor: AppColors.teal,
                      onChanged: (value) =>
                          setState(() => _rules[index] = (rule.$1, value)),
                    ),
                    if (index != _rules.length - 1) const Divider(height: 1),
                  ],
                );
              }),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: () => ScaffoldMessenger.of(
                  context,
                ).showSnackBar(const SnackBar(content: Text('可在下一版本添加自定义规则'))),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                  foregroundColor: AppColors.ink,
                  side: const BorderSide(color: AppColors.line),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
                icon: const Icon(Icons.add_rounded),
                label: const Text('添加一条规则'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _AccountCard(),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Trade with Data, Not Emotion.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(letterSpacing: .5),
          ),
        ),
      ],
    );
  }
}

class _HealthCard extends StatelessWidget {
  const _HealthCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.navy,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '交易健康度',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 5),
                    const Text(
                      '68',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 42,
                        height: 1.1,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 7),
                    Text(
                      '比上周提升 6 分',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: .5),
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 74,
                height: 74,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: .07),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.favorite_outline_rounded,
                  color: Color(0xFF8AD3C7),
                  size: 29,
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          _HealthLine(label: '风险控制', value: 55, color: const Color(0xFFE1B15B)),
          _HealthLine(label: '交易频率', value: 42, color: const Color(0xFFE0807A)),
          _HealthLine(label: '策略稳定', value: 76, color: const Color(0xFF75C8B9)),
          _HealthLine(label: '交易纪律', value: 71, color: const Color(0xFF75C8B9)),
        ],
      ),
    );
  }
}

class _HealthLine extends StatelessWidget {
  const _HealthLine({
    required this.label,
    required this.value,
    required this.color,
  });

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 68,
            child: Text(
              label,
              style: TextStyle(
                color: Colors.white.withValues(alpha: .62),
                fontSize: 11,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: LinearProgressIndicator(
                value: value / 100,
                minHeight: 6,
                color: color,
                backgroundColor: Colors.white.withValues(alpha: .1),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 23,
            child: Text(
              '$value',
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyReport extends StatelessWidget {
  const _WeeklyReport({required this.onOpenReview});

  final VoidCallback onOpenReview;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onOpenReview,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: SectionTitle(title: '本周表现', eyebrow: 'WEEKLY REPORT'),
              ),
              const Icon(
                Icons.arrow_forward_rounded,
                color: AppColors.muted,
                size: 20,
              ),
            ],
          ),
          const SizedBox(height: 18),
          const Row(
            children: [
              Expanded(
                child: Metric(
                  label: '本周收益',
                  value: '+3.8%',
                  valueColor: AppColors.teal,
                ),
              ),
              Expanded(
                child: Metric(label: '交易次数', value: '82'),
              ),
              Expanded(
                child: Metric(
                  label: '最大回撤',
                  value: '-4.2%',
                  valueColor: AppColors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppColors.tealSoft,
              borderRadius: BorderRadius.circular(15),
            ),
            child: const Row(
              children: [
                Icon(
                  Icons.trending_up_rounded,
                  color: AppColors.teal,
                  size: 20,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    '小币交易减少 72%，平均杠杆正在下降。',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
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

class _AccountCard extends StatelessWidget {
  const _AccountCard();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          _SettingsRow(
            icon: Icons.account_balance_wallet_outlined,
            title: '交易账户',
            value: '演示数据',
          ),
          const Divider(height: 25),
          _SettingsRow(
            icon: Icons.history_rounded,
            title: '历史报告',
            value: '12 份',
          ),
          const Divider(height: 25),
          _SettingsRow(
            icon: Icons.security_rounded,
            title: '隐私与数据',
            value: '仅保存在本机',
          ),
        ],
      ),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  const _SettingsRow({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: AppColors.teal, size: 20),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        Text(value, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(width: 4),
        const Icon(
          Icons.chevron_right_rounded,
          color: AppColors.muted,
          size: 19,
        ),
      ],
    );
  }
}
