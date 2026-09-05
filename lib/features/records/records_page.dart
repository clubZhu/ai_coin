import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/live_price_service.dart';
import '../../data/position_repository.dart';
import '../../domain/position_record.dart';
import '../../domain/trading_assets.dart';

enum _RecordFilterValue { all, open, profit, loss }

class RecordsPage extends StatefulWidget {
  const RecordsPage({
    super.key,
    required this.positionRepository,
    this.livePriceService,
  });

  final PositionRepository positionRepository;
  final LivePriceService? livePriceService;

  @override
  State<RecordsPage> createState() => _RecordsPageState();
}

class _RecordsPageState extends State<RecordsPage> {
  final List<PositionRecord> _records = [];
  final Map<String, double> _livePrices = {};
  final Map<String, StreamSubscription<double>> _priceSubscriptions = {};

  _RecordFilterValue _recordFilter = _RecordFilterValue.all;
  bool _loadingRecords = true;
  final Set<String> _expandedRecordIds = {};

  void _toggleRecordExpanded(String id) {
    setState(() {
      if (!_expandedRecordIds.add(id)) _expandedRecordIds.remove(id);
    });
  }

  double? get _totalUnrealized {
    var total = 0.0;
    var counted = 0;
    for (final record in _records) {
      if (record.result != PositionResult.open) continue;
      final price = _livePrices[record.symbol];
      if (price == null) continue;
      final amount = record.unrealizedAmount(price);
      if (amount == null) continue;
      total += amount;
      counted++;
    }
    return counted == 0 ? null : total;
  }

  @override
  void initState() {
    super.initState();
    _loadRecords();
  }

  @override
  void dispose() {
    for (final subscription in _priceSubscriptions.values) {
      subscription.cancel();
    }
    super.dispose();
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
    _watchLivePrices();
  }

  void _watchLivePrices() {
    final service = widget.livePriceService;
    if (service == null) return;
    final symbols = _records
        .where((record) => record.result == PositionResult.open)
        .map((record) => record.symbol)
        .toSet();
    for (final symbol in _priceSubscriptions.keys.toList()) {
      if (!symbols.contains(symbol)) {
        _priceSubscriptions.remove(symbol)!.cancel();
        _livePrices.remove(symbol);
      }
    }
    for (final symbol in symbols) {
      if (_priceSubscriptions.containsKey(symbol)) continue;
      _priceSubscriptions[symbol] = service.watchPrice(symbol).listen((price) {
        if (!mounted) return;
        setState(() => _livePrices[symbol] = price);
      }, onError: (Object _) {});
    }
  }

