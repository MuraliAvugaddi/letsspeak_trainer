// =========================================================================
// ✍️ TRAINER TESTS — write a test → admin approves → admin releases
//
//   TeacherTestsScreen  → "Tests" tab: my tests with status
//                         (Waiting for admin / Approved / Sent back / Live)
//   TestEditorScreen    → write or fix questions, then "Send to admin"
//
// Students see the test only after the admin presses "Release".
// =========================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:letsspeak_trainer/Api/Apiend_points.dart';
import 'package:letsspeak_trainer/Api/api_headers.dart';
import 'package:socket_io_client/socket_io_client.dart' as IO;

const Color _navy = Color(0xFF155A8A);
const Color _deepNavy = Color(0xFF0E3F63);
const Color _teal = Color(0xFF27BFC0);
const Color _bg = Color(0xFFEAF2F8);
const Color _green = Color(0xFF12B76A);
const Color _amber = Color(0xFFE59E1B);
const Color _red = Color(0xFFE5484D);
const Color _purple = Color(0xFF7A5AF8);

String _testApi(String path) => '${ApiEndpoints.baseUrl}/test$path';

String _stageLabel(String s) =>
    s.replaceAll(RegExp('stage', caseSensitive: false), 'Stage ');

String _date(String? iso) {
  final d = DateTime.tryParse(iso ?? '')?.toLocal();
  if (d == null) return '';
  const m = [
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
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '${d.day} ${m[d.month - 1]}, $h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

({String label, Color color, IconData icon}) _statusLook(String s) {
  switch (s) {
    case 'approved':
      return (
        label: 'Approved • not live yet',
        color: _purple,
        icon: Icons.verified_rounded,
      );
    case 'rejected':
      return (
        label: 'Sent back — please fix',
        color: _red,
        icon: Icons.reply_rounded,
      );
    case 'released':
      return (
        label: 'Live for students',
        color: _green,
        icon: Icons.check_circle_rounded,
      );
    default:
      return (
        label: 'Waiting for admin',
        color: _amber,
        icon: Icons.hourglass_top_rounded,
      );
  }
}

/// The trainer's own class (from login data) — tests are only for this class
({String language, String stage}) _myClass(Map<String, dynamic> t) {
  final l = (t['language'] ?? t['courseLanguage'] ?? 'English')
      .toString()
      .toLowerCase();
  var st = (t['teacherStage'] ?? t['stage'] ?? t['assignedStage'] ?? 'stage1')
      .toString()
      .toLowerCase()
      .replaceAll(' ', '');
  if (RegExp(r'^\d$').hasMatch(st)) st = 'stage$st';
  if (!RegExp(r'^stage[1-7]$').hasMatch(st)) st = 'stage1';
  return (language: l == 'hindi' ? 'Hindi' : 'English', stage: st);
}

// =========================================================================
// LIST
// =========================================================================
class TeacherTestsScreen extends StatefulWidget {
  final Map<String, dynamic> teacherData;
  const TeacherTestsScreen({super.key, required this.teacherData});

  @override
  State<TeacherTestsScreen> createState() => _TeacherTestsScreenState();
}

class _TeacherTestsScreenState extends State<TeacherTestsScreen>
    with WidgetsBindingObserver {
  List<Map<String, dynamic>> _drafts = [];
  bool _loading = true;
  String? _error;
  IO.Socket? _socket;
  Timer? _poll;
  Map<String, String> _lastStatus =
      {}; // id → status (to tell the trainer what changed)

  ({String language, String stage}) get _cls => _myClass(widget.teacherData);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
    _listenLive();
    // safety net: refresh every 30 s even if the live connection drops
    _poll = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _load(quiet: true),
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load(quiet: true);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _poll?.cancel();
    _socket?.clearListeners();
    _socket?.dispose();
    super.dispose();
  }

  /// ⚡ Admin approves / sends back / releases → this list updates by itself
  void _listenLive() {
    try {
      final id = (widget.teacherData['_id'] ?? widget.teacherData['id'] ?? '')
          .toString();
      final uri = Uri.parse(ApiEndpoints.baseUrl);
      _socket = IO.io(
        '${uri.scheme}://${uri.host}:${uri.port}',
        <String, dynamic>{
          'transports': ['websocket'],
          'autoConnect': true,
          'forceNew': true,
          'auth': {'token': ApiHeaders.token ?? ''},
        },
      );
      _socket?.onConnect((_) {
        if (id.isNotEmpty) _socket?.emit('join_user_room', id);
        _load(quiet: true); // anything that changed while we were offline
      });
      _socket?.onReconnect((_) {
        if (id.isNotEmpty) _socket?.emit('join_user_room', id);
      });
      _socket?.on('test_draft_updated', (data) {
        if (!mounted) return;
        _load(quiet: true);
        final status = data is Map ? (data['status'] ?? '').toString() : '';
        final note = data is Map ? (data['note'] ?? '').toString() : '';
        final text = {
          'approved':
              'Admin approved your test ✅ It goes live when the admin releases it.',
          'released': 'Your test is LIVE for students now 🚀',
          'rejected':
              'Admin sent your test back${note.isNotEmpty ? ': $note' : ' — please fix it.'}',
        }[status];
        if (text != null) {
          _announcedLive = true;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text),
              backgroundColor: status == 'rejected' ? _red : _green,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      });
    } catch (e) {
      debugPrint('Tests live updates off: $e');
    }
  }

  Future<void> _load({bool quiet = false}) async {
    if (!mounted) return;
    setState(() {
      if (!quiet) _loading = true;
      _error = null;
    });
    try {
      final res = await http
          .get(
            Uri.parse(_testApi('/trainer/test-drafts')),
            headers: ApiHeaders.auth(),
          )
          .timeout(const Duration(seconds: 20));
      final data = jsonDecode(res.body);
      if (res.statusCode == 200) {
        _drafts = ((data['drafts'] ?? []) as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList();
        _announceChanges();
      } else {
        _error = (data['message'] ?? 'Could not load tests').toString();
      }
    } catch (e) {
      _error = 'Could not load tests. Check your internet.';
    }
    if (mounted) setState(() => _loading = false);
  }

  /// Status changed since the last load (live message missed) → small message
  void _announceChanges() {
    final now = {
      for (final d in _drafts)
        d['_id'].toString(): (d['status'] ?? '').toString(),
    };
    if (_lastStatus.isNotEmpty && mounted && !_announcedLive) {
      for (final e in now.entries) {
        final before = _lastStatus[e.key];
        if (before == null || before == e.value) continue;
        final text = {
          'approved': 'Admin approved your test ✅',
          'released': 'Your test is LIVE for students now 🚀',
          'rejected': 'Admin sent your test back — please fix it.',
        }[e.value];
        if (text != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(text),
              backgroundColor: e.value == 'rejected' ? _red : _green,
            ),
          );
          break;
        }
      }
    }
    _announcedLive = false;
    _lastStatus = now;
  }

  bool _announcedLive = false; // the live message already showed the text

  Future<void> _open([Map<String, dynamic>? draft]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TestEditorScreen(
          draft: draft,
          language: _cls.language,
          stage: _cls.stage,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _delete(Map<String, dynamic> d) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 24, 22, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _red.withOpacity(.12),
                ),
                child: const Icon(
                  Icons.delete_outline_rounded,
                  color: _red,
                  size: 28,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Delete this test?',
                style: GoogleFonts.poppins(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  color: _deepNavy,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'The questions will be removed. This cannot be undone.',
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(
                  fontSize: 12.5,
                  color: Colors.black54,
                ),
              ),
              const SizedBox(height: 18),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Cancel',
                        style: GoogleFonts.poppins(
                          color: _deepNavy,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _red,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size.fromHeight(46),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Delete',
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
    if (ok != true) return;
    try {
      final res = await http
          .delete(
            Uri.parse(_testApi('/trainer/test-draft?id=${d['_id']}')),
            headers: ApiHeaders.auth(),
          )
          .timeout(const Duration(seconds: 20));
      final msg = (jsonDecode(res.body)['message'] ?? '').toString();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(msg.isEmpty ? 'Done' : msg)));
      if (res.statusCode == 200) _load();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not delete. Try again.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = _drafts
        .where(
          (d) => d['language'] == _cls.language && d['stage'] == _cls.stage,
        )
        .toList();
    final others = _drafts
        .where(
          (d) => !(d['language'] == _cls.language && d['stage'] == _cls.stage),
        )
        .toList();
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          'My Tests',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17),
        ),
        actions: [
          IconButton(onPressed: _load, icon: const Icon(Icons.refresh_rounded)),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _teal,
        foregroundColor: Colors.white,
        onPressed: () => _open(),
        icon: const Icon(Icons.add_rounded),
        label: Text(
          'New test',
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700),
        ),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 120),
                children: [
                  _classHeader(),
                  const SizedBox(height: 14),
                  if (_error != null)
                    _message(Icons.wifi_off_rounded, _error!)
                  else if (_drafts.isEmpty)
                    _message(
                      Icons.quiz_outlined,
                      'No tests yet.\nTap "New test" to write your first one.',
                    )
                  else ...[
                    ...mine.map(_card),
                    if (others.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: Text(
                          'Older tests (other class)',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Colors.black45,
                          ),
                        ),
                      ),
                      ...others.map(_card),
                    ],
                  ],
                ],
              ),
      ),
    );
  }

  /// Your class + how it works
  Widget _classHeader() {
    Widget step(IconData icon, String t) => Expanded(
      child: Column(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.15),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(icon, color: Colors.white, size: 18),
          ),
          const SizedBox(height: 5),
          Text(
            t,
            textAlign: TextAlign.center,
            style: GoogleFonts.poppins(
              color: Colors.white,
              fontSize: 10,
              fontWeight: FontWeight.w600,
              height: 1.25,
            ),
          ),
        ],
      ),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_navy, _deepNavy]),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.school_rounded,
                color: Color(0xFFF5DD55),
                size: 18,
              ),
              const SizedBox(width: 8),
              Text(
                'Your class',
                style: GoogleFonts.poppins(
                  color: Colors.white70,
                  fontSize: 11.5,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${_cls.language} • ${_stageLabel(_cls.stage)}',
                  style: GoogleFonts.poppins(
                    color: _deepNavy,
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              step(Icons.edit_note_rounded, 'You write\nthe test'),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              step(Icons.fact_check_rounded, 'Admin checks\n& approves'),
              const Icon(Icons.chevron_right_rounded, color: Colors.white38),
              step(Icons.rocket_launch_rounded, 'Students\nget the test'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _message(IconData icon, String text) => Padding(
    padding: const EdgeInsets.only(top: 50),
    child: Column(
      children: [
        Icon(icon, size: 48, color: Colors.black26),
        const SizedBox(height: 10),
        Text(
          text,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(color: Colors.black45, fontSize: 13),
        ),
      ],
    ),
  );

  Widget _card(Map<String, dynamic> d) {
    final status = (d['status'] ?? 'pending').toString();
    final look = _statusLook(status);
    final count = (d['questions'] is List)
        ? (d['questions'] as List).length
        : 0;
    final title = (d['title'] ?? '').toString();
    final note = (d['reviewNote'] ?? '').toString();
    final canEdit = status == 'pending' || status == 'rejected';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: status == 'rejected'
              ? _red.withOpacity(.35)
              : const Color(0xFFDCE7F0),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: look.color.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(look.icon, color: look.color, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title.isEmpty
                            ? '${d['language']} ${_stageLabel(d['stage'].toString())} test'
                            : title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 14,
                          color: _deepNavy,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '$count questions • ${d['durationMinutes'] ?? 25} min • ${_date(d['updatedAt']?.toString())}',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: look.color.withOpacity(.10),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                look.label,
                style: GoogleFonts.poppins(
                  fontSize: 11,
                  color: look.color,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            if (note.isNotEmpty) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: (status == 'rejected' ? _red : _navy).withOpacity(.06),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.comment_rounded,
                      size: 16,
                      color: status == 'rejected' ? _red : _navy,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Admin: $note',
                        style: GoogleFonts.poppins(
                          fontSize: 12,
                          color: _deepNavy,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            const Divider(height: 1, thickness: 1, color: Color(0xFFE8EFF5)),
            const SizedBox(height: 12),
            // clear buttons instead of "tap the card"
            Row(
              children: [
                if (canEdit) ...[
                  // 🗑 small square delete button (never wraps)
                  Tooltip(
                    message: 'Delete test',
                    child: SizedBox(
                      width: 46,
                      height: 44,
                      child: OutlinedButton(
                        onPressed: () => _delete(d),
                        style: OutlinedButton.styleFrom(
                          padding: EdgeInsets.zero,
                          foregroundColor: _red,
                          backgroundColor: _red.withOpacity(.05),
                          side: BorderSide(color: _red.withOpacity(.30)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Icon(
                          Icons.delete_outline_rounded,
                          size: 21,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: () => _open(d),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: status == 'rejected' ? _red : _navy,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.edit_rounded, size: 18),
                      label: Text(
                        status == 'rejected' ? 'Fix & send again' : 'Edit test',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ),
                ] else
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () => _open(d),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _navy,
                        side: const BorderSide(color: Color(0xFFDCE7F0)),
                        minimumSize: const Size.fromHeight(44),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      icon: const Icon(Icons.visibility_outlined, size: 18),
                      label: Text(
                        'View questions',
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
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

// =========================================================================
// EDITOR
// =========================================================================
class _QForm {
  final TextEditingController text;
  final List<TextEditingController> options;
  int correct;
  _QForm({String q = '', List<String>? opts, this.correct = 0})
    : text = TextEditingController(text: q),
      options = List.generate(
        4,
        (i) => TextEditingController(
          text: (opts != null && i < opts.length) ? opts[i] : '',
        ),
      );

  void dispose() {
    text.dispose();
    for (final o in options) {
      o.dispose();
    }
  }
}

class TestEditorScreen extends StatefulWidget {
  final Map<String, dynamic>? draft;
  final String language; // the trainer's class (fixed)
  final String stage;
  const TestEditorScreen({
    super.key,
    this.draft,
    required this.language,
    required this.stage,
  });

  @override
  State<TestEditorScreen> createState() => _TestEditorScreenState();
}

class _TestEditorScreenState extends State<TestEditorScreen> {
  static const List<int> _times = [10, 15, 20, 25, 30, 45, 60];

  final _title = TextEditingController();
  int _minutes = 25;
  final List<_QForm> _qs = [];
  bool _sending = false;

  bool get _readOnly {
    final s = (widget.draft?['status'] ?? 'pending').toString();
    return widget.draft != null && !(s == 'pending' || s == 'rejected');
  }

  // an old test keeps its own class; a new one uses the trainer's class
  String get _language =>
      (widget.draft?['language'] ?? widget.language).toString();
  String get _stage => (widget.draft?['stage'] ?? widget.stage).toString();

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _minutes = int.tryParse('${d?['durationMinutes'] ?? 25}') ?? 25;
    _title.text = (d?['title'] ?? '').toString();
    final list = d?['questions'];
    if (list is List && list.isNotEmpty) {
      for (final q in list.whereType<Map>()) {
        _qs.add(
          _QForm(
            q: (q['questionText'] ?? '').toString(),
            opts: (q['options'] is List)
                ? (q['options'] as List).map((e) => e.toString()).toList()
                : null,
            correct: int.tryParse('${q['correctOptionIndex'] ?? 0}') ?? 0,
          ),
        );
      }
    } else {
      _qs.add(_QForm());
    }
  }

  @override
  void dispose() {
    _title.dispose();
    for (final q in _qs) {
      q.dispose();
    }
    super.dispose();
  }

  String? _check() {
    if (_qs.isEmpty) return 'Add at least one question';
    for (var i = 0; i < _qs.length; i++) {
      final q = _qs[i];
      if (q.text.text.trim().isEmpty)
        return 'Question ${i + 1}: write the question';
      final filled = q.options.where((o) => o.text.trim().isNotEmpty).length;
      if (filled < 2) return 'Question ${i + 1}: write at least 2 options';
      if (q.options[q.correct].text.trim().isEmpty)
        return 'Question ${i + 1}: the right answer is empty';
    }
    return null;
  }

  List<Map<String, dynamic>> _payloadQuestions() {
    return _qs.map((q) {
      // keep only filled options, and move the correct index with them
      final opts = <String>[];
      var correct = 0;
      for (var i = 0; i < q.options.length; i++) {
        final t = q.options[i].text.trim();
        if (t.isEmpty) continue;
        if (i == q.correct) correct = opts.length;
        opts.add(t);
      }
      return {
        'questionText': q.text.text.trim(),
        'options': opts,
        'correctOptionIndex': correct,
      };
    }).toList();
  }

  Future<void> _send() async {
    FocusScope.of(context).unfocus();
    final err = _check();
    if (err != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(err), backgroundColor: _red));
      return;
    }
    setState(() => _sending = true);
    try {
      final res = await http
          .post(
            Uri.parse(_testApi('/trainer/test-draft')),
            headers: ApiHeaders.json(),
            body: jsonEncode({
              if (widget.draft != null) 'id': widget.draft!['_id'],
              'title': _title.text.trim(),
              'language': _language,
              'stage': _stage,
              'durationMinutes': _minutes,
              'questions': _payloadQuestions(),
            }),
          )
          .timeout(const Duration(seconds: 25));
      final msg = (jsonDecode(res.body)['message'] ?? '').toString();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(msg.isEmpty ? 'Done' : msg),
          backgroundColor: res.statusCode == 200 ? _green : _red,
        ),
      );
      if (res.statusCode == 200) Navigator.pop(context, true);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not send. Check your internet.'),
          backgroundColor: _red,
        ),
      );
    }
    if (mounted) setState(() => _sending = false);
  }

  InputDecoration _box(String hint, {Color fill = Colors.white}) =>
      InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.poppins(fontSize: 13, color: Colors.black38),
        filled: true,
        fillColor: fill,
        isDense: true,
        counterText: '',
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 13,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDCE7F0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFDCE7F0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _teal, width: 1.6),
        ),
      );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, left: 2),
    child: Text(
      t,
      style: GoogleFonts.poppins(
        fontSize: 12.5,
        fontWeight: FontWeight.w700,
        color: _deepNavy,
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final ro = _readOnly;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.draft == null ? 'New test' : (ro ? 'View test' : 'Edit test'),
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 17),
        ),
      ),
      bottomNavigationBar: ro
          ? null
          : SafeArea(
              child: Container(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Color(0xFFDCE7F0))),
                ),
                child: SizedBox(
                  height: 52,
                  child: ElevatedButton.icon(
                    onPressed: _sending ? null : _send,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _teal,
                      foregroundColor: Colors.white,
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    icon: _sending
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.send_rounded),
                    label: Text(
                      'Send to admin  •  ${_qs.length} ${_qs.length == 1 ? 'question' : 'questions'}',
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ),
              ),
            ),
      // 🔒 View mode: the list must still SCROLL — so no AbsorbPointer around it.
      //    Each field is read-only instead (see readOnly: ro below).
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 30),
        children: [
          if (ro)
            Container(
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _purple.withOpacity(.08),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.lock_outline_rounded,
                    color: _purple,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'The admin already approved this test, so it can\'t be changed.',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _deepNavy,
                      ),
                    ),
                  ),
                ],
              ),
            ),

          // ---- class (fixed) ----
          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFDCE7F0)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _teal.withOpacity(.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.school_rounded,
                    color: _teal,
                    size: 21,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Test for your class',
                        style: GoogleFonts.poppins(
                          fontSize: 11,
                          color: Colors.black45,
                        ),
                      ),
                      Text(
                        '$_language • ${_stageLabel(_stage)}',
                        style: GoogleFonts.poppins(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: _deepNavy,
                        ),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.lock_rounded, color: Colors.black26, size: 18),
              ],
            ),
          ),
          const SizedBox(height: 18),

          // ---- name ----
          _label('Test name (optional)'),
          TextField(
            controller: _title,
            readOnly: ro,
            maxLength: 120,
            decoration: _box(ro ? 'No name' : 'e.g. Week 3 — Past tense'),
          ),
          const SizedBox(height: 18),

          // ---- time ----
          _label('Time for students'),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _times.map((t) {
              final sel = _minutes == t;
              return ChoiceChip(
                selected: sel,
                showCheckmark: false,
                label: Text('$t min'),
                labelStyle: GoogleFonts.poppins(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: sel ? Colors.white : _deepNavy,
                ),
                selectedColor: _navy,
                backgroundColor: Colors.white,
                side: BorderSide(color: sel ? _navy : const Color(0xFFDCE7F0)),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: ro ? null : (_) => setState(() => _minutes = t),
              );
            }).toList(),
          ),
          const SizedBox(height: 22),

          // ---- questions ----
          Row(
            children: [
              Text(
                'Questions',
                style: GoogleFonts.poppins(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: _deepNavy,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: _navy.withOpacity(.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_qs.length}',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    fontWeight: FontWeight.w800,
                    color: _navy,
                  ),
                ),
              ),
            ],
          ),
          if (!ro)
            Padding(
              padding: const EdgeInsets.only(top: 4, bottom: 10),
              child: Text(
                'Tap the letter (A B C D) of the right answer — it turns green.',
                style: GoogleFonts.poppins(fontSize: 11, color: Colors.black45),
              ),
            )
          else
            const SizedBox(height: 10),
          for (var i = 0; i < _qs.length; i++) _questionCard(i),
          if (!ro)
            OutlinedButton.icon(
              onPressed: () => setState(() => _qs.add(_QForm())),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size.fromHeight(50),
                backgroundColor: Colors.white,
                side: BorderSide(color: _navy.withOpacity(.35), width: 1.4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              icon: const Icon(Icons.add_circle_outline_rounded, color: _navy),
              label: Text(
                'Add another question',
                style: GoogleFonts.poppins(
                  color: _navy,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _questionCard(int i) {
    final q = _qs[i];
    const letters = ['A', 'B', 'C', 'D'];
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFDCE7F0)),
        boxShadow: [
          BoxShadow(
            color: _navy.withOpacity(.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // header strip
          Container(
            padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
            decoration: BoxDecoration(
              color: _navy.withOpacity(.05),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(18),
              ),
            ),
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(
                    color: _navy,
                    shape: BoxShape.circle,
                  ),
                  child: Text(
                    '${i + 1}',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  'Question ${i + 1}',
                  style: GoogleFonts.poppins(
                    fontWeight: FontWeight.w700,
                    color: _deepNavy,
                    fontSize: 13,
                  ),
                ),
                const Spacer(),
                if (_qs.length > 1 && !_readOnly)
                  TextButton.icon(
                    onPressed: () {
                      final gone = _qs.removeAt(i);
                      setState(() {});
                      WidgetsBinding.instance.addPostFrameCallback(
                        (_) => gone.dispose(),
                      );
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _red,
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.delete_outline_rounded, size: 18),
                    label: Text(
                      'Remove',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              children: [
                TextField(
                  controller: q.text,
                  readOnly: _readOnly,
                  minLines: 2,
                  maxLines: 5,
                  style: GoogleFonts.poppins(fontSize: 13.5, color: _deepNavy),
                  decoration: _box(
                    'Type the question here',
                    fill: const Color(0xFFF7FAFC),
                  ),
                ),
                const SizedBox(height: 12),
                for (var k = 0; k < 4; k++) _optionRow(q, k, letters[k]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// One answer: tap the letter to make it the right answer
  Widget _optionRow(_QForm q, int k, String letter) {
    final right = q.correct == k;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          GestureDetector(
            onTap: _readOnly ? null : () => setState(() => q.correct = k),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: right ? _green : Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: right ? _green : const Color(0xFFCFDCE6),
                  width: 1.6,
                ),
              ),
              child: right
                  ? const Icon(
                      Icons.check_rounded,
                      color: Colors.white,
                      size: 20,
                    )
                  : Text(
                      letter,
                      style: GoogleFonts.poppins(
                        color: Colors.black54,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: TextField(
              controller: q.options[k],
              readOnly: _readOnly,
              style: GoogleFonts.poppins(fontSize: 13, color: _deepNavy),
              decoration:
                  _box(
                    k < 2 ? 'Answer $letter' : 'Answer $letter (optional)',
                    fill: right ? _green.withOpacity(.07) : Colors.white,
                  ).copyWith(
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(
                        color: right
                            ? _green.withOpacity(.6)
                            : const Color(0xFFDCE7F0),
                      ),
                    ),
                    suffixIcon: right
                        ? Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Center(
                              widthFactor: 1,
                              child: Text(
                                'Right',
                                style: GoogleFonts.poppins(
                                  color: _green,
                                  fontSize: 11,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          )
                        : null,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
