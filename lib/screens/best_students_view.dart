import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:letsspeak_trainer/Api/api_headers.dart';

/// 🏆 Best student of the month — students only (no trainers).
///   • "Your class": the student's own class(es) / the trainer's own class
///   • Best of ALL English and ALL Hindi (every stage, online + offline)
///   • Every class: English online per stage + section, English offline per stage, Hindi per stage
/// Score = attendance 50% + trainer practice stars 30% + tests 20%. Month by month only.
class BestStudentsView extends StatefulWidget {
  /// 'student' | 'trainer' | 'admin' — only changes a few words
  final String audience;
  final EdgeInsetsGeometry padding;
  const BestStudentsView({super.key, this.audience = 'student', this.padding = const EdgeInsets.fromLTRB(14, 12, 14, 28)});

  @override
  State<BestStudentsView> createState() => _BestStudentsViewState();
}

class _BestStudentsViewState extends State<BestStudentsView> {
  static const Color navy = Color(0xFF155A88);
  static const Color teal = Color(0xFF28C2C2);
  static const Color gold = Color(0xFFE3B21B);
  static const Color silver = Color(0xFF9AAAB8);
  static const Color bronze = Color(0xFFC07A45);
  static const Color green = Color(0xFF16A66A);
  static const Color star = Color(0xFFF5B83D);
  static const Color red = Color(0xFFE45757);

