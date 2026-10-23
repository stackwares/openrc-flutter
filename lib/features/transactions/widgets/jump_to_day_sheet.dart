import 'dart:async';
import 'dart:math' as math;

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:openrc/core/extensions/context_extensions.dart';
import 'package:openrc/theme/app_tokens.dart';
import 'package:openrc/widgets/adaptive_modal.dart';

/// Picks a day to open: quick picks for the usual jumps, and a calendar
/// (tap the month for years) for any day from [firstDay] to today. Tapping
/// a day opens it. Returns the picked local day, or null if dismissed.
Future<DateTime?> showJumpToDaySheet(
  BuildContext context, {
  required DateTime selectedDay,
  DateTime? firstDay,
}) {
  return showAdaptiveSheet<DateTime>(
    context: context,
    dialogMaxWidth: 420,
    builder: (_) =>
        _JumpToDaySheet(selectedDay: selectedDay, firstDay: firstDay),
  );
}

class _JumpToDaySheet extends StatefulWidget {
  const _JumpToDaySheet({required this.selectedDay, this.firstDay});

  final DateTime selectedDay;
  final DateTime? firstDay;

  @override
  State<_JumpToDaySheet> createState() => _JumpToDaySheetState();
}

class _JumpToDaySheetState extends State<_JumpToDaySheet> {
  /// Set while a year pick moves the calendar: the picker reports the new
  /// date in the same call, and that shouldn't close the sheet.
  bool _monthJustMoved = false;

  void _onDisplayedMonthChanged(DateTime _) {
    _monthJustMoved = true;
    scheduleMicrotask(() => _monthJustMoved = false);
  }

  void _onDateChanged(DateTime day) {
    if (_monthJustMoved) return;
    Navigator.of(context).pop(DateUtils.dateOnly(day));
  }

  @override
  Widget build(BuildContext context) {
    final tt = context.textTheme;
    final today = DateUtils.dateOnly(DateTime.now());
    final selected = DateUtils.dateOnly(widget.selectedDay);
    // Imported receipts can predate RevenueCat, so the floor is generous.
    final firstDay = widget.firstDay == null
        ? DateTime(2010)
        : DateUtils.dateOnly(widget.firstDay!);
    final first = [
      firstDay,
      selected,
      today,
    ].reduce((a, b) => a.isBefore(b) ? a : b);
    final initial = selected.isAfter(today) ? today : selected;
    final monthBack = DateTime(today.year, today.month - 1);
    final quickPicks = [
      ('transactions.today'.tr(), today),
      ('transactions.yesterday'.tr(), DateUtils.addDaysToDate(today, -1)),
      ('transactions.weekAgo'.tr(), DateUtils.addDaysToDate(today, -7)),
      (
        'transactions.monthAgo'.tr(),
        DateTime(
          monthBack.year,
          monthBack.month,
          math.min(
            today.day,
            DateUtils.getDaysInMonth(monthBack.year, monthBack.month),
          ),
        ),
      ),
    ];

    return SingleChildScrollView(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpace.lg,
              0,
              AppSpace.lg,
              AppSpace.sm,
            ),
            child: Text(
              'transactions.jumpToDay'.tr(),
              style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpace.gutter),
            child: Wrap(
              spacing: AppSpace.xs,
              runSpacing: AppSpace.xs,
              children: [
                for (final (label, day) in quickPicks)
                  if (!day.isBefore(first))
                    ChoiceChip(
                      label: Text(label, style: tt.labelLarge),
                      selected: DateUtils.isSameDay(day, selected),
                      showCheckmark: false,
                      onSelected: (_) => Navigator.of(context).pop(day),
                    ),
              ],
            ),
          ),
          const SizedBox(height: AppSpace.xs),
          const Divider(indent: AppSpace.gutter, endIndent: AppSpace.gutter),
          CalendarDatePicker(
            initialDate: initial,
            firstDate: first,
            lastDate: today,
            currentDate: today,
            onDateChanged: _onDateChanged,
            onDisplayedMonthChanged: _onDisplayedMonthChanged,
          ),
        ],
      ),
    );
  }
}
