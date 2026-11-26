import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:letsspeak_trainer/Api/batch_slots.dart';
import 'package:letsspeak_trainer/screens/TeacherAlertsScreen.dart';
import 'package:letsspeak_trainer/services/trainer_alerts.dart';
import 'package:letsspeak_trainer/services/trainer_requests.dart';

const Color _navy = Color(0xFF155A8A);
const Color _teal = Color(0xFF27BFC0);
const Color _bg = Color(0xFFF0F5F9);
const Color _soft = Color(0xFFF5F9FC);
const Color _text = Color(0xFF173E5C);
const Color _muted = Color(0xFF6A8295);
const Color _border = Color(0xFFDDE8F0);
const Color _green = Color(0xFF16A34A);
const Color _amber = Color(0xFFD97706);
const Color _purple = Color(0xFF7C3AED);
const Color _orange = Color(0xFFE07A3F);
const Color _red = Color(0xFFE85D5D);

// ======================================================================
// 📥 INBOX tab: [ 🙋 Student requests ] [ 👋 New students ]
// ======================================================================
class TrainerInboxScreen extends StatefulWidget {
  const TrainerInboxScreen({super.key});

  @override
  State<TrainerInboxScreen> createState() => _TrainerInboxScreenState();
}

class _TrainerInboxScreenState extends State<TrainerInboxScreen> {
  int tab = 0; // 0 = requests, 1 = new students

  @override
  void initState() {
    super.initState();
    TrainerRequests.load();
    TrainerRequests.openId.addListener(_openFromPush);
  }

  @override
  void dispose() {
    TrainerRequests.openId.removeListener(_openFromPush);
    super.dispose();
  }

  void _openFromPush() {
    final id = TrainerRequests.openId.value;
    if (id.isEmpty || !mounted) return;
    setState(() => tab = 0);
    TrainerRequests.openId.value = '';
    Get.to(() => TrainerRequestChatScreen(id: id));
  }

