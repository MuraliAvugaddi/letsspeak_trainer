import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:letsspeak_trainer/services/trainer_alerts.dart';

/// 👋 NEW STUDENTS — who the admin / online manager added to your class
///   • grouped by day: Today / Yesterday / 12 Nov …
///   • 📅 calendar: see only one day
///   • timing of the class is shown big (05:30 AM - 07:00 AM)
///   • online/offline only for some days → "For 2 days • till Mon, 16 Nov"
///   • student phone numbers are NOT shown
class TeacherAlertsScreen extends StatefulWidget {
  const TeacherAlertsScreen({super.key});

  @override
  State<TeacherAlertsScreen> createState() => _TeacherAlertsScreenState();
}

class _TeacherAlertsScreenState extends State<TeacherAlertsScreen> {
  static const Color navy = Color(0xFF155A8A);
  static const Color teal = Color(0xFF27BFC0);
  static const Color amber = Color(0xFFE59E1B);
  static const Color bg = Color(0xFFEAF2F8);
  static const Color text = Color(0xFF16324A);
  static const Color muted = Color(0xFF667F95);
  static const Color line = Color(0xFFE1EBF3);

  static const List<String> _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  static const List<String> _days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  /// 'all' | 'today' | 'yesterday' | 'day' (= _pickedDay)
  String _when = 'all';
  DateTime? _pickedDay;

  @override
  void initState() {
    super.initState();
    TrainerAlerts.load();
  }

