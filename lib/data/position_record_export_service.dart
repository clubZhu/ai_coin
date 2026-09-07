import 'package:flutter/services.dart';

import '../domain/position_record.dart';

abstract final class PositionRecordExportService {
  static const _channel = MethodChannel('crypto_pilot/record_export');

  static Future<void> shareCsv(List<PositionRecord> records) {
    final now = DateTime.now();
    final fileName = 'cryptopilot_records_${_fileStamp(now)}.csv';
    return _channel.invokeMethod<void>('shareCsv', {
      'title': '分享交易记录',
      'fileName': fileName,
      'content': '\uFEFF${buildCsv(records)}',
    });
  }

  static String buildCsv(List<PositionRecord> records) {
    final rows = <List<String>>[
      const [
        '开仓时间',
        '币种',
        '方向',
        '状态',
        '开仓价格(USDT)',
        '开仓数量(USDT)',
        '杠杆',
        '止损比例(%)',
        '止损价格(USDT)',
        '预计亏损(USDT)',
        '止盈比例(%)',
        '止盈价格(USDT)',
        '预计盈利(USDT)',
        '实际盈亏(USDT)',
        '盈亏比例(%)',
        '平仓价格(USDT)',
      ],
      for (final record in records)
        [
          _dateTime(record.createdAt),
          record.symbol,
          record.side == PositionSide.long ? '做多' : '做空',
          _resultLabel(record.result),
          _number(record.entryPrice),
          _number(record.positionAmount),
          '${record.leverage}X',
          _number(record.stopLossPercent, maxDecimals: 4),
          _number(record.stopLossPrice),
          _number(-record.estimatedLoss),
          _number(record.takeProfitPercent, maxDecimals: 4),
          _number(record.takeProfitPrice),
          _number(record.estimatedProfit),
          _nullableNumber(record.realizedAmount),
          _nullableNumber(record.realizedPercent, maxDecimals: 4),
          _nullableNumber(record.closePrice),
        ],
    ];
    return rows.map((row) => row.map(_csvValue).join(',')).join('\n');
  }

  static String _resultLabel(PositionResult result) {
    return switch (result) {
      PositionResult.open => '持仓中',
      PositionResult.profit => '盈利',
      PositionResult.loss => '亏损',
    };
  }

  static String _nullableNumber(double? value, {int maxDecimals = 8}) {
    return value == null ? '' : _number(value, maxDecimals: maxDecimals);
  }

  static String _number(double value, {int maxDecimals = 8}) {
    final fixed = value.toStringAsFixed(maxDecimals);
    return fixed.replaceFirst(RegExp(r'\.?0+$'), '');
  }

  static String _dateTime(DateTime value) {
    final local = value.toLocal();
    return '${local.year.toString().padLeft(4, '0')}-'
        '${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')} '
        '${local.hour.toString().padLeft(2, '0')}:'
        '${local.minute.toString().padLeft(2, '0')}:'
        '${local.second.toString().padLeft(2, '0')}';
  }

  static String _fileStamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}'
        '${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}_'
        '${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}'
        '${value.second.toString().padLeft(2, '0')}';
  }

  static String _csvValue(String value) {
    final escaped = value.replaceAll('"', '""');
    final needsQuotes =
        escaped.contains(',') ||
        escaped.contains('"') ||
        escaped.contains('\n') ||
        escaped.contains('\r');
    return needsQuotes ? '"$escaped"' : escaped;
  }
}
