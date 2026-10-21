/// The 7 daily class timings (IST) — same list as the backend (utils/batches.js).
/// The backend stores `label` exactly as written here, e.g. "05:30 AM - 07:00 AM".
class BatchSlot {
  final int number;
  final String label; // canonical value sent to / stored by the backend
  final String start; // "5:30"
  final String end; // "7:00"
  final String period; // "AM" | "PM" (start)
  final String? endPeriod; // only when the class ends in the other half (10:30 AM – 12:00 PM)
  final int startMinutes;

  const BatchSlot({
    required this.number,
    required this.label,
    required this.start,
    required this.end,
    required this.period,
    required this.startMinutes,
    this.endPeriod,
  });

  /// "5:30 – 7:00 AM"   or   "10:30 AM – 12:00 PM"
  String get shortLabel =>
      (endPeriod == null || endPeriod == period) ? '$start – $end $period' : '$start $period – $end $endPeriod';

  /// "Batch 1"
  String get title => 'Batch $number';
}

class BatchSlots {
  BatchSlots._();

  static const List<BatchSlot> all = [
    BatchSlot(number: 1, label: '05:30 AM - 07:00 AM', start: '5:30', end: '7:00', period: 'AM', startMinutes: 330),
    BatchSlot(number: 2, label: '07:00 AM - 08:30 AM', start: '7:00', end: '8:30', period: 'AM', startMinutes: 420),
    BatchSlot(number: 3, label: '09:00 AM - 10:30 AM', start: '9:00', end: '10:30', period: 'AM', startMinutes: 540),
    BatchSlot(number: 4, label: '10:30 AM - 12:00 PM', start: '10:30', end: '12:00', period: 'AM', endPeriod: 'PM', startMinutes: 630),
    BatchSlot(number: 5, label: '03:30 PM - 05:00 PM', start: '3:30', end: '5:00', period: 'PM', startMinutes: 930),
    BatchSlot(number: 6, label: '05:00 PM - 06:30 PM', start: '5:00', end: '6:30', period: 'PM', startMinutes: 1020),
    BatchSlot(number: 7, label: '06:30 PM - 08:00 PM', start: '6:30', end: '8:00', period: 'PM', startMinutes: 1110),
  ];

  static List<BatchSlot> get morning => all.where((b) => b.period == 'AM').toList();
  static List<BatchSlot> get evening => all.where((b) => b.period == 'PM').toList();

  /// Finds a batch from anything stored/sent: "05:30 AM - 07:00 AM", "5:30 AM - 7:00 AM",
  /// "batch3", 3, "03:30 - 05:00". Returns null for empty / unknown / "N/A".
  static BatchSlot? find(dynamic value) {
    if (value == null) return null;
    final raw = value.toString().trim();
    if (raw.isEmpty) return null;

    final id = RegExp(r'^(?:batch\s*)?([1-7])$', caseSensitive: false).firstMatch(raw);
    if (id != null) return all[int.parse(id.group(1)!) - 1];

    final m = RegExp(r'(\d{1,2}):(\d{2})\s*(AM|PM)?', caseSensitive: false).firstMatch(raw);
    if (m == null) return null;
    var h = int.parse(m.group(1)!);
    final min = int.parse(m.group(2)!);
    final mod = (m.group(3) ?? '').toUpperCase();
    if (mod == 'PM' && h < 12) h += 12;
    if (mod == 'AM' && h == 12) h = 0;

    BatchSlot? byStart(int minutes) {
      for (final b in all) {
        if (b.startMinutes == minutes) return b;
      }
      return null;
    }

    return byStart(h * 60 + min) ?? ((mod.isEmpty && h < 12) ? byStart((h + 12) * 60 + min) : null);
  }

  /// Canonical label or "" when not chosen.
  static String labelOf(dynamic value) => find(value)?.label ?? '';

  /// "5:30 – 7:00 AM" or the fallback text.
  static String shortOf(dynamic value, {String fallback = 'Timing not set'}) =>
      find(value)?.shortLabel ?? fallback;
}
