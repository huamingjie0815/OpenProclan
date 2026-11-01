import 'l10n/app_localizations.dart';

String categoryLabel(AppLocalizations l, String wire) {
  return switch (wire) {
    '科技' => l.catTech,
    '财经' => l.catMarkets,
    '国际' => l.catWorld,
    '社会' => l.catSociety,
    '生活' => l.catLife,
    '其他' => l.catOther,
    _ => wire,
  };
}

String weekdayName(AppLocalizations l, int weekday) {
  return switch (weekday) {
    1 => l.weekdayMon,
    2 => l.weekdayTue,
    3 => l.weekdayWed,
    4 => l.weekdayThu,
    5 => l.weekdayFri,
    6 => l.weekdaySat,
    _ => l.weekdaySun,
  };
}

const _monthsEn = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

bool _zh(AppLocalizations l) => l.localeName.startsWith('zh');

DateTime? localTime(String iso) => DateTime.tryParse(iso)?.toLocal();

String clockOf(DateTime time) {
  final hour = time.hour.toString().padLeft(2, '0');
  final minute = time.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

int calendarDaysBeforeToday(DateTime day) {
  final now = DateTime.now();
  final today = DateTime.utc(now.year, now.month, now.day);
  final that = DateTime.utc(day.year, day.month, day.day);
  return today.difference(that).inDays;
}

String dayHeading(AppLocalizations l, DateTime day) {
  final diff = calendarDaysBeforeToday(day);
  if (diff == 0) {
    return l.today;
  }
  if (diff == 1) {
    return l.yesterday;
  }
  if (_zh(l)) {
    return '${day.month}月${day.day}日';
  }
  return '${_monthsEn[day.month - 1]} ${day.day}';
}

String editionMeta(AppLocalizations l, DateTime now) {
  final week = weekdayName(l, now.weekday);
  if (_zh(l)) {
    return '${now.month}月 · $week';
  }
  return '${_monthsEn[now.month - 1]} · $week';
}

String shortWhen(AppLocalizations l, String iso) {
  final time = localTime(iso);
  if (time == null) {
    return '';
  }
  final minutes = DateTime.now().difference(time).inMinutes;
  if (minutes < 0 || minutes >= 360) {
    return clockOf(time);
  }
  if (minutes < 60) {
    return l.minutesAgo(minutes);
  }
  final hours = minutes ~/ 60;
  final rest = minutes % 60;
  if (_zh(l) || rest == 0) {
    return l.hoursAgo(hours);
  }
  return l.hoursMinutesAgo(hours, rest);
}

String detailWhen(AppLocalizations l, String iso) {
  final time = localTime(iso);
  if (time == null) {
    return '';
  }
  final clock = clockOf(time);
  final diff = calendarDaysBeforeToday(time);
  if (diff == 0) {
    return l.todayAt(clock);
  }
  if (diff == 1) {
    return l.yesterdayAt(clock);
  }
  if (_zh(l)) {
    return '${time.month}月${time.day}日 $clock';
  }
  return '${_monthsEn[time.month - 1]} ${time.day}, $clock';
}

String sourceMark(String source) {
  final trimmed = source.trim();
  if (trimmed.isEmpty) {
    return '';
  }
  return String.fromCharCode(trimmed.runes.first).toUpperCase();
}

String nameMark(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return '?';
  }
  final char = String.fromCharCode(trimmed.runes.first);
  final lower = char.toLowerCase();
  if (lower != char.toUpperCase()) {
    return char.toUpperCase();
  }
  return char;
}

int readingMinutes(String text) {
  final chars = text.replaceAll(RegExp(r'\s'), '').length;
  final minutes = (chars / 380).round();
  return minutes < 1 ? 1 : minutes;
}