  static const List<String> monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June',
    'July', 'August', 'September', 'October', 'November', 'December',
  ];

  late int year;
  late int month;
  bool loading = true;
  String? error;
  Map<String, dynamic>? data;
  String langFilter = 'All';
  final Set<String> open = <String>{};

  bool get _dark => Theme.of(context).brightness == Brightness.dark;
  Color get _card => _dark ? const Color(0xFF1B2A36) : Colors.white;
  Color get _soft => _dark ? const Color(0xFF223441) : const Color(0xFFF4F9FC);
  Color get _border => _dark ? const Color(0xFF2E4352) : const Color(0xFFD5E5EE);
  Color get _text => _dark ? const Color(0xFFE8F1F7) : const Color(0xFF173A52);
  Color get _muted => _dark ? const Color(0xFF9DB3C3) : const Color(0xFF678196);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    year = now.year;
    month = now.month;
    _load();
  }

  Future<void> _load() async {
    setState(() {
      loading = true;
      error = null;
    });
    try {
      final res = await http
          .get(Uri.parse('${ApiEndpoints.baseUrl}/leaderboard/best-students?year=$year&month=$month'), headers: ApiHeaders.auth())
          .timeout(const Duration(seconds: 30));
      if (!mounted) return;
      if (res.statusCode == 200) {
        setState(() {
          data = Map<String, dynamic>.from(jsonDecode(res.body));
          loading = false;
        });
      } else {
        String msg = 'Could not load (${res.statusCode})';
        try {
          final b = jsonDecode(res.body);
          if (b is Map && b['message'] != null) msg = b['message'].toString();
        } catch (_) {}
        setState(() {
          error = msg;
          loading = false;
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        error = 'Connection problem. Pull down to try again.';
        loading = false;
      });
    }
  }

  void _shift(int delta) {
    final now = DateTime.now();
    final total = year * 12 + (month - 1) + delta;
    final y = total ~/ 12, m = total % 12 + 1;
    if (y * 12 + m > now.year * 12 + now.month || y < 2024) return;
    setState(() {
      year = y;
      month = m;
      open.clear();
    });
    _load();
  }

  List<Map<String, dynamic>> _list(dynamic v) =>
      ((v ?? const []) as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  // =========================================================
  @override
  Widget build(BuildContext context) {
    final classes = _list(data?['classes']);
    final overall = _list(data?['overall']);
    final mine = classes.where((c) => c['mine'] == true).toList();
    final shown = classes.where((c) => langFilter == 'All' || c['language'] == langFilter).toList();

    return RefreshIndicator(
      color: navy,
      onRefresh: _load,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        padding: widget.padding,
        children: [
          _monthNav(),
          const SizedBox(height: 12),
          if (loading)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 80),
              child: Center(child: CircularProgressIndicator(color: navy, strokeWidth: 2.4)),
            )
          else if (error != null)
            _note(Icons.error_outline_rounded, error!, red)
          else ...[
            if (mine.isNotEmpty) ...[
              _title(widget.audience == 'trainer' ? '👨‍🏫 Your class' : '🎓 Your class', 'Best student in your own class'),
              ...mine.map((c) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _classBig(c))),
              const SizedBox(height: 4),
            ],
            _title('🏆 Best of all stages', 'Online + offline, every stage together'),
            ...overall.map((o) => Padding(padding: const EdgeInsets.only(bottom: 12), child: _overallCard(o))),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(child: _title('📚 Every class', '${classes.length} classes this month', bottom: 0)),
                for (final l in ['All', 'English', 'Hindi'])
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: ChoiceChip(
                      label: Text(l, style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600)),
                      selected: langFilter == l,
                      onSelected: (_) => setState(() => langFilter = l),
                      selectedColor: navy.withOpacity(.15),
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (shown.isEmpty) _note(Icons.hourglass_empty_rounded, 'No classes with results yet this month.', _muted),
            ...shown.map((c) => Padding(padding: const EdgeInsets.only(bottom: 8), child: _classRow(c))),
            const SizedBox(height: 8),
            Text(
              'Score = attendance 50% + trainer speaking-practice stars 30% + test average 20%. '
              'Only this month counts. Students need at least 3 working days. Sundays are off. Today counts after 8:15 PM.',
              style: GoogleFonts.poppins(color: _muted, fontSize: 9.5, height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  // ---------------------------------------------------------
  Widget _monthNav() {
    final now = DateTime.now();
    final canNext = year * 12 + month < now.year * 12 + now.month;
    Widget arrow(IconData i, bool on, VoidCallback f) => Material(
          color: on ? navy.withOpacity(.10) : _soft,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: on ? f : null,
            child: SizedBox(width: 40, height: 40, child: Icon(i, color: on ? navy : _border)),
          ),
        );
    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
      child: Row(
        children: [
          arrow(Icons.chevron_left_rounded, true, () => _shift(-1)),
          Expanded(
            child: Column(
              children: [
                Text('${monthNames[month - 1]} $year',
                    style: GoogleFonts.poppins(color: _text, fontSize: 15, fontWeight: FontWeight.w800)),
                Text('Best students of the month', style: GoogleFonts.poppins(color: _muted, fontSize: 9.5)),
              ],
            ),
          ),
          arrow(Icons.chevron_right_rounded, canNext, () => _shift(1)),
        ],
      ),
    );
  }

  Widget _title(String t, String sub, {double bottom = 8}) => Padding(
        padding: EdgeInsets.only(bottom: bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t, style: GoogleFonts.poppins(color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
            Text(sub, style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
          ],
        ),
      );

  Widget _note(IconData icon, String text, Color c) => Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(14), border: Border.all(color: _border)),
        child: Row(
          children: [
            Icon(icon, color: c),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: GoogleFonts.poppins(color: _text, fontSize: 12))),
          ],
        ),
      );

  Color _medal(int rank) => rank == 1 ? gold : (rank == 2 ? silver : (rank == 3 ? bronze : navy));

  Widget _metrics(Map<String, dynamic> p, {double size = 10}) {
    Widget m(IconData i, String t, Color c) => Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(i, size: size + 3, color: c),
              const SizedBox(width: 2),
              Text(t, style: GoogleFonts.poppins(color: _muted, fontSize: size, fontWeight: FontWeight.w600)),
            ],
          ),
        );
    final pa = (p['practiceAvg'] as num?)?.toDouble() ?? 0;
    final tc = (p['testCount'] as num?)?.toInt() ?? 0;
    return Wrap(
      children: [
        m(Icons.event_available_rounded, '${p['percentage'] ?? 0}%', green),
        m(Icons.star_rounded, pa > 0 ? pa.toStringAsFixed(1) : '–', star),
        m(Icons.assignment_turned_in_rounded, tc > 0 ? '${p['testAvg']}%' : '–', navy),
      ],
    );
  }

  Widget _scoreBadge(int score, {double size = 16}) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
        decoration: BoxDecoration(color: navy.withOpacity(.10), borderRadius: BorderRadius.circular(10)),
        child: Column(
          children: [
            Text('$score', style: GoogleFonts.poppins(color: navy, fontSize: size, fontWeight: FontWeight.w800, height: 1.1)),
            Text('score', style: GoogleFonts.poppins(color: _muted, fontSize: 8)),
          ],
        ),
      );

  Widget _personRow(Map<String, dynamic> p, {bool highlight = false}) {
    final r = (p['rank'] as num?)?.toInt() ?? 0;
    final phone = (p['phone'] ?? '').toString();
    return Container(
      margin: const EdgeInsets.only(top: 6),
      padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
      decoration: BoxDecoration(
        color: highlight ? teal.withOpacity(.12) : _soft,
        borderRadius: BorderRadius.circular(12),
        border: highlight ? Border.all(color: teal.withOpacity(.6)) : null,
      ),
      child: Row(
        children: [
          Container(
            width: 26,
            height: 26,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: _medal(r).withOpacity(.16), shape: BoxShape.circle),
            child: Text('$r', style: GoogleFonts.poppins(color: _medal(r), fontSize: 11, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  highlight ? '${p['name']} (You)' : (p['name'] ?? '').toString(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(color: _text, fontSize: 12, fontWeight: FontWeight.w700),
                ),
                Row(
                  children: [
                    Flexible(child: _metrics(p, size: 9.5)),
                    if (phone.isNotEmpty)
                      Text(phone, style: GoogleFonts.poppins(color: _muted, fontSize: 9)),
                  ],
                ),
              ],
            ),
          ),
          Text('${p['score'] ?? 0}', style: GoogleFonts.poppins(color: navy, fontSize: 14, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _winnerHero(Map<String, dynamic>? w, String caption, {Color c1 = navy, Color c2 = const Color(0xFF0E466D)}) {
    if (w == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(color: _soft, borderRadius: BorderRadius.circular(14)),
        child: Text('No winner yet — results appear after a few class days.',
            style: GoogleFonts.poppins(color: _muted, fontSize: 11)),
      );
    }
    final name = (w['name'] ?? '').toString();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: [c1, c2], begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              CircleAvatar(
                radius: 24,
                backgroundColor: Colors.white.withOpacity(.18),
                child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800)),
              ),
              const Positioned(top: -12, left: 10, child: Text('👑', style: TextStyle(fontSize: 18))),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(caption.toUpperCase(),
                    style: GoogleFonts.poppins(color: Colors.white70, fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: .6)),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.poppins(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800)),
                const SizedBox(height: 3),
                Wrap(
                  spacing: 10,
                  children: [
                    _whiteMetric('📅', '${w['percentage'] ?? 0}% attendance'),
                    _whiteMetric('⭐', ((w['practiceAvg'] as num?)?.toDouble() ?? 0) > 0 ? '${w['practiceAvg']}' : '–'),
                    _whiteMetric('📝', ((w['testCount'] as num?)?.toInt() ?? 0) > 0 ? '${w['testAvg']}%' : '–'),
                  ],
                ),
              ],
            ),
          ),
          Column(
            children: [
              Text('${w['score'] ?? 0}',
                  style: GoogleFonts.poppins(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w800, height: 1)),
              Text('score', style: GoogleFonts.poppins(color: Colors.white70, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  Widget _whiteMetric(String e, String t) =>
      Text('$e $t', style: GoogleFonts.poppins(color: Colors.white.withOpacity(.9), fontSize: 10.5, fontWeight: FontWeight.w600));

  // Own class: winner + top 5 + "you"
  Widget _classBig(Map<String, dynamic> c) {
    final top = _list(c['top']);
    final me = c['me'] is Map ? Map<String, dynamic>.from(c['me']) : null;
    final meInTop = me != null && top.any((p) => p['userId'] == me['userId']);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: teal.withOpacity(.5))),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text((c['label'] ?? '').toString(),
                    style: GoogleFonts.poppins(color: _text, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              Text('${c['totalRanked'] ?? 0} students', style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          _winnerHero(c['winner'] is Map ? Map<String, dynamic>.from(c['winner']) : null, 'Best student of ${monthNames[month - 1]}',
              c1: const Color(0xFF0E7C7B), c2: teal),
          ...top.skip(1).take(4).map((p) => _personRow(p, highlight: me != null && p['userId'] == me['userId'])),
          if (me != null && !meInTop) ...[
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Center(child: Text('•  •  •', style: GoogleFonts.poppins(color: _muted, fontSize: 10))),
            ),
            _personRow(me, highlight: true),
          ],
        ],
      ),
    );
  }

  // Best of all English / all Hindi
  Widget _overallCard(Map<String, dynamic> o) {
    final top = _list(o['top']);
    final english = o['language'] == 'English';
    final me = o['me'] is Map ? Map<String, dynamic>.from(o['me']) : null;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: _card, borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(english ? '🇬🇧' : '🇮🇳', style: const TextStyle(fontSize: 16)),
              const SizedBox(width: 6),
              Expanded(
                child: Text('${o['language']} — all stages',
                    style: GoogleFonts.poppins(color: _text, fontSize: 12.5, fontWeight: FontWeight.w800)),
              ),
              Text('${o['totalRanked'] ?? 0} students', style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
            ],
          ),
          const SizedBox(height: 8),
          _winnerHero(
            o['winner'] is Map ? Map<String, dynamic>.from(o['winner']) : null,
            'Best ${o['language']} student',
            c1: english ? navy : const Color(0xFFB4570B),
            c2: english ? const Color(0xFF0E466D) : const Color(0xFFE0A21B),
          ),
          ...top.skip(1).take(2).map((p) => _personRow(p, highlight: me != null && p['userId'] == me['userId'])),
          if (me != null && ((me['rank'] as num?)?.toInt() ?? 0) > 3) _personRow(me, highlight: true),
        ],
      ),
    );
  }

  // Every class: compact row, tap to see the top 10
  Widget _classRow(Map<String, dynamic> c) {
    final key = (c['key'] ?? '').toString();
    final expanded = open.contains(key);
    final w = c['winner'] is Map ? Map<String, dynamic>.from(c['winner']) : null;
    final top = _list(c['top']);
    final mine = c['mine'] == true;
    return Container(
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: mine ? teal.withOpacity(.6) : _border),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(14),
            onTap: () => setState(() => expanded ? open.remove(key) : open.add(key)),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
              child: Row(
                children: [
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(color: gold.withOpacity(.15), borderRadius: BorderRadius.circular(10)),
                    child: const Center(child: Text('🏅', style: TextStyle(fontSize: 16))),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text((c['label'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(color: _muted, fontSize: 10, fontWeight: FontWeight.w600)),
                        Text(w == null ? 'No winner yet' : (w['name'] ?? '').toString(),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.poppins(color: _text, fontSize: 13, fontWeight: FontWeight.w800)),
                        if (w != null) _metrics(w, size: 9.5),
                      ],
                    ),
                  ),
                  if (w != null) _scoreBadge((w['score'] as num?)?.toInt() ?? 0, size: 14),
                  Icon(expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded, color: _muted),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Column(
                children: [
                  ...top.map((p) => _personRow(p,
                      highlight: c['me'] is Map && (c['me'] as Map)['userId'] == p['userId'])),
                  if (((c['totalRanked'] as num?)?.toInt() ?? 0) > top.length)
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Text('Top ${top.length} of ${c['totalRanked']} students',
                          style: GoogleFonts.poppins(color: _muted, fontSize: 10)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