  // ---------------------------------------------------------------- dates
  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);
  static DateTime? _timeOf(Map a) => DateTime.tryParse('${a['createdAt'] ?? ''}')?.toLocal();

  String _dayTitle(DateTime day) {
    final today = _dayOf(DateTime.now());
    if (day == today) return 'Today';
    if (day == today.subtract(const Duration(days: 1))) return 'Yesterday';
    return '${_days[day.weekday - 1]}, ${day.day} ${_months[day.month - 1]}${day.year == today.year ? '' : ' ${day.year}'}';
  }

  String _clock(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'AM' : 'PM'}';
  }

  String _shortDay(DateTime d) => '${_days[d.weekday - 1]}, ${d.day} ${_months[d.month - 1]}';

  bool _matches(Map a) {
    if (_when == 'all') return true;
    final t = _timeOf(a);
    if (t == null) return false;
    final day = _dayOf(t);
    final today = _dayOf(DateTime.now());
    switch (_when) {
      case 'today':
        return day == today;
      case 'yesterday':
        return day == today.subtract(const Duration(days: 1));
      case 'day':
        return _pickedDay != null && day == _pickedDay;
    }
    return true;
  }

  Future<void> _pickDay() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedDay ?? now,
      firstDate: now.subtract(const Duration(days: 60)),
      lastDate: now,
      helpText: 'Show new students of this day',
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(primary: navy, onPrimary: Colors.white, onSurface: text),
          dialogTheme: const DialogThemeData(backgroundColor: Colors.white),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _pickedDay = _dayOf(picked);
      _when = 'day';
    });
  }

  // ---------------------------------------------------------------- texts
  String _stage(String s) => s.replaceAll(RegExp(r'stage', caseSensitive: false), 'Stage ');

  String _by(Map a) {
    final name = '${a['byName'] ?? ''}'.trim();
    final role = '${a['byRole'] ?? ''}';
    final who = role == 'manager' ? 'Manager' : 'Admin';
    final how = {
          'promoted': 'Promoted by',
          'rejoined': 'Brought back by',
          'mode': 'Moved by',
        }['${a['reason'] ?? ''}'] ??
        'Added by';
    return '$how $who${name.isEmpty ? '' : ' $name'}';
  }

  /// "For 2 days • till Mon, 16 Nov" (only when the change is temporary)
  String? _period(Map a) {
    final until = DateTime.tryParse('${a['until'] ?? ''}')?.toLocal();
    if (until == null) return null;
    final how = const {'1d': 'For 1 day', '2d': 'For 2 days', '1w': 'For 1 week'}['${a['duration'] ?? ''}'] ?? 'For a few days';
    return '$how • till ${_shortDay(until)}';
  }

  // ---------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 18,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('New students', style: GoogleFonts.poppins(color: text, fontSize: 18, fontWeight: FontWeight.w800)),
            Text(
              'Students the admin added to your class',
              style: GoogleFonts.poppins(color: muted, fontSize: 11.5, fontWeight: FontWeight.w500),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Pick a day',
            onPressed: _pickDay,
            icon: const Icon(Icons.calendar_month_rounded, color: navy),
          ),
          ValueListenableBuilder<int>(
            valueListenable: TrainerAlerts.unread,
            builder: (_, n, __) => n == 0
                ? const SizedBox(width: 6)
                : IconButton(
                    tooltip: 'Mark all as read',
                    onPressed: TrainerAlerts.markAllRead,
                    icon: const Icon(Icons.done_all_rounded, color: navy),
                  ),
          ),
        ],
      ),
      body: RefreshIndicator(
        color: teal,
        onRefresh: TrainerAlerts.load,
        child: ValueListenableBuilder<List<Map<String, dynamic>>>(
          valueListenable: TrainerAlerts.items,
          builder: (context, all, _) {
            final list = all.where(_matches).toList();
            final today = _dayOf(DateTime.now());
            int countOn(DateTime day) => all.where((a) {
                  final t = _timeOf(a);
                  return t != null && _dayOf(t) == day;
                }).length;

            // group by day (newest first)
            final groups = <DateTime, List<Map<String, dynamic>>>{};
            for (final a in list) {
              final t = _timeOf(a);
              final day = t == null ? today : _dayOf(t);
              groups.putIfAbsent(day, () => []).add(a);
            }
            final days = groups.keys.toList()..sort((a, b) => b.compareTo(a));

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                _filters(all.length, countOn(today), countOn(today.subtract(const Duration(days: 1)))),
                const SizedBox(height: 12),
                if (list.isEmpty)
                  ValueListenableBuilder<bool>(
                    valueListenable: TrainerAlerts.loading,
                    builder: (_, busy, __) => Padding(
                      padding: const EdgeInsets.only(top: 80),
                      child: busy && all.isEmpty
                          ? const Center(child: CircularProgressIndicator(color: teal))
                          : _empty(),
                    ),
                  )
                else
                  for (final day in days) ...[
                    _dayHeader(day, groups[day]!.length),
                    for (final a in groups[day]!) ...[
                      _card(a),
                      const SizedBox(height: 10),
                    ],
                    const SizedBox(height: 6),
                  ],
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _filters(int all, int today, int yesterday) {
    Widget chip(String key, String label, int? n, {IconData? icon, VoidCallback? onTap}) {
      final sel = _when == key;
      return Padding(
        padding: const EdgeInsets.only(right: 8),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap ?? () => setState(() => _when = key),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: sel ? navy : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: sel ? navy : line),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 15, color: sel ? Colors.white : navy),
                  const SizedBox(width: 5),
                ],
                Text(label,
                    style: GoogleFonts.poppins(
                        color: sel ? Colors.white : text, fontSize: 12, fontWeight: FontWeight.w700)),
                if (n != null) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                    decoration: BoxDecoration(
                      color: sel ? Colors.white.withValues(alpha: 0.2) : teal.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Text('$n',
                        style: GoogleFonts.poppins(
                            color: sel ? Colors.white : navy, fontSize: 10.5, fontWeight: FontWeight.w800)),
                  ),
                ],
              ],
            ),
          ),
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          chip('all', 'All', all),
          chip('today', 'Today', today),
          chip('yesterday', 'Yesterday', yesterday),
          chip(
            'day',
            _when == 'day' && _pickedDay != null ? _shortDay(_pickedDay!) : 'Pick a day',
            null,
            icon: Icons.calendar_month_rounded,
            onTap: _pickDay,
          ),
        ],
      ),
    );
  }

  Widget _dayHeader(DateTime day, int n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 4, 2, 8),
      child: Row(
        children: [
          Text(_dayTitle(day), style: GoogleFonts.poppins(color: text, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(width: 8),
          Text('$n new', style: GoogleFonts.poppins(color: muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
          const SizedBox(width: 10),
          const Expanded(child: Divider(color: line, height: 1)),
        ],
      ),
    );
  }

  Widget _empty() {
    final title = switch (_when) {
      'today' => 'No new students today',
      'yesterday' => 'No new students yesterday',
      'day' => 'No new students on this day',
      _ => 'No new students yet',
    };
    return Column(
      children: [
        Container(
          width: 76,
          height: 76,
          decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: line)),
          child: const Icon(Icons.notifications_none_rounded, color: navy, size: 36),
        ),
        const SizedBox(height: 14),
        Text(title, style: GoogleFonts.poppins(color: text, fontSize: 15, fontWeight: FontWeight.w700)),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'When the admin adds a student to your class, you will see it here and get a notification.',
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(color: muted, fontSize: 12, height: 1.4),
          ),
        ),
      ],
    );
  }

  Widget _chip(IconData icon, String label, {Color color = navy}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(label, style: GoogleFonts.poppins(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _card(Map<String, dynamic> a) {
    final name = '${a['studentName'] ?? 'Student'}'.trim();
    final unread = a['read'] != true;
    final section = '${a['section'] ?? ''}';
    final batch = '${a['batch'] ?? ''}';
    final offline = a['mode'] == 'offline';
    final initial = name.isEmpty ? '?' : name[0].toUpperCase();
    final t = _timeOf(a);
    final period = _period(a);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: unread ? teal : line, width: unread ? 1.4 : 1),
        boxShadow: [BoxShadow(color: navy.withValues(alpha: 0.05), blurRadius: 12, offset: const Offset(0, 4))],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: teal.withValues(alpha: 0.15),
                      child: Text(initial,
                          style: GoogleFonts.poppins(color: navy, fontSize: 17, fontWeight: FontWeight.w800)),
                    ),
                    if (unread)
                      Positioned(
                        right: -1,
                        top: -1,
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: const Color(0xFFE85D5D),
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.poppins(color: text, fontSize: 15, fontWeight: FontWeight.w800)),
                          ),
                          if (unread)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(color: teal, borderRadius: BorderRadius.circular(6)),
                              child: Text('NEW',
                                  style: GoogleFonts.poppins(
                                      color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.w800)),
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          _chip(Icons.school_rounded, '${a['language'] ?? 'English'} ${_stage('${a['stage'] ?? ''}')}'),
                          if (section.isNotEmpty) _chip(Icons.groups_rounded, 'Section $section'),
                          if (offline) _chip(Icons.apartment_rounded, 'Offline'),
                          if (period != null) _chip(Icons.event_repeat_rounded, period, color: amber),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ⏰ class timing (big) + who added + when
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: const BoxDecoration(
              color: Color(0xFFF4F8FB),
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(16)),
            ),
            child: Row(
              children: [
                const Icon(Icons.schedule_rounded, size: 16, color: navy),
                const SizedBox(width: 6),
                Text(
                  batch.isEmpty ? 'No timing yet' : batch,
                  style: GoogleFonts.poppins(color: navy, fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    '${_by(a)}${t == null ? '' : ' • ${_clock(t)}'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: GoogleFonts.poppins(color: muted, fontSize: 10.5, fontWeight: FontWeight.w500),
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
