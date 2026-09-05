import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/app_theme.dart';
import '../../core/ui.dart';
import '../../data/live_price_service.dart';
import '../../data/position_repository.dart';
import '../../domain/position_record.dart';

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
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 19),
        ),
        title: const Text(
          '开仓记录',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
      ),
      body: PageFrame(
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 34),
        children: [
          Row(
            children: [
              Text(
                _loadingRecords ? '加载中…' : '共 ${_records.length} 笔',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (totalUnrealized != null) ...[
                const SizedBox(width: 10),
                const Text('浮动', style: TextStyle(color: AppColors.muted)),
                const SizedBox(width: 4),
                Text(
                  formatUsdt(totalUnrealized),
                  style: TextStyle(
                    color: totalUnrealized < 0 ? AppColors.red : AppColors.teal,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              const Spacer(),
              _RecordFilter(
                value: _recordFilter,
                onChanged: (value) => setState(() => _recordFilter = value),
              ),
            ],
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
                  onEdit: () => _editRecord(
                    _records.indexWhere(
                      (record) => record.id == visibleRecords[index].id,
                    ),
                  ),
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
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(22),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0A23314A),
            blurRadius: 24,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _RecordFilter extends StatelessWidget {
  const _RecordFilter({required this.value, required this.onChanged});

  final _RecordFilterValue value;
  final ValueChanged<_RecordFilterValue> onChanged;

  @override
  Widget build(BuildContext context) {
    final label = switch (value) {
      _RecordFilterValue.all => '全部',
      _RecordFilterValue.open => '持仓',
      _RecordFilterValue.profit => '盈利',
      _RecordFilterValue.loss => '亏损',
    };
    return PopupMenuButton<_RecordFilterValue>(
      key: const ValueKey('record-filter'),
      initialValue: value,
      onSelected: onChanged,
      color: AppColors.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      itemBuilder: (context) => const [
        PopupMenuItem(value: _RecordFilterValue.all, child: Text('全部')),
        PopupMenuItem(value: _RecordFilterValue.open, child: Text('持仓')),
        PopupMenuItem(value: _RecordFilterValue.profit, child: Text('盈利')),
        PopupMenuItem(value: _RecordFilterValue.loss, child: Text('亏损')),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 10),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(
              color: Color(0x0A23314A),
              blurRadius: 18,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 7),
            const Icon(
              Icons.keyboard_arrow_down_rounded,
              color: AppColors.muted,
              size: 19,
            ),
          ],
        ),
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
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Column(
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(
                  Icons.assignment_outlined,
                  color: Color(0xFFC8D0E2),
                  size: 46,
                ),
                Positioned(
                  left: -8,
                  top: 2,
                  child: Icon(
                    Icons.add_rounded,
                    color: AppColors.teal.withValues(alpha: .28),
                    size: 17,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              filtered ? '没有符合条件的记录' : '暂无开仓记录',
              style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 7),
            Text(
              filtered ? '切换筛选条件查看其他记录' : '回到首页添加第一笔开仓记录，开始追踪你的交易。',
              style: Theme.of(context).textTheme.bodySmall,
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
    required this.onEdit,
    this.currentPrice,
  });

  final PositionRecord record;
  final VoidCallback onEdit;
  final double? currentPrice;

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

    return _RecordPanel(
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
                    fontSize: 19,
                    fontWeight: FontWeight.w600,
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
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
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
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            '开仓 \$${formatPrice(record.entryPrice)}  ·  ${formatPrice(record.positionAmount)} USDT  ·  ${record.leverage}X',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 14),
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
              Container(width: 1, height: 46, color: AppColors.line),
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
          if (record.result == PositionResult.open) ...[
            const SizedBox(height: 17),
            _UnrealizedSection(record: record, currentPrice: currentPrice),
          ] else ...[
            const SizedBox(height: 17),
            Container(
              padding: const EdgeInsets.all(13),
              decoration: BoxDecoration(
                color: resultColor.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Text(
                        '实际结果',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      Text(
                        formatUsdt(record.realizedAmount ?? 0),
                        style: TextStyle(
                          color: resultColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      Text(
                        '平仓价格',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      const Spacer(),
                      if (record.closePrice != null)
                        Text(
                          r'$' + formatPrice(record.closePrice!),
                          style: const TextStyle(fontSize: 12),
                        ),
                      const SizedBox(width: 10),
                      Text(
                        '${(record.realizedPercent ?? 0) > 0 ? '+' : ''}${(record.realizedPercent ?? 0).toStringAsFixed(1)}%',
                        style: TextStyle(
                          color: resultColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
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

class _UnrealizedSection extends StatelessWidget {
  const _UnrealizedSection({required this.record, this.currentPrice});

  final PositionRecord record;
  final double? currentPrice;

  @override
  Widget build(BuildContext context) {
    final amount = currentPrice == null
        ? null
        : record.unrealizedAmount(currentPrice!);
    final percent = currentPrice == null
        ? null
        : record.unrealizedPercent(currentPrice!);
    final color = amount != null && amount < 0 ? AppColors.red : AppColors.teal;
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Text('浮动盈亏', style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(
                amount == null ? '--' : formatUsdt(amount),
                style: TextStyle(
                  color: color,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Row(
            children: [
              Text('当前价格', style: Theme.of(context).textTheme.bodySmall),
              const Spacer(),
              Text(
                currentPrice == null ? '--' : r'$' + formatPrice(currentPrice!),
                style: const TextStyle(fontSize: 12),
              ),
              const SizedBox(width: 10),
              Text(
                percent == null
                    ? '--'
                    : '${percent > 0 ? '+' : ''}${percent.toStringAsFixed(1)}%',
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
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
        Text(label, style: Theme.of(context).textTheme.bodySmall),
        const SizedBox(height: 3),
        Text(
          formatUsdt(amount),
          style: TextStyle(
            color: color,
            fontSize: 15,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          '\$${formatPrice(price)}',
          style: const TextStyle(color: AppColors.muted, fontSize: 11),
        ),
      ],
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
              const FieldLabel('当前结果'),
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
        FieldLabel(label),
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