  @override
  Widget build(BuildContext context) {
    Widget seg(int i, String label, IconData icon, ValueListenable<int> count) => Expanded(
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () => setState(() => tab = i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: tab == i ? Colors.white : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
                boxShadow: tab == i
                    ? [BoxShadow(color: _navy.withValues(alpha: 0.10), blurRadius: 8, offset: const Offset(0, 2))]
                    : null,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, size: 16, color: tab == i ? _navy : _muted),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.poppins(
                        color: tab == i ? _navy : _muted,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  ValueListenableBuilder<int>(
                    valueListenable: count,
                    builder: (_, n, __) => n <= 0
                        ? const SizedBox.shrink()
                        : Container(
                            margin: const EdgeInsets.only(left: 6),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(color: _red, borderRadius: BorderRadius.circular(10)),
                            child: Text(
                              '$n',
                              style: GoogleFonts.poppins(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700),
                            ),
                          ),
                  ),
                ],
              ),
            ),
          ),
        );

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Inbox', style: GoogleFonts.poppins(color: _text, fontSize: 20, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(color: const Color(0xFFE6EEF4), borderRadius: BorderRadius.circular(14)),
                    child: Row(
                      children: [
                        seg(0, 'Student requests', Icons.forum_rounded, TrainerRequests.open),
                        const SizedBox(width: 4),
                        seg(1, 'New students', Icons.person_add_alt_1_rounded, TrainerAlerts.unread),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: IndexedStack(
                index: tab,
                children: const [_RequestsList(), TeacherAlertsScreen()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ======================================================================
// helpers
// ======================================================================
class _St {
  final String label;
  final Color color;
  final IconData icon;
  const _St(this.label, this.color, this.icon);
}

_St _status(String s) {
  switch (s) {
    case 'accepted':
      return const _St('Accepted', _green, Icons.check_circle_rounded);
    case 'escalated':
      return const _St('With manager', _purple, Icons.support_agent_rounded);
    case 'solved':
      return const _St('Solved', _green, Icons.verified_rounded);
    default:
      return const _St('Needs reply', _amber, Icons.mark_chat_unread_rounded);
  }
}

class _Ty {
  final String label;
  final IconData icon;
  final Color color;
  const _Ty(this.label, this.icon, this.color);
}

_Ty _type(String t) {
  switch (t) {
    case 'other_batch':
      return const _Ty('Join another batch', Icons.swap_horiz_rounded, _navy);
    case 'absent':
      return const _Ty("Can't attend", Icons.event_busy_rounded, _orange);
    default:
      return const _Ty('Other', Icons.chat_bubble_outline_rounded, Color(0xFF0E9AA7));
  }
}

Widget _chip(_St st) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(color: st.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(20)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(st.icon, size: 12, color: st.color),
          const SizedBox(width: 4),
          Text(st.label, style: GoogleFonts.poppins(color: st.color, fontSize: 9.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );

String _ymd(DateTime d) => DateFormat('yyyy-MM-dd').format(d);

/// the class day this request is about ("2026-11-27"); old requests → day it was sent
String _day(Map<String, dynamic> r) {
  final f = '${r['forDate'] ?? ''}';
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(f)) return f;
  final t = DateTime.tryParse('${r['createdAt'] ?? r['lastActivityAt'] ?? ''}')?.toLocal();
  return t == null ? '' : _ymd(t);
}

String _dayTitle(String ymd) {
  final d = DateTime.tryParse(ymd);
  if (d == null) return 'Earlier';
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final diff = DateTime(d.year, d.month, d.day).difference(today).inDays;
  if (diff == 0) return 'Today';
  if (diff == 1) return 'Tomorrow';
  if (diff == -1) return 'Yesterday';
  return DateFormat(d.year == now.year ? 'EEE, d MMM' : 'EEE, d MMM yyyy').format(d);
}

String _when(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'Just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 20) return DateFormat('h:mm a').format(t);
  return DateFormat('d MMM, h:mm a').format(t);
}

String _time(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  return t == null ? '' : DateFormat('h:mm a').format(t);
}

/// sort key of the student's batch (unknown batch → last)
int _batchMin(Map<String, dynamic> r) => BatchSlots.find(r['batchTime'])?.startMinutes ?? 9999;

Widget _batchLine(Map<String, dynamic> r) {
  final mine = BatchSlots.find(r['batchTime'])?.shortLabel ?? '';
  final want = BatchSlots.find(r['preferredBatch'])?.shortLabel ?? '';
  Widget pill(String t, Color c, {bool strike = false}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(color: c.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
        child: Text(
          t,
          style: GoogleFonts.poppins(
            color: c,
            fontSize: 10.5,
            fontWeight: FontWeight.w600,
            decoration: strike ? TextDecoration.lineThrough : null,
          ),
        ),
      );
  if (mine.isEmpty && want.isEmpty) return const SizedBox.shrink();
  return Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 6,
    runSpacing: 4,
    children: [
      const Icon(Icons.schedule_rounded, size: 14, color: _muted),
      if (mine.isNotEmpty) pill(mine, _muted, strike: want.isNotEmpty || r['type'] == 'absent'),
      if (want.isNotEmpty) ...[
        const Icon(Icons.arrow_forward_rounded, size: 14, color: _muted),
        pill(want, _teal),
      ],
    ],
  );
}

Widget _groupHeader({required IconData icon, required String title, String sub = '', required int count}) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: _navy),
          const SizedBox(width: 6),
          Text(title, style: GoogleFonts.poppins(color: _text, fontSize: 13.5, fontWeight: FontWeight.w700)),
          if (sub.isNotEmpty) ...[
            const SizedBox(width: 6),
            Flexible(
              child: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(color: _muted, fontSize: 11)),
            ),
          ],
          const SizedBox(width: 8),
          const Expanded(child: Divider(color: _border, height: 1)),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(color: _navy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(10)),
            child: Text('$count', style: GoogleFonts.poppins(color: _navy, fontSize: 10.5, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );

// ======================================================================
// 🙋 requests list — status • batch filter • grouped by day OR by batch
// ======================================================================
class _RequestsList extends StatefulWidget {
  const _RequestsList();

  @override
  State<_RequestsList> createState() => _RequestsListState();
}

class _RequestsListState extends State<_RequestsList> {
  String filter = 'open';
  String batch = ''; // '' = all timings, else BatchSlot.label
  bool byBatch = false; // false = group by day, true = group by batch

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      color: _teal,
      onRefresh: TrainerRequests.load,
      child: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: TrainerRequests.items,
        builder: (_, all, __) {
          int n(String s) => all.where((r) => r['status'] == s).length;
          final byStatus = filter == 'all' ? all : all.where((r) => r['status'] == filter).toList();
          int nb(String label) => byStatus.where((r) => BatchSlots.find(r['batchTime'])?.label == label).length;
          final list = batch.isEmpty ? byStatus : byStatus.where((r) => BatchSlots.find(r['batchTime'])?.label == batch).toList();

          Widget statusPill(String key, String label, int count, Color c) {
            final sel = filter == key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => setState(() => filter = key),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: sel ? c : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: sel ? c : _border),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        label,
                        style: GoogleFonts.poppins(color: sel ? Colors.white : _text, fontSize: 11.5, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6),
                        decoration: BoxDecoration(
                          color: sel ? Colors.white.withValues(alpha: 0.25) : c.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$count',
                          style: GoogleFonts.poppins(color: sel ? Colors.white : c, fontSize: 10.5, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }

          Widget batchChip(String label, String text, int count) {
            final sel = batch == label;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(10),
                onTap: () => setState(() => batch = label),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: sel ? _teal.withValues(alpha: 0.14) : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? _teal : _border),
                  ),
                  child: Text(
                    count > 0 ? '$text · $count' : text,
                    style: GoogleFonts.poppins(
                      color: sel ? const Color(0xFF0B7F80) : (count > 0 ? _text : _muted),
                      fontSize: 11,
                      fontWeight: sel ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            );
          }

          // ---- groups ----
          final groups = <String, List<Map<String, dynamic>>>{};
          for (final r in list) {
            final k = byBatch ? (BatchSlots.find(r['batchTime'])?.label ?? '') : _day(r);
            groups.putIfAbsent(k, () => []).add(r);
          }
          final keys = groups.keys.toList();
          if (byBatch) {
            keys.sort((a, b) => (BatchSlots.find(a)?.startMinutes ?? 9999).compareTo(BatchSlots.find(b)?.startMinutes ?? 9999));
            for (final g in groups.values) {
              g.sort((a, b) => _day(b).compareTo(_day(a)));
            }
          } else {
            keys.sort((a, b) => b.compareTo(a));
            for (final g in groups.values) {
              g.sort((a, b) => _batchMin(a).compareTo(_batchMin(b)));
            }
          }

          return ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
            children: [
              // all 5 always visible (wraps to 2 lines on small phones)
              Wrap(
                runSpacing: 8,
                children: [
                  statusPill('open', 'Needs reply', n('open'), _amber),
                  statusPill('accepted', 'Accepted', n('accepted'), _green),
                  statusPill('escalated', 'With manager', n('escalated'), _purple),
                  statusPill('solved', 'Solved by manager', n('solved'), _teal),
                  statusPill('all', 'All', all.length, _navy),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.schedule_rounded, size: 15, color: _muted),
                  const SizedBox(width: 6),
                  Text('Timing', style: GoogleFonts.poppins(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  // group toggle
                  Container(
                    padding: const EdgeInsets.all(3),
                    decoration: BoxDecoration(color: const Color(0xFFE6EEF4), borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final v in [false, true])
                          InkWell(
                            borderRadius: BorderRadius.circular(8),
                            onTap: () => setState(() => byBatch = v),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: byBatch == v ? Colors.white : Colors.transparent,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(v ? Icons.access_time_rounded : Icons.calendar_today_rounded,
                                      size: 13, color: byBatch == v ? _navy : _muted),
                                  const SizedBox(width: 4),
                                  Text(
                                    v ? 'By batch' : 'By day',
                                    style: GoogleFonts.poppins(
                                      color: byBatch == v ? _navy : _muted,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    batchChip('', 'All timings', byStatus.length),
                    for (final b in BatchSlots.all) batchChip(b.label, '${b.start} ${b.period}', nb(b.label)),
                  ],
                ),
              ),
              if (TrainerRequests.loading.value && all.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(color: _teal)),
                )
              else if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 60),
                  child: Column(
                    children: [
                      Container(
                        width: 76,
                        height: 76,
                        decoration: BoxDecoration(color: _teal.withValues(alpha: 0.12), shape: BoxShape.circle),
                        child: const Icon(Icons.forum_rounded, size: 36, color: _teal),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        filter == 'open' ? 'No requests waiting 🎉' : 'Nothing here',
                        style: GoogleFonts.poppins(color: _text, fontSize: 14.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        all.isEmpty
                            ? 'Students of your class can message you here.'
                            : 'Tap “All” to see every request (${all.length}).',
                        style: GoogleFonts.poppins(color: _muted, fontSize: 11.5),
                      ),
                    ],
                  ),
                )
              else
                for (final k in keys) ...[
                  if (byBatch)
                    _groupHeader(
                      icon: Icons.access_time_rounded,
                      title: BatchSlots.find(k)?.title ?? 'No batch',
                      sub: BatchSlots.find(k)?.shortLabel ?? '',
                      count: groups[k]!.length,
                    )
                  else
                    _groupHeader(
                      icon: Icons.calendar_today_rounded,
                      title: _dayTitle(k),
                      sub: ['Today', 'Tomorrow', 'Yesterday'].contains(_dayTitle(k)) && DateTime.tryParse(k) != null
                          ? DateFormat('EEE, d MMM').format(DateTime.parse(k))
                          : '',
                      count: groups[k]!.length,
                    ),
                  for (final r in groups[k]!)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _TrainerRequestCard(r: r, showDay: byBatch),
                    ),
                ],
            ],
          );
        },
      ),
    );
  }
}

class _TrainerRequestCard extends StatelessWidget {
  final Map<String, dynamic> r;
  final bool showDay;
  const _TrainerRequestCard({required this.r, required this.showDay});

  @override
  Widget build(BuildContext context) {
    final st = _status('${r['status']}');
    final ty = _type('${r['type']}');
    final msgs = (r['messages'] as List?) ?? const [];
    final last = msgs.isEmpty ? <String, dynamic>{} : Map<String, dynamic>.from(msgs.last as Map);
    final name = '${r['studentName'] ?? ''}'.trim();
    final open = r['status'] == 'open';
    final lastWho = last['role'] == 'teacher' ? 'You' : '${last['byName'] ?? ''}';

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => Get.to(() => TrainerRequestChatScreen(id: '${r['id']}')),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: open ? _amber.withValues(alpha: 0.55) : _border, width: open ? 1.4 : 1),
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  width: 4,
                  decoration: BoxDecoration(
                    color: st.color,
                    borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                  ),
                ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 18,
                              backgroundColor: _navy.withValues(alpha: 0.10),
                              child: Text(
                                name.isEmpty ? '?' : name[0].toUpperCase(),
                                style: GoogleFonts.poppins(color: _navy, fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    name.isEmpty ? 'Student' : name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(color: _text, fontSize: 13.5, fontWeight: FontWeight.w700),
                                  ),
                                  Text(
                                    '${r['classLabel'] ?? ''}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(color: _muted, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                            _chip(st),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: ty.color.withValues(alpha: 0.10), borderRadius: BorderRadius.circular(8)),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(ty.icon, size: 13, color: ty.color),
                                  const SizedBox(width: 4),
                                  Text(ty.label, style: GoogleFonts.poppins(color: ty.color, fontSize: 10.5, fontWeight: FontWeight.w600)),
                                ],
                              ),
                            ),
                            if (showDay && _day(r).isNotEmpty)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(color: _navy.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(8)),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.event_rounded, size: 13, color: _navy),
                                    const SizedBox(width: 4),
                                    Text(_dayTitle(_day(r)), style: GoogleFonts.poppins(color: _navy, fontSize: 10.5, fontWeight: FontWeight.w600)),
                                  ],
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        _batchLine(r),
                        if ('${last['text'] ?? ''}'.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            '${lastWho.isEmpty ? '' : '$lastWho: '}${last['text']}',
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(color: _text.withValues(alpha: 0.85), fontSize: 12, height: 1.4),
                          ),
                        ],
                        const SizedBox(height: 6),
                        Align(
                          alignment: Alignment.centerRight,
                          child: Text(_when('${r['lastActivityAt']}'), style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ======================================================================
// 💬 one request: details + chat + Accept / Send to manager
// ======================================================================
class TrainerRequestChatScreen extends StatefulWidget {
  final String id;
  const TrainerRequestChatScreen({super.key, required this.id});

  @override
  State<TrainerRequestChatScreen> createState() => _TrainerRequestChatScreenState();
}

class _TrainerRequestChatScreenState extends State<TrainerRequestChatScreen> {
  Map<String, dynamic>? r;
  bool busy = false;
  final ctrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
    TrainerRequests.tick.addListener(_load);
  }

  @override
  void dispose() {
    TrainerRequests.tick.removeListener(_load);
    ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final d = await TrainerRequests.get(widget.id);
    if (mounted && d != null) setState(() => r = d);
  }

  Future<void> _do(Future<String?> Function() action, String done) async {
    FocusScope.of(context).unfocus();
    setState(() => busy = true);
    final err = await action();
    if (!mounted) return;
    setState(() => busy = false);
    if (err == null) {
      ctrl.clear();
      await _load();
      Get.snackbar('Done', done,
          backgroundColor: _green,
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(12),
          duration: const Duration(seconds: 2));
    } else {
      Get.snackbar('Not done', err,
          backgroundColor: const Color(0xFFDC2626),
          colorText: Colors.white,
          snackPosition: SnackPosition.TOP,
          margin: const EdgeInsets.all(12));
    }
  }

  /// bottom sheet with a note + quick picks; returns null when cancelled
  Future<String?> _askNote({
    required String title,
    required String sub,
    required String hint,
    required String button,
    required Color color,
    required IconData icon,
    List<String> quick = const [],
  }) async {
    final c = TextEditingController();
    final res = await Get.bottomSheet<String>(
      StatefulBuilder(
        builder: (ctx, setS) => Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: SafeArea(
              top: false,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(4)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
                        child: Icon(icon, color: color, size: 20),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: GoogleFonts.poppins(color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
                            Text(sub, style: GoogleFonts.poppins(color: _muted, fontSize: 11.5)),
                          ],
                        ),
                      ),
                    ],
                  ),
                  if (quick.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final q in quick)
                          ActionChip(
                            label: Text(q, style: GoogleFonts.poppins(fontSize: 11, color: _text)),
                            backgroundColor: _soft,
                            side: const BorderSide(color: _border),
                            onPressed: () => setS(() {
                              c.text = q;
                              c.selection = TextSelection.collapsed(offset: q.length);
                            }),
                          ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 12),
                  TextField(
                    controller: c,
                    minLines: 2,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    style: GoogleFonts.poppins(fontSize: 13, color: _text),
                    decoration: InputDecoration(
                      hintText: hint,
                      hintStyle: GoogleFonts.poppins(fontSize: 12, color: _muted),
                      filled: true,
                      fillColor: _soft,
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _border)),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: color, width: 1.5)),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => Get.back(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: _muted,
                            side: const BorderSide(color: _border),
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text('Cancel', style: GoogleFonts.poppins(fontWeight: FontWeight.w600)),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        flex: 2,
                        child: ElevatedButton(
                          onPressed: () => Get.back(result: c.text.trim()),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: color,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(0, 46),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(button, style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      isScrollControlled: true,
    );
    return res;
  }

  void _accept() async {
    final want = BatchSlots.find(r?['preferredBatch'])?.shortLabel ?? '';
    final day = _dayTitle(_day(r ?? const {})).toLowerCase();
    final note = await _askNote(
      title: 'Accept request?',
      sub: '${r?['studentName'] ?? 'The student'} gets a notification.',
      hint: 'Optional message',
      button: 'Accept',
      color: _green,
      icon: Icons.check_circle_rounded,
      quick: [
        if (want.isNotEmpty) 'OK, join the $want batch $day.',
        if (r?['type'] == 'absent') 'OK, noted. Please watch the materials.',
        'OK 👍',
      ],
    );
    if (note != null) _do(() => TrainerRequests.accept(widget.id, note), 'Student was told you accepted ✅');
  }

  void _escalate() async {
    final note = await _askNote(
      title: 'Send to manager?',
      sub: 'The manager will call the student and solve it.',
      hint: 'Why? e.g. "Evening batch is full"',
      button: 'Send to manager',
      color: _purple,
      icon: Icons.support_agent_rounded,
      quick: const ['That batch is full', 'Needs fee / access check', 'Please call the student'],
    );
    if (note != null) _do(() => TrainerRequests.escalate(widget.id, note), 'Sent to the manager 📨');
  }

  @override
  Widget build(BuildContext context) {
    final status = '${r?['status'] ?? 'open'}';
    final solved = status == 'solved';
    final canDecide = r != null && (status == 'open' || status == 'accepted');
    final msgs = ((r?['messages'] as List?) ?? const []).map((m) => Map<String, dynamic>.from(m as Map)).toList();
    final name = '${r?['studentName'] ?? ''}'.trim();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            CircleAvatar(
              radius: 17,
              backgroundColor: Colors.white.withValues(alpha: 0.18),
              child: Text(
                name.isEmpty ? '?' : name[0].toUpperCase(),
                style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name.isEmpty ? 'Request' : name,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700)),
                  Text('${r?['classLabel'] ?? ''}',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.poppins(fontSize: 10.5, color: Colors.white70)),
                ],
              ),
            ),
          ],
        ),
      ),
      body: r == null
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : Column(
              children: [
                _details(),
                Expanded(child: _messages(msgs)),
                if (!solved) _bottom(canDecide, status, name) else _solvedBar(),
              ],
            ),
    );
  }

  Widget _details() {
    final ty = _type('${r!['type']}');
    final st = _status('${r!['status']}');
    final day = _day(r!);
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(color: ty.color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
                child: Icon(ty.icon, color: ty.color, size: 18),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ty.label, style: GoogleFonts.poppins(color: _text, fontSize: 13.5, fontWeight: FontWeight.w700)),
                    if (day.isNotEmpty)
                      Text(
                        'For ${_dayTitle(day)}'
                        '${['Today', 'Tomorrow', 'Yesterday'].contains(_dayTitle(day)) ? ' • ${DateFormat('EEE, d MMM').format(DateTime.parse(day))}' : ''}',
                        style: GoogleFonts.poppins(color: _muted, fontSize: 11),
                      ),
                  ],
                ),
              ),
              _chip(st),
            ],
          ),
          const SizedBox(height: 10),
          _batchLine(r!),
          if ('${r!['status']}' == 'escalated' && '${r!['escalatedByName'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Sent to manager by ${r!['escalatedByName']}', style: GoogleFonts.poppins(color: _purple, fontSize: 11)),
          ],
          if ('${r!['status']}' == 'accepted' && '${r!['acceptedByName'] ?? ''}'.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Accepted by ${r!['acceptedByName']}', style: GoogleFonts.poppins(color: _green, fontSize: 11)),
          ],
        ],
      ),
    );
  }

  Widget _messages(List<Map<String, dynamic>> msgs) {
    final rows = <Widget>[];
    String lastDay = '';
    for (final m in msgs) {
      final t = DateTime.tryParse('${m['at']}')?.toLocal();
      final d = t == null ? '' : _ymd(t);
      if (d.isNotEmpty && d != lastDay) {
        lastDay = d;
        rows.add(Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(10)),
            child: Text(_dayTitle(d), style: GoogleFonts.poppins(color: _muted, fontSize: 10, fontWeight: FontWeight.w600)),
          ),
        ));
      }
      rows.add(_bubble(m));
    }
    return ListView(
      reverse: true,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      children: rows.reversed.toList(),
    );
  }

  Widget _bubble(Map<String, dynamic> m) {
    final role = '${m['role']}';
    if (role == 'system') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Text('${m['text']}',
              textAlign: TextAlign.center, style: GoogleFonts.poppins(color: _muted, fontSize: 10.5, fontStyle: FontStyle.italic)),
        ),
      );
    }
    final mine = role == 'teacher';
    final who = role == 'student'
        ? '${m['byName']} • Student'
        : mine
            ? '${m['byName']} • Trainer'
            : '${m['byName']} • Manager';
    final whoColor = role == 'student' ? _navy : (mine ? Colors.white70 : _purple);
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        decoration: BoxDecoration(
          color: mine ? _navy : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(mine ? 16 : 4),
            bottomRight: Radius.circular(mine ? 4 : 16),
          ),
          border: mine ? null : Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(who, style: GoogleFonts.poppins(color: whoColor, fontSize: 10, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            SelectableText('${m['text']}',
                style: GoogleFonts.poppins(color: mine ? Colors.white : _text, fontSize: 13, height: 1.4)),
            const SizedBox(height: 2),
            Align(
              alignment: Alignment.bottomRight,
              child: Text(_time('${m['at']}'), style: GoogleFonts.poppins(color: mine ? Colors.white60 : _muted, fontSize: 9)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _bottom(bool canDecide, String status, String name) {
    return Container(
      decoration: const BoxDecoration(color: Colors.white, border: Border(top: BorderSide(color: _border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (canDecide) ...[
                Row(
                  children: [
                    if (status == 'open') ...[
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: busy ? null : _accept,
                          icon: const Icon(Icons.check_rounded, size: 18),
                          label: Text('Accept', style: GoogleFonts.poppins(fontWeight: FontWeight.w700)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _green,
                            foregroundColor: Colors.white,
                            elevation: 0,
                            minimumSize: const Size(0, 44),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: busy ? null : _escalate,
                        icon: const Icon(Icons.support_agent_rounded, size: 18),
                        label: Text(
                          status == 'open' ? 'To manager' : 'Send to manager',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 12.5),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _purple,
                          side: const BorderSide(color: _purple),
                          minimumSize: const Size(0, 44),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: ctrl,
                      minLines: 1,
                      maxLines: 4,
                      maxLength: 1000,
                      textCapitalization: TextCapitalization.sentences,
                      style: GoogleFonts.poppins(fontSize: 13.5, color: _text),
                      decoration: InputDecoration(
                        counterText: '',
                        hintText: 'Reply to ${name.isEmpty ? 'student' : name}…',
                        hintStyle: GoogleFonts.poppins(fontSize: 13, color: _muted),
                        filled: true,
                        fillColor: _soft,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(24), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 46,
                    height: 46,
                    child: IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: _teal),
                      onPressed: busy
                          ? null
                          : () {
                              final t = ctrl.text.trim();
                              if (t.isNotEmpty) _do(() => TrainerRequests.reply(widget.id, t), 'Reply sent');
                            },
                      icon: busy
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.send_rounded, color: Colors.white, size: 20),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _solvedBar() => Container(
        width: double.infinity,
        color: Colors.white,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Text(
              '✅ Solved by ${r!['solvedByName'] ?? 'the manager'}',
              textAlign: TextAlign.center,
              style: GoogleFonts.poppins(color: _green, fontWeight: FontWeight.w700),
            ),
          ),
        ),
      );
}