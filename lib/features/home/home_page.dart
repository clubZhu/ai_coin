import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/position_repository.dart';
import '../../domain/market_snapshot.dart';
import '../../domain/position_record.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.snapshots,
    required this.positionRepository,
  });

  final List<MarketSnapshot> snapshots;
  final PositionRepository positionRepository;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  final _priceController = TextEditingController();
  final _scrollController = ScrollController();
  final List<PositionRecord> _records = [];

  int _selectedAsset = 0;
  PositionSide _side = PositionSide.long;
  double _stopLossPercent = 2;
  double _takeProfitPercent = 10;
  bool _loadingRecords = true;

  MarketSnapshot get _snapshot => widget.snapshots[_selectedAsset];
  double? get _entryPrice => double.tryParse(_priceController.text.trim());
  bool get _canSubmit => (_entryPrice ?? 0) > 0;

  double? get _stopLossPrice {
    final price = _entryPrice;
    if (price == null) return null;
    return _side == PositionSide.long
        ? price * (1 - _stopLossPercent / 100)
        : price * (1 + _stopLossPercent / 100);
  }

  double? get _takeProfitPrice {
    final price = _entryPrice;
    if (price == null) return null;
    return _side == PositionSide.long
        ? price * (1 + _takeProfitPercent / 100)
        : price * (1 - _takeProfitPercent / 100);
  }

  @override
  void initState() {
    super.initState();
    _fillMarketPrice();
    _loadRecords();
  }

  @override
  void dispose() {
    _priceController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _fillMarketPrice() {
    final price = _snapshot.price;
    _priceController.text = price % 1 == 0
        ? price.toStringAsFixed(0)
        : price.toStringAsFixed(1);
  }

  void _selectAsset(int index) {
    setState(() {
      _selectedAsset = index;
      _fillMarketPrice();
    });
  }

  Future<void> _loadRecords() async {
    var records = <PositionRecord>[];
    try {
      records = await widget.positionRepository.load();
    } on Exception {
      records = [];
    }
    if (!mounted) return;
    setState(() {
      _records
        ..clear()
        ..addAll(records);
      _loadingRecords = false;
    });
  }

  Future<void> _addRecord() async {
    final price = _entryPrice;
    if (price == null || price <= 0) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _records.insert(
        0,
        PositionRecord(
          id: DateTime.now().microsecondsSinceEpoch.toString(),
          symbol: _snapshot.symbol,
          side: _side,
          entryPrice: price,
          stopLossPercent: _stopLossPercent,
          takeProfitPercent: _takeProfitPercent,
          createdAt: DateTime.now(),
        ),
      );
    });
    try {
      await widget.positionRepository.save(_records);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('记录已加入，但本机保存失败，请稍后重试')));
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('${_snapshot.symbol} 开仓计划已加入记录')));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _editRecord(int index) async {
    final updated = await showModalBottomSheet<PositionRecord>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _EditRecordSheet(record: _records[index]),
    );
    if (updated == null || !mounted) return;
    setState(() => _records[index] = updated);
    try {
      await widget.positionRepository.save(_records);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('结果已更新，但本机保存失败，请稍后重试')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PageFrame(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 34),
      children: [
        const _Header(),
        const SizedBox(height: 24),
        Text('开仓计划', style: Theme.of(context).textTheme.headlineMedium),
        const SizedBox(height: 6),
        Text(
          '先算清止损与止盈价格，再确认开仓。',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: AppColors.muted),
        ),
        const SizedBox(height: 20),
        _AssetSelector(
          snapshots: widget.snapshots,
          selectedIndex: _selectedAsset,
          onSelected: _selectAsset,
        ),
        const SizedBox(height: 16),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _FieldLabel('开仓方向'),
              const SizedBox(height: 9),
              _DirectionSelector(
                side: _side,
                onChanged: (side) => setState(() => _side = side),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  const Expanded(child: _FieldLabel('开仓价格')),
                  TextButton.icon(
                    key: const ValueKey('use-market-price'),
                    onPressed: () => setState(_fillMarketPrice),
                    icon: const Icon(Icons.bolt_rounded, size: 16),
                    label: Text('使用市价 ${formatPrice(_snapshot.price)}'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.teal,
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                key: const ValueKey('entry-price-input'),
                controller: _priceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                ],
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
                decoration: InputDecoration(
                  prefixText: r'$ ',
                  suffixText: 'USDT',
                  suffixIcon: _priceController.text.isEmpty
                      ? null
                      : IconButton(
                          onPressed: () {
                            _priceController.clear();
                            setState(() {});
                          },
                          icon: const Icon(Icons.cancel_rounded, size: 18),
                        ),
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _TargetCard(
                key: const ValueKey('stop-loss-card'),
                title: '止损',
                percent: _stopLossPercent,
                price: _stopLossPrice,
                color: AppColors.red,
                softColor: AppColors.redSoft,
                directionIcon: _side == PositionSide.long
                    ? Icons.south_rounded
                    : Icons.north_rounded,
                onDecrease: () => setState(() {
                  _stopLossPercent = (_stopLossPercent - .5).clamp(.5, 50);
                }),
                onIncrease: () => setState(() {
                  _stopLossPercent = (_stopLossPercent + .5).clamp(.5, 50);
                }),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _TargetCard(
                key: const ValueKey('take-profit-card'),
                title: '止盈',
                percent: _takeProfitPercent,
                price: _takeProfitPrice,
                color: AppColors.teal,
                softColor: AppColors.tealSoft,
                directionIcon: _side == PositionSide.long
                    ? Icons.north_rounded
                    : Icons.south_rounded,
                onDecrease: () => setState(() {
                  _takeProfitPercent = (_takeProfitPercent - 1).clamp(1, 90);
                }),
                onIncrease: () => setState(() {
                  _takeProfitPercent = (_takeProfitPercent + 1).clamp(1, 90);
                }),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _PlanSummary(
          side: _side,
          stopLossPercent: _stopLossPercent,
          takeProfitPercent: _takeProfitPercent,
        ),
        const SizedBox(height: 16),
        FilledButton.icon(
          key: const ValueKey('add-position-record'),
          onPressed: _canSubmit ? _addRecord : null,
          icon: const Icon(Icons.add_task_rounded, size: 19),
          label: const Text('确认并加入开仓记录'),
        ),
        const SizedBox(height: 30),
        Row(
          children: [
            Expanded(
              child: Text(
                '开仓记录',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(100),
              ),
              child: Text(
                '${_records.length} 笔',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_loadingRecords)
          const AppCard(
            child: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_records.isEmpty)
          const _EmptyRecords()
        else
          ...List.generate(
            _records.length,
            (index) => Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _RecordCard(
                record: _records[index],
                onEdit: () => _editRecord(index),
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();

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
            letterSpacing: -.3,
          ),
        ),
        const Spacer(),
        const StatusPill(label: '计划工具', icon: Icons.calculate_outlined),
      ],
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
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
    return Row(
      children: List.generate(snapshots.length, (index) {
        final snapshot = snapshots[index];
        final selected = selectedIndex == index;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(
              right: index == snapshots.length - 1 ? 0 : 10,
            ),
            child: Material(
              color: selected ? AppColors.ink : AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              child: InkWell(
                key: ValueKey('home-asset-${snapshot.symbol}'),
                borderRadius: BorderRadius.circular(18),
                onTap: () => onSelected(index),
                child: Padding(
                  padding: const EdgeInsets.all(15),
                  child: Row(
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected
                              ? Colors.white.withValues(alpha: .12)
                              : AppColors.tealSoft,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          snapshot.symbol == 'BTC' ? '₿' : 'Ξ',
                          style: TextStyle(
                            color: selected ? Colors.white : AppColors.teal,
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              snapshot.symbol,
                              style: TextStyle(
                                color: selected ? Colors.white : AppColors.ink,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              r'$' + formatPrice(snapshot.price),
                              maxLines: 1,
                              overflow: TextOverflow.fade,
                              softWrap: false,
                              style: TextStyle(
                                color: selected
                                    ? Colors.white.withValues(alpha: .58)
                                    : AppColors.muted,
                                fontSize: 11,
                              ),
                            ),
                          ],
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
    );
  }
}

class _DirectionSelector extends StatelessWidget {
  const _DirectionSelector({required this.side, required this.onChanged});

  final PositionSide side;
  final ValueChanged<PositionSide> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Row(
        children: PositionSide.values.map((value) {
          final selected = value == side;
          final isLong = value == PositionSide.long;
          return Expanded(
            child: GestureDetector(
              key: ValueKey('direction-${value.name}'),
              onTap: () => onChanged(value),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                height: 44,
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
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      isLong ? Icons.north_rounded : Icons.south_rounded,
                      size: 17,
                      color: selected
                          ? (isLong ? AppColors.teal : AppColors.red)
                          : AppColors.muted,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isLong ? '做多' : '做空',
                      style: TextStyle(
                        color: selected ? AppColors.ink : AppColors.muted,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _TargetCard extends StatelessWidget {
  const _TargetCard({
    super.key,
    required this.title,
    required this.percent,
    required this.price,
    required this.color,
    required this.softColor,
    required this.directionIcon,
    required this.onDecrease,
    required this.onIncrease,
  });

  final String title;
  final double percent;
  final double? price;
  final Color color;
  final Color softColor;
  final IconData directionIcon;
  final VoidCallback onDecrease;
  final VoidCallback onIncrease;

  @override
  Widget build(BuildContext context) {
    final percentText = percent % 1 == 0
        ? percent.toStringAsFixed(0)
        : percent.toStringAsFixed(1);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: .14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: softColor,
                  shape: BoxShape.circle,
                ),
                child: Icon(directionIcon, color: color, size: 17),
              ),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 17),
          Row(
            children: [
              _StepButton(
                key: ValueKey('$title-decrease'),
                icon: Icons.remove_rounded,
                onTap: onDecrease,
              ),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    '$percentText%',
                    style: TextStyle(
                      color: color,
                      fontSize: 21,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              _StepButton(
                key: ValueKey('$title-increase'),
                icon: Icons.add_rounded,
                onTap: onIncrease,
              ),
            ],
          ),
          const SizedBox(height: 18),
          Text('目标价格', style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 180),
            child: Text(
              price == null ? '--' : r'$' + formatPrice(price!),
              key: ValueKey(price),
              maxLines: 1,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({super.key, required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 30,
          height: 30,
          child: Icon(icon, size: 18, color: AppColors.ink),
        ),
      ),
    );
  }
}

class _PlanSummary extends StatelessWidget {
  const _PlanSummary({
    required this.side,
    required this.stopLossPercent,
    required this.takeProfitPercent,
  });

  final PositionSide side;
  final double stopLossPercent;
  final double takeProfitPercent;

  @override
  Widget build(BuildContext context) {
    final ratio = takeProfitPercent / stopLossPercent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(
        color: AppColors.amberSoft,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.balance_rounded, color: AppColors.amber, size: 20),
          const SizedBox(width: 10),
          Text(
            '盈亏比  1 : ${ratio.toStringAsFixed(1)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const Spacer(),
          Text(
            side == PositionSide.long ? '做多计划' : '做空计划',
            style: const TextStyle(color: AppColors.muted, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords();

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
              color: AppColors.tealSoft,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.receipt_long_outlined,
              color: AppColors.teal,
            ),
          ),
          const SizedBox(height: 13),
          const Text('还没有开仓记录', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text('设置好计划后，点击上方按钮加入', style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({required this.record, required this.onEdit});

  final PositionRecord record;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final isLong = record.side == PositionSide.long;
    final resultColor = switch (record.result) {
      PositionResult.open => AppColors.blue,
      PositionResult.profit => AppColors.teal,
      PositionResult.loss => AppColors.red,
    };
    final resultLabel = switch (record.result) {
      PositionResult.open => '持仓中',
      PositionResult.profit => '盈利',
      PositionResult.loss => '亏损',
    };
    final time =
        '${record.createdAt.hour.toString().padLeft(2, '0')}:${record.createdAt.minute.toString().padLeft(2, '0')}';

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: const BoxDecoration(
                  color: AppColors.tealSoft,
                  shape: BoxShape.circle,
                ),
                child: Text(
                  record.symbol == 'BTC' ? '₿' : 'Ξ',
                  style: const TextStyle(
                    color: AppColors.teal,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 11),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        record.symbol,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 7),
                      StatusPill(
                        label: isLong ? '做多 ↑' : '做空 ↓',
                        foreground: isLong ? AppColors.teal : AppColors.red,
                        background: isLong
                            ? AppColors.tealSoft
                            : AppColors.redSoft,
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '今天 $time',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                decoration: BoxDecoration(
                  color: resultColor.withValues(alpha: .1),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Text(
                  resultLabel,
                  style: TextStyle(
                    color: resultColor,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Metric(
                  label: '开仓价格',
                  value: r'$' + formatPrice(record.entryPrice),
                ),
              ),
              Expanded(
                child: Metric(
                  label: '止损 ${_percent(record.stopLossPercent)}',
                  value: r'$' + formatPrice(record.stopLossPrice),
                  valueColor: AppColors.red,
                ),
              ),
              Expanded(
                child: Metric(
                  label: '止盈 ${_percent(record.takeProfitPercent)}',
                  value: r'$' + formatPrice(record.takeProfitPrice),
                  valueColor: AppColors.teal,
                ),
              ),
            ],
          ),
          if (record.result != PositionResult.open) ...[
            const SizedBox(height: 17),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: resultColor.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                children: [
                  Text('实际结果', style: Theme.of(context).textTheme.bodySmall),
                  const Spacer(),
                  if (record.closePrice != null) ...[
                    Text(
                      r'$' + formatPrice(record.closePrice!),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const SizedBox(width: 10),
                  ],
                  Text(
                    '${(record.realizedPercent ?? 0) > 0 ? '+' : ''}${(record.realizedPercent ?? 0).toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: resultColor,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          OutlinedButton.icon(
            key: ValueKey('edit-record-${record.id}'),
            onPressed: onEdit,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: AppColors.ink,
              side: const BorderSide(color: AppColors.line),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
            ),
            icon: const Icon(Icons.edit_outlined, size: 17),
            label: Text(
              record.result == PositionResult.open ? '记录盈亏结果' : '编辑结果',
            ),
          ),
        ],
      ),
    );
  }

  static String _percent(double value) {
    final text = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text%';
  }
}

class _EditRecordSheet extends StatefulWidget {
  const _EditRecordSheet({required this.record});

  final PositionRecord record;

  @override
  State<_EditRecordSheet> createState() => _EditRecordSheetState();
}

class _EditRecordSheetState extends State<_EditRecordSheet> {
  late PositionResult _result;
  late final TextEditingController _percentController;
  late final TextEditingController _closePriceController;

  @override
  void initState() {
    super.initState();
    _result = widget.record.result;
    _percentController = TextEditingController(
      text: widget.record.realizedPercent?.abs().toStringAsFixed(1) ?? '',
    );
    _closePriceController = TextEditingController(
      text: widget.record.closePrice == null
          ? ''
          : widget.record.closePrice!.toStringAsFixed(1),
    );
  }

  @override
  void dispose() {
    _percentController.dispose();
    _closePriceController.dispose();
    super.dispose();
  }

  void _selectResult(PositionResult result) {
    setState(() {
      _result = result;
      if (result == PositionResult.profit && _percentController.text.isEmpty) {
        _percentController.text = widget.record.takeProfitPercent
            .toStringAsFixed(1);
      } else if (result == PositionResult.loss &&
          _percentController.text.isEmpty) {
        _percentController.text = widget.record.stopLossPercent.toStringAsFixed(
          1,
        );
      }
    });
  }

  void _save() {
    if (_result == PositionResult.open) {
      Navigator.of(context).pop(
        widget.record.copyWith(
          result: PositionResult.open,
          clearClosePrice: true,
          clearRealizedPercent: true,
        ),
      );
      return;
    }
    final rawPercent = double.tryParse(_percentController.text) ?? 0;
    final signedPercent = _result == PositionResult.loss
        ? -rawPercent.abs()
        : rawPercent.abs();
    Navigator.of(context).pop(
      widget.record.copyWith(
        result: _result,
        realizedPercent: signedPercent,
        closePrice: double.tryParse(_closePriceController.text),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 24 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              Text('编辑交易结果', style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 5),
              Text(
                '${widget.record.symbol} · ${widget.record.side == PositionSide.long ? '做多' : '做空'} · 开仓 ${formatPrice(widget.record.entryPrice)}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 20),
              const _FieldLabel('当前结果'),
              const SizedBox(height: 9),
              Row(
                children: [
                  _ResultOption(
                    key: const ValueKey('result-open'),
                    label: '持仓中',
                    selected: _result == PositionResult.open,
                    color: AppColors.blue,
                    onTap: () => _selectResult(PositionResult.open),
                  ),
                  const SizedBox(width: 8),
                  _ResultOption(
                    key: const ValueKey('result-profit'),
                    label: '盈利',
                    selected: _result == PositionResult.profit,
                    color: AppColors.teal,
                    onTap: () => _selectResult(PositionResult.profit),
                  ),
                  const SizedBox(width: 8),
                  _ResultOption(
                    key: const ValueKey('result-loss'),
                    label: '亏损',
                    selected: _result == PositionResult.loss,
                    color: AppColors.red,
                    onTap: () => _selectResult(PositionResult.loss),
                  ),
                ],
              ),
              if (_result != PositionResult.open) ...[
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: _SheetNumberField(
                        fieldKey: const ValueKey('close-price-input'),
                        label: '平仓价格',
                        controller: _closePriceController,
                        prefix: r'$',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SheetNumberField(
                        fieldKey: const ValueKey('result-percent-input'),
                        label: '实际盈亏',
                        controller: _percentController,
                        suffix: '%',
                      ),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('save-record-result'),
                onPressed: _save,
                child: const Text('保存结果'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultOption extends StatelessWidget {
  const _ResultOption({
    super.key,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: .11)
                : AppColors.background,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? color.withValues(alpha: .35) : AppColors.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? color : AppColors.muted,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetNumberField extends StatelessWidget {
  const _SheetNumberField({
    required this.fieldKey,
    required this.label,
    required this.controller,
    this.prefix,
    this.suffix,
  });

  final Key fieldKey;
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
          key: fieldKey,
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