  Future<void> _confirmDeleteRecord(PositionRecord record) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => _DeleteRecordDialog(record: record),
    );
    if (confirmed != true || !mounted) return;
    final index = _records.indexWhere((item) => item.id == record.id);
    if (index < 0) return;
    setState(() {
      _records.removeAt(index);
      _expandedRecordIds.remove(record.id);
    });
    _watchLivePrices();
    try {
      await widget.positionRepository.save(_records);
    } on Exception {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('记录已删除，但本机保存失败，请稍后重试')));
    }
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
    _watchLivePrices();
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
    final visibleRecords = switch (_recordFilter) {
      _RecordFilterValue.all => _records,
      _RecordFilterValue.open =>
        _records
            .where((record) => record.result == PositionResult.open)
            .toList(),
      _RecordFilterValue.profit =>
        _records
            .where((record) => record.result == PositionResult.profit)
            .toList(),
      _RecordFilterValue.loss =>
        _records
            .where((record) => record.result == PositionResult.loss)
            .toList(),
    };
    final totalUnrealized = _loadingRecords ? null : _totalUnrealized;
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 56,
        titleSpacing: 0,
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
        ),
        title: const Text(
          '开仓记录',
          style: TextStyle(
            color: AppColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w600,
            letterSpacing: -.3,
          ),
        ),
      ),
      body: PageFrame(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        children: [
          _RecordsOverview(
            total: _loadingRecords ? null : _records.length,
            openCount: _records
                .where((record) => record.result == PositionResult.open)
                .length,
            unrealizedAmount: totalUnrealized,
          ),
          const SizedBox(height: 14),
          _RecordFilter(
            value: _recordFilter,
            onChanged: (value) => setState(() => _recordFilter = value),
          ),
          const SizedBox(height: 14),
          if (_loadingRecords)
            const _RecordPanel(
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else if (visibleRecords.isEmpty)
            _EmptyRecords(filtered: _recordFilter != _RecordFilterValue.all)
          else
            ...List.generate(
              visibleRecords.length,
              (index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _RecordCard(
                  record: visibleRecords[index],
                  currentPrice: _livePrices[visibleRecords[index].symbol],
                  expanded: _expandedRecordIds.contains(
                    visibleRecords[index].id,
                  ),
                  onToggle: () =>
                      _toggleRecordExpanded(visibleRecords[index].id),
                  onEdit: () => _editRecord(
                    _records.indexWhere(
                      (record) => record.id == visibleRecords[index].id,
                    ),
                  ),
                  onDelete: () => _confirmDeleteRecord(visibleRecords[index]),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecordPanel extends StatelessWidget {
  const _RecordPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
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

const _recordCaptionStyle = TextStyle(
  color: AppColors.muted,
  fontSize: 11,
  height: 1.4,
  fontWeight: FontWeight.w400,
);

class _RecordsOverview extends StatelessWidget {
  const _RecordsOverview({
    required this.total,
    required this.openCount,
    required this.unrealizedAmount,
  });

  final int? total;
  final int openCount;
  final double? unrealizedAmount;

  @override
  Widget build(BuildContext context) {
    final amountColor = unrealizedAmount == null
        ? AppColors.muted
        : unrealizedAmount! < 0
        ? AppColors.red
        : AppColors.teal;
    return _RecordPanel(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  total == null ? '加载中…' : '共 $total 笔',
                  style: const TextStyle(
                    color: AppColors.ink,
                    fontSize: 15,
                    height: 1.3,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  total == null ? '持仓 --' : '持仓 $openCount 笔',
                  style: _recordCaptionStyle,
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                const Text('持仓浮动合计', style: _recordCaptionStyle),
                const SizedBox(height: 4),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    unrealizedAmount == null
                        ? '--'
                        : formatUsdt(unrealizedAmount!),
                    style: TextStyle(
                      color: amountColor,
                      fontSize: 22,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -.4,
                    ),
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

class _RecordFilter extends StatelessWidget {
  const _RecordFilter({required this.value, required this.onChanged});

  final _RecordFilterValue value;
  final ValueChanged<_RecordFilterValue> onChanged;

  @override
  Widget build(BuildContext context) {
    const labels = ['全部', '持仓', '盈利', '亏损'];
    return Container(
      key: const ValueKey('record-filter'),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFEEF0F3),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: _RecordFilterValue.values.map((option) {
          final selected = option == value;
          return Expanded(
            child: Semantics(
              button: true,
              selected: selected,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                decoration: BoxDecoration(
                  color: selected ? AppColors.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () => onChanged(option),
                    borderRadius: BorderRadius.circular(10),
                    child: SizedBox(
                      height: 36,
                      child: Center(
                        child: Text(
                          labels[option.index],
                          style: TextStyle(
                            color: selected ? AppColors.teal : AppColors.muted,
                            fontSize: 12,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _EmptyRecords extends StatelessWidget {
  const _EmptyRecords({required this.filtered});

  final bool filtered;

  @override
  Widget build(BuildContext context) {
    return _RecordPanel(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Column(
          children: [
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(18),
              ),
              child: const Icon(
                Icons.receipt_long_outlined,
                color: Color(0xFFACB8C2),
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              filtered ? '没有符合条件的记录' : '暂无开仓记录',
              style: const TextStyle(
                color: AppColors.ink,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 7),
            Text(
              filtered ? '试试其他筛选条件' : '在首页添加第一笔开仓记录',
              style: _recordCaptionStyle,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.record,
    required this.expanded,
    required this.onToggle,
    required this.onEdit,
    required this.onDelete,
    this.currentPrice,
  });

  final PositionRecord record;
  final bool expanded;
  final VoidCallback onToggle;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final double? currentPrice;

  @override
  Widget build(BuildContext context) {
    final isLong = record.side == PositionSide.long;
    final isOpen = record.result == PositionResult.open;
    final sideColor = isLong ? AppColors.teal : AppColors.red;
    final resultColor = switch (record.result) {
      PositionResult.open => AppColors.muted,
      PositionResult.profit => AppColors.teal,
      PositionResult.loss => AppColors.red,
    };
    final resultLabel = switch (record.result) {
      PositionResult.open => '持仓中',
      PositionResult.profit => '盈利',
      PositionResult.loss => '亏损',
    };
    final amount = isOpen
        ? (currentPrice == null ? null : record.unrealizedAmount(currentPrice!))
        : record.realizedAmount;
    final percent = isOpen
        ? (currentPrice == null
              ? null
              : record.unrealizedPercent(currentPrice!))
        : record.realizedPercent;

    return GestureDetector(
      key: ValueKey('record-card-${record.id}'),
      onTap: onToggle,
      onLongPress: onDelete,
      child: _RecordPanel(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      TradingAssets.glyph(record.symbol),
                      style: const TextStyle(
                        color: AppColors.ink,
                        fontSize: 19,
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
                            Flexible(
                              child: Text(
                                record.symbol,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.ink,
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isLong ? '做多 ↑' : '做空 ↓',
                              style: TextStyle(
                                color: sideColor,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _createdAtLabel(record.createdAt),
                          style: _recordCaptionStyle,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: resultColor.withValues(alpha: .07),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      resultLabel,
                      style: TextStyle(
                        color: resultColor,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  AnimatedRotation(
                    turns: expanded ? .5 : 0,
                    duration: const Duration(milliseconds: 180),
                    child: const Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: AppColors.muted,
                      size: 18,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              _RecordResult(
                label: isOpen ? '浮动盈亏' : '实际结果',
                amount: amount,
                percent: percent,
                priceLabel: isOpen ? '当前价格' : '平仓价格',
                price: isOpen ? currentPrice : record.closePrice,
              ),
              if (expanded) ...[
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      flex: 5,
                      child: _RecordMeta(
                        label: '开仓价格',
                        value: '\$' + formatPrice(record.entryPrice),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 5,
                      child: _RecordMeta(
                        label: '开仓数量',
                        value: '${formatPrice(record.positionAmount)} USDT',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: _RecordMeta(
                        label: '杠杆',
                        value: '${record.leverage}X',
                        alignment: CrossAxisAlignment.end,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                const Divider(height: 1, thickness: .5, color: AppColors.line),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _RecordTarget(
                        label: '止损 ${_percent(record.stopLossPercent)}',
                        amount: -record.estimatedLoss,
                        price: record.stopLossPrice,
                        color: AppColors.red,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _RecordTarget(
                        label: '止盈 ${_percent(record.takeProfitPercent)}',
                        amount: record.estimatedProfit,
                        price: record.takeProfitPrice,
                        color: AppColors.teal,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton.icon(
                    key: ValueKey('edit-record-${record.id}'),
                    onPressed: onEdit,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 36),
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
                    icon: const Icon(Icons.edit_outlined, size: 15),
                    label: Text(isOpen ? '记录盈亏结果' : '编辑结果'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static String _percent(double value) {
    final text = value % 1 == 0
        ? value.toStringAsFixed(0)
        : value.toStringAsFixed(1);
    return '$text%';
  }

  static String _createdAtLabel(DateTime createdAt) {
    final date = createdAt.toLocal();
    final now = DateTime.now();
    final time =
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    if (isToday) return '今天 $time';
    final day =
        '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}';
    return date.year == now.year ? '$day $time' : '${date.year}/$day $time';
  }
}

class _RecordMeta extends StatelessWidget {
  const _RecordMeta({
    required this.label,
    required this.value,
    this.alignment = CrossAxisAlignment.start,
  });

  final String label;
  final String value;
  final CrossAxisAlignment alignment;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: alignment,
      children: [
        Text(label, style: _recordCaptionStyle),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: alignment == CrossAxisAlignment.end
              ? Alignment.centerRight
              : Alignment.centerLeft,
          child: Text(
            value,
            style: const TextStyle(
              color: AppColors.ink,
              fontSize: 13,
              height: 1.3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ],
    );
  }
}

class _RecordResult extends StatelessWidget {
  const _RecordResult({
    required this.label,
    required this.amount,
    required this.percent,
    required this.priceLabel,
    required this.price,
  });

  final String label;
  final double? amount;
  final double? percent;
  final String priceLabel;
  final double? price;

  @override
  Widget build(BuildContext context) {
    final color = amount == null
        ? AppColors.muted
        : amount! < 0
        ? AppColors.red
        : AppColors.teal;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .045),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: _recordCaptionStyle),
          const SizedBox(height: 5),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                flex: 3,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    amount == null ? '--' : formatUsdt(amount!),
                    style: TextStyle(
                      color: color,
                      fontSize: 22,
                      height: 1.2,
                      fontWeight: FontWeight.w500,
                      letterSpacing: -.4,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Align(
                  alignment: Alignment.centerRight,
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      percent == null
                          ? '--'
                          : '${percent! > 0 ? '+' : ''}${percent!.toStringAsFixed(1)}%',
                      style: TextStyle(
                        color: color,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Text(priceLabel, style: _recordCaptionStyle),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    price == null ? '--' : '\$' + formatPrice(price!),
                    style: _recordCaptionStyle.copyWith(color: AppColors.ink),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RecordTarget extends StatelessWidget {
  const _RecordTarget({
    required this.label,
    required this.amount,
    required this.price,
    required this.color,
  });

  final String label;
  final double amount;
  final double price;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _recordCaptionStyle),
        const SizedBox(height: 3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            formatUsdt(amount),
            style: TextStyle(
              color: color,
              fontSize: 15,
              height: 1.3,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
        const SizedBox(height: 2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text('\$${formatPrice(price)}', style: _recordCaptionStyle),
        ),
      ],
    );
  }
}

class _DeleteRecordDialog extends StatelessWidget {
  const _DeleteRecordDialog({required this.record});

  final PositionRecord record;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '删除这条记录？',
              style: TextStyle(
                color: AppColors.ink,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '${record.symbol} · ${record.side == PositionSide.long ? '做多' : '做空'} · '
              '开仓 \$${formatPrice(record.entryPrice)}，删除后无法恢复。',
              style: _recordCaptionStyle.copyWith(fontSize: 13),
            ),
            const SizedBox(height: 20),
            Row(
              children: [
                Expanded(
                  child: Semantics(
                    button: true,
                    child: Material(
                      color: AppColors.background,
                      borderRadius: BorderRadius.circular(13),
                      child: InkWell(
                        onTap: () => Navigator.of(context).pop(false),
                        borderRadius: BorderRadius.circular(13),
                        child: SizedBox(
                          height: 44,
                          child: Center(
                            child: Text(
                              '取消',
                              style: const TextStyle(
                                color: AppColors.muted,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Semantics(
                    button: true,
                    child: Material(
                      color: AppColors.red,
                      borderRadius: BorderRadius.circular(13),
                      child: InkWell(
                        key: const ValueKey('confirm-delete-record'),
                        onTap: () => Navigator.of(context).pop(true),
                        borderRadius: BorderRadius.circular(13),
                        child: SizedBox(
                          height: 44,
                          child: Center(
                            child: Text(
                              '删除',
                              style: const TextStyle(
                                color: AppColors.surface,
                                fontSize: 15,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
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
    );
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
  late final TextEditingController _amountController;
  late final TextEditingController _percentController;
  late final TextEditingController _closePriceController;
  double? _draftAmount;

  double? get _draftPercent {
    if (_draftAmount == null || widget.record.positionValue <= 0) return null;
    final percent = _draftAmount! / widget.record.positionValue * 100;
    return percent.isFinite ? percent : null;
  }

  bool get _canSave {
    if (_result == PositionResult.open) return true;
    if (_draftAmount == null || _draftPercent == null) return false;
    if (_closePriceController.text.isEmpty) return true;
    final price = _parseNumber(_closePriceController.text);
    return price != null && price > 0;
  }

  @override
  void initState() {
    super.initState();
    _result = widget.record.result;
    _draftAmount = widget.record.realizedAmount?.abs();
    _amountController = TextEditingController(
      text: _draftAmount == null ? '' : _editableNumber(_draftAmount!),
    );
    _percentController = TextEditingController(
      text: _draftPercent == null ? '' : _editableNumber(_draftPercent!),
    );
    _closePriceController = TextEditingController(
      text: widget.record.closePrice == null
          ? ''
          : _editableNumber(widget.record.closePrice!),
    );
  }

  @override
  void dispose() {
    _amountController.dispose();
    _percentController.dispose();
    _closePriceController.dispose();
    super.dispose();
  }

  void _selectResult(PositionResult result) {
    setState(() {
      _result = result;
      if (result != PositionResult.open &&
          _amountController.text.isEmpty &&
          _percentController.text.isEmpty) {
        final percent = result == PositionResult.profit
            ? widget.record.takeProfitPercent
            : widget.record.stopLossPercent;
        _percentController.text = _editableNumber(percent);
        _setAmountFromPercent(_percentController.text);
      }
    });
  }

  static double? _parseNumber(String text) {
    final value = double.tryParse(text);
    return value != null && value.isFinite && value >= 0 ? value : null;
  }

  static String _editableNumber(double value) {
    return value.toStringAsFixed(8).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _onAmountChanged(String text) {
    setState(() {
      _draftAmount = _parseNumber(text);
      final percent = _draftPercent;
      _percentController.text = percent == null ? '' : _editableNumber(percent);
    });
  }

  void _setAmountFromPercent(String text) {
    final percent = _parseNumber(text);
    final amount = percent == null
        ? null
        : widget.record.positionValue * (percent / 100);
    _draftAmount = amount != null && amount.isFinite && amount >= 0
        ? amount
        : null;
    _amountController.text = _draftAmount == null
        ? ''
        : _editableNumber(_draftAmount!);
  }

  void _onPercentChanged(String text) {
    setState(() => _setAmountFromPercent(text));
  }

  void _save() {
    if (!_canSave) return;
    if (_result == PositionResult.open) {
      Navigator.of(context).pop(
        widget.record.copyWith(
          result: PositionResult.open,
          clearClosePrice: true,
          clearRealizedPercent: true,
          clearRealizedAmount: true,
        ),
      );
      return;
    }
    final sign = _result == PositionResult.loss ? -1 : 1;
    Navigator.of(context).pop(
      widget.record.copyWith(
        result: _result,
        realizedPercent: _draftPercent! * sign,
        realizedAmount: _draftAmount! * sign,
        closePrice: _parseNumber(_closePriceController.text),
        clearClosePrice: _closePriceController.text.isEmpty,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(20, 12, 20, 20 + bottomInset),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
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
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      '编辑交易结果',
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 18,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    onPressed: () => Navigator.of(context).pop(),
                    visualDensity: VisualDensity.compact,
                    icon: const Icon(
                      Icons.close_rounded,
                      color: AppColors.muted,
                      size: 20,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 5),
              Text(
                '${widget.record.symbol} · ${widget.record.side == PositionSide.long ? '做多' : '做空'} · 开仓 ${formatPrice(widget.record.entryPrice)}',
                style: _recordCaptionStyle,
              ),
              const SizedBox(height: 20),
              const Text('当前结果', style: _recordCaptionStyle),
              const SizedBox(height: 9),
              Row(
                children: [
                  _ResultOption(
                    key: const ValueKey('result-open'),
                    label: '持仓中',
                    selected: _result == PositionResult.open,
                    color: AppColors.teal,
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
                        fieldKey: const ValueKey('result-amount-input'),
                        label: '实际盈亏',
                        controller: _amountController,
                        prefix: _result == PositionResult.loss ? '− ' : '+ ',
                        suffix: 'USDT',
                        onChanged: _onAmountChanged,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _SheetNumberField(
                        fieldKey: const ValueKey('result-percent-input'),
                        label: '盈亏比例',
                        controller: _percentController,
                        suffix: '%',
                        onChanged: _onPercentChanged,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                _SheetNumberField(
                  fieldKey: const ValueKey('close-price-input'),
                  label: '平仓价格（选填）',
                  controller: _closePriceController,
                  suffix: 'USDT',
                  onChanged: (_) => setState(() {}),
                ),
              ],
              const SizedBox(height: 24),
              FilledButton(
                key: const ValueKey('save-record-result'),
                onPressed: _canSave ? _save : null,
                style: FilledButton.styleFrom(
                  backgroundColor: AppColors.teal,
                  minimumSize: const Size.fromHeight(48),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(15),
                  ),
                ),
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
      child: Semantics(
        button: true,
        selected: selected,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 44,
          decoration: BoxDecoration(
            color: selected
                ? color.withValues(alpha: .07)
                : AppColors.background,
            borderRadius: BorderRadius.circular(13),
            border: Border.all(
              color: selected ? color.withValues(alpha: .18) : AppColors.line,
            ),
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onTap,
              borderRadius: BorderRadius.circular(13),
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    color: selected ? color : AppColors.muted,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
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
    this.onChanged,
  });

  final Key fieldKey;
  final String label;
  final TextEditingController controller;
  final String? prefix;
  final String? suffix;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: _recordCaptionStyle),
        const SizedBox(height: 8),
        TextField(
          key: fieldKey,
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
          decoration: InputDecoration(
            prefixText: prefix,
            suffixText: suffix,
            hintText: '--',
            isDense: true,
            fillColor: const Color(0xFFFAFBFC),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            prefixStyle: _recordCaptionStyle,
            suffixStyle: _recordCaptionStyle,
            enabledBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(13)),
              borderSide: BorderSide(color: AppColors.line),
            ),
            focusedBorder: const OutlineInputBorder(
              borderRadius: BorderRadius.all(Radius.circular(13)),
              borderSide: BorderSide(color: AppColors.teal),
            ),
          ),
        ),
      ],
    );
  }
}
