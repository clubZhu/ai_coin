import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../domain/trading_assets.dart';

class RiskPage extends StatefulWidget {
  const RiskPage({super.key});

  @override
  State<RiskPage> createState() => _RiskPageState();
}

class _RiskPageState extends State<RiskPage> {
  final _entryController = TextEditingController(text: '77660');
  final _positionController = TextEditingController(text: '2160');
  String _symbol = 'BTC';
  bool _isLong = false;
  double _leverage = 125;
  bool _showResult = false;

  @override
  void dispose() {
    _entryController.dispose();
    _positionController.dispose();
    super.dispose();
  }

  int get _riskScore {
    final leverageRisk = (_leverage / 125 * 40).round();
    final trendConflict = _isLong ? 8 : 25;
    final levelRisk = _isLong ? 10 : 20;
    return (leverageRisk + trendConflict + levelRisk + 10).clamp(0, 100);
  }

  String get _riskLabel {
    if (_riskScore >= 85) return '极高';
    if (_riskScore >= 65) return '高';
    if (_riskScore >= 40) return '中等';
    return '较低';
  }

  Color get _riskColor {
    if (_riskScore >= 85) return AppColors.red;
    if (_riskScore >= 65) return AppColors.amber;
    return AppColors.teal;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        title: const Text(
          '仓位风险体检',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: PageFrame(
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 40),
        children: [
          Text(
            '下单前花 10 秒，看清这笔交易的风险来源。',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
          ),
          const SizedBox(height: 20),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SectionTitle(title: '仓位信息', eyebrow: 'POSITION'),
                const SizedBox(height: 20),
                const _FieldLabel('交易品种'),
                const SizedBox(height: 8),
                _ChoiceBar(
                  labels: TradingAssets.symbols,
                  selectedIndex: TradingAssets.symbols.indexOf(_symbol),
                  onChanged: (index) => setState(() {
                    _symbol = TradingAssets.symbols[index];
                    _showResult = false;
                  }),
                ),
                const SizedBox(height: 18),
                const _FieldLabel('方向'),
                const SizedBox(height: 8),
                _ChoiceBar(
                  labels: const ['做多', '做空'],
                  selectedIndex: _isLong ? 0 : 1,
                  onChanged: (index) => setState(() {
                    _isLong = index == 0;
                    _showResult = false;
                  }),
                ),
                const SizedBox(height: 18),
                Row(
                  children: [
                    Expanded(
                      child: _NumberField(
                        label: '开仓价格',
                        prefix: r'$',
                        controller: _entryController,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _NumberField(
                        label: '仓位',
                        suffix: 'USDT',
                        controller: _positionController,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    const Expanded(child: _FieldLabel('杠杆倍数')),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 11,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: _leverage >= 50
                            ? AppColors.redSoft
                            : AppColors.tealSoft,
                        borderRadius: BorderRadius.circular(100),
                      ),
                      child: Text(
                        '${_leverage.round()}X',
                        style: TextStyle(
                          color: _leverage >= 50
                              ? AppColors.red
                              : AppColors.teal,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
                Slider(
                  key: const ValueKey('leverage-slider'),
                  value: _leverage,
                  min: 1,
                  max: 125,
                  divisions: 124,
                  activeColor: _leverage >= 50 ? AppColors.red : AppColors.teal,
                  inactiveColor: AppColors.line,
                  onChanged: (value) => setState(() {
                    _leverage = value;
                    _showResult = false;
                  }),
                ),
                const Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '1X',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                    Text(
                      '125X',
                      style: TextStyle(color: AppColors.muted, fontSize: 11),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                FilledButton.icon(
                  key: const ValueKey('analyze-risk'),
                  onPressed: () => setState(() => _showResult = true),
                  icon: const Icon(Icons.shield_outlined, size: 19),
                  label: const Text('分析这笔仓位'),
                ),
              ],
            ),
          ),
          if (_showResult) ...[
            const SizedBox(height: 16),
            _RiskResult(
              symbol: _symbol,
              isLong: _isLong,
              leverage: _leverage.round(),
              score: _riskScore,
              label: _riskLabel,
              color: _riskColor,
            ),
          ],
        ],
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.label);

  final String label;

  @override
  Widget build(BuildContext context) {
    return Text(
      label,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    );
  }
}

class _ChoiceBar extends StatelessWidget {
  const _ChoiceBar({
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = index == selectedIndex;
          return Expanded(
            child: GestureDetector(
              onTap: () => onChanged(index),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                padding: const EdgeInsets.symmetric(vertical: 11),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: selected
                      ? const [
                          BoxShadow(
                            color: Color(0x0F000000),
                            blurRadius: 8,
                            offset: Offset(0, 2),
                          ),
                        ]
                      : null,
                ),
                child: Text(
                  labels[index],
                  style: TextStyle(
                    color: selected ? AppColors.ink : AppColors.muted,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
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

class _NumberField extends StatelessWidget {
  const _NumberField({
    required this.label,
    required this.controller,
    this.prefix,
    this.suffix,
  });

  final String label;
  final TextEditingController controller;
  final String? prefix;
  final String? suffix;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _FieldLabel(label),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
          ],
          decoration: InputDecoration(prefixText: prefix, suffixText: suffix),
        ),
      ],
    );
  }
}

class _RiskResult extends StatelessWidget {
  const _RiskResult({
    required this.symbol,
    required this.isLong,
    required this.leverage,
    required this.score,
    required this.label,
    required this.color,
  });

  final String symbol;
  final bool isLong;
  final int leverage;
  final int score;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final liquidationMove = (100 / leverage).toStringAsFixed(
      leverage >= 20 ? 1 : 0,
    );
    final factors = [
      ('高杠杆', (leverage / 125 * 40).round()),
      ('逆大周期', isLong ? 8 : 25),
      ('靠近支撑', isLong ? 10 : 20),
      ('市场波动率高', 10),
    ];
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SectionTitle(title: '仓位风险', eyebrow: 'AI RISK CHECK'),
          const SizedBox(height: 20),
          Center(
            child: SizedBox(
              width: 150,
              height: 150,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox.expand(
                    child: CircularProgressIndicator(
                      value: score / 100,
                      strokeWidth: 12,
                      strokeCap: StrokeCap.round,
                      color: color,
                      backgroundColor: AppColors.line,
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$score',
                        style: TextStyle(
                          color: color,
                          fontSize: 40,
                          height: 1,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        '$label风险',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 20),
          Container(
            padding: const EdgeInsets.all(15),
            decoration: BoxDecoration(
              color: color.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '${leverage}X 杠杆意味着价格反向波动约 $liquidationMove% 就可能造成极大的保证金压力。',
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                height: 1.5,
              ),
            ),
          ),
          const SizedBox(height: 22),
          Text('风险来源', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          ...factors.map(
            (factor) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 7),
              child: Row(
                children: [
                  SizedBox(
                    width: 92,
                    child: Text(
                      factor.$1,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(20),
                      child: LinearProgressIndicator(
                        value: factor.$2 / 40,
                        minHeight: 7,
                        color: color,
                        backgroundColor: AppColors.line,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 24,
                    child: Text(
                      '+${factor.$2}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 17),
          const Divider(height: 1),
          const SizedBox(height: 17),
          Text('市场对照', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 10),
          const _MarketContext(
            period: '15M',
            state: '反弹',
            arrow: '↑',
            color: AppColors.teal,
          ),
          const _MarketContext(
            period: '4H',
            state: '回调',
            arrow: '↓',
            color: AppColors.red,
          ),
          const _MarketContext(
            period: '1D',
            state: '多头',
            arrow: '↑',
            color: AppColors.teal,
          ),
          const SizedBox(height: 14),
          Text(
            isLong
                ? '你的 $symbol 多单顺应日线方向，但高杠杆会放大短周期回调风险。'
                : '你的 $symbol 空单与日线趋势冲突，且当前位置靠近支撑，容易遭遇反弹。',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 18),
          OutlinedButton.icon(
            onPressed: () => Navigator.of(context).pop(),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(50),
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
            ),
            icon: const Icon(Icons.pause_circle_outline_rounded),
            label: const Text('先暂停，重新检查交易计划'),
          ),
        ],
      ),
    );
  }
}

class _MarketContext extends StatelessWidget {
  const _MarketContext({
    required this.period,
    required this.state,
    required this.arrow,
    required this.color,
  });

  final String period;
  final String state;
  final String arrow;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        children: [
          SizedBox(
            width: 50,
            child: Text(period, style: Theme.of(context).textTheme.bodySmall),
          ),
          Expanded(
            child: Text(
              state,
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            arrow,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
