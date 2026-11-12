// =========================================================================
// ✋ RAISE HAND + 💬 STUDENT QUESTIONS — trainer side of the live class
//
//   ClassHandsBar   → yellow bar under the mic-lock bar: "3 hands raised"
//                     tap → list with "Allow to speak" / "Lower"
//   ClassChatAction → 💬 button in the class top bar (red badge = new questions)
//                     tap → questions from students + send a message to all
//
// Everything comes from ClassroomController (Home_PortalScreen.dart).
// =========================================================================
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:letsspeak_trainer/screens/Home_PortalScreen.dart';

const Color _navy = Color(0xFF155A8A);
const Color _deepNavy = Color(0xFF0E3F63);
const Color _teal = Color(0xFF27BFC0);
const Color _yellow = Color(0xFFF5DD55);
const Color _amber = Color(0xFFE59E1B);
const Color _green = Color(0xFF12B76A);
const Color _red = Color(0xFFE5484D);

String _ago(DateTime t) {
  final s = DateTime.now().difference(t).inSeconds;
  if (s < 60) return 'just now';
  final m = s ~/ 60;
  return m == 1 ? '1 min ago' : '$m min ago';
}

String _clock(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  return '$h:${t.minute.toString().padLeft(2, '0')} ${t.hour < 12 ? 'AM' : 'PM'}';
}

// -------------------------------------------------------------------------
// ✋ Bar: shows only when someone raised a hand
// -------------------------------------------------------------------------
class ClassHandsBar extends StatelessWidget {
  final ClassroomController cc;
  const ClassHandsBar({super.key, required this.cc});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final list = cc.hands.toList();
      if (list.isEmpty) return const SizedBox.shrink();
      final first = list.first;
      return Material(
        color: _yellow,
        child: InkWell(
          onTap: () => showClassHandsSheet(context, cc),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
            child: Row(
              children: [
                const Text('✋', style: TextStyle(fontSize: 20)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        list.length == 1
                            ? '1 hand raised'
                            : '${list.length} hands raised',
                        style: GoogleFonts.poppins(
                          color: _deepNavy,
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      Text(
                        list.length == 1
                            ? first.name
                            : '${first.name} and ${list.length - 1} more',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          color: _deepNavy.withOpacity(.75),
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
                if (list.length == 1)
                  _smallButton('Allow', _green, () => cc.allowHand(first))
                else
                  _smallButton(
                    'View',
                    _navy,
                    () => showClassHandsSheet(context, cc),
                  ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

Widget _smallButton(String label, Color color, VoidCallback onTap) {
  return Padding(
    padding: const EdgeInsets.only(left: 6),
    child: ElevatedButton(
      onPressed: onTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: color,
        foregroundColor: Colors.white,
        elevation: 0,
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
      child: Text(
        label,
        style: GoogleFonts.poppins(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    ),
  );
}

Future<void> showClassHandsSheet(BuildContext context, ClassroomController cc) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * .75,
        ),
        child: Obx(() {
          final list = cc.hands.toList();
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 6),
                child: Row(
                  children: [
                    const Text('✋', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Raised hands (${list.length})',
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: _deepNavy,
                        ),
                      ),
                    ),
                    if (list.isNotEmpty)
                      TextButton(
                        onPressed: cc.lowerAllHands,
                        child: Text(
                          'Lower all',
                          style: GoogleFonts.poppins(
                            color: _red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18),
                child: Text(
                  cc.micLocked.value
                      ? 'Mics are locked. "Allow" opens the mic only for that student.'
                      : 'Mics are open. "Allow" tells the student to speak now.',
                  style: GoogleFonts.poppins(
                    fontSize: 11.5,
                    color: Colors.black54,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(30),
                  child: Text(
                    'No hands raised right now.',
                    style: GoogleFonts.poppins(
                      color: Colors.black45,
                      fontSize: 13,
                    ),
                  ),
                )
              else
                Flexible(
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(12, 4, 12, 16),
                    itemCount: list.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (_, i) {
                      final h = list[i];
                      return Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F9FC),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: const Color(0xFFE3E9F1)),
                        ),
                        child: Row(
                          children: [
                            CircleAvatar(
                              radius: 17,
                              backgroundColor: _amber.withOpacity(.15),
                              child: Text(
                                '${i + 1}',
                                style: GoogleFonts.poppins(
                                  color: _amber,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    h.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.poppins(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: _deepNavy,
                                    ),
                                  ),
                                  Text(
                                    _ago(h.at),
                                    style: GoogleFonts.poppins(
                                      fontSize: 10.5,
                                      color: Colors.black45,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              tooltip: 'Lower hand',
                              onPressed: () => cc.lowerHand(h.id),
                              icon: const Icon(
                                Icons.pan_tool_alt_outlined,
                                color: Colors.black45,
                                size: 20,
                              ),
                            ),
                            _smallButton(
                              'Allow',
                              _green,
                              () => cc.allowHand(h),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        }),
      ),
    ),
  );
}

// -------------------------------------------------------------------------
// 💬 Top-bar button with unread badge
// -------------------------------------------------------------------------
class ClassChatAction extends StatelessWidget {
  final ClassroomController cc;
  const ClassChatAction({super.key, required this.cc});

  @override
  Widget build(BuildContext context) {
    return Obx(() {
      final n = cc.unreadMessages.value;
      return IconButton(
        tooltip: 'Student questions',
        onPressed: () => showClassChatSheet(context, cc),
        icon: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.chat_bubble_outline_rounded, size: 22),
            if (n > 0)
              Positioned(
                right: -7,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    n > 99 ? '99+' : '$n',
                    style: GoogleFonts.poppins(
                      color: Colors.white,
                      fontSize: 9,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        ),
      );
    });
  }
}

Future<void> showClassChatSheet(
  BuildContext context,
  ClassroomController cc,
) async {
  cc.chatOpen = true;
  cc.unreadMessages.value = 0;
  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
    ),
    builder: (ctx) => _ChatSheet(cc: cc),
  );
  cc.chatOpen = false;
  cc.unreadMessages.value = 0;
}

class _ChatSheet extends StatefulWidget {
  final ClassroomController cc;
  const _ChatSheet({required this.cc});

  @override
  State<_ChatSheet> createState() => _ChatSheetState();
}

class _ChatSheetState extends State<_ChatSheet> {
  final TextEditingController _text = TextEditingController();
  final ScrollController _scroll = ScrollController();
  ClassChatMsg? _replyTo; // null → message to the whole class
  bool _sending = false;
  Worker? _worker;

  ClassroomController get cc => widget.cc;

  @override
  void initState() {
    super.initState();
    _worker = ever(cc.messages, (_) => _toBottom());
    _toBottom();
  }

  @override
  void dispose() {
    _worker?.dispose();
    _text.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _toBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final t = _text.text.trim();
    if (t.isEmpty || _sending) return;
    setState(() => _sending = true);
    final r = _replyTo;
    final ok = r == null
        ? await cc.sendClassMessage(t)
        : await cc.replyTo(r.fromId, r.fromName, t);
    if (!mounted) return;
    setState(() {
      _sending = false;
      if (ok) {
        _text.clear();
        _replyTo = null;
      }
    });
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not send. Check your internet.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: bottom),
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.of(context).size.height * .72,
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.black12,
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 18, 8),
                child: Row(
                  children: [
                    const Icon(
                      Icons.chat_bubble_rounded,
                      color: _navy,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Class messages',
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                        color: _deepNavy,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Obx(() {
                  final list = cc.messages.toList();
                  if (list.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(28),
                        child: Text(
                          'Students\' questions will appear here.\nTap a question to reply only to that student.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.poppins(
                            color: Colors.black45,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scroll,
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
                    itemCount: list.length,
                    itemBuilder: (_, i) => _bubble(list[i]),
                  );
                }),
              ),
              if (_replyTo != null)
                Container(
                  color: const Color(0xFFEAF2F8),
                  padding: const EdgeInsets.fromLTRB(14, 6, 4, 6),
                  child: Row(
                    children: [
                      const Icon(Icons.reply_rounded, size: 16, color: _navy),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Reply only to ${_replyTo!.fromName}',
                          style: GoogleFonts.poppins(
                            fontSize: 12,
                            color: _navy,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        onPressed: () => setState(() => _replyTo = null),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _text,
                        maxLength: 300,
                        minLines: 1,
                        maxLines: 3,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _send(),
                        // ✍️ typed letters: dark & clear on the light box (theme made them white / pale)
                        style: GoogleFonts.poppins(
                          fontSize: 14,
                          color: _deepNavy,
                          fontWeight: FontWeight.w500,
                        ),
                        cursorColor: _navy,
                        decoration: InputDecoration(
                          counterText: '',
                          hintText: _replyTo == null
                              ? 'Message to the whole class…'
                              : 'Your reply…',
                          hintStyle: GoogleFonts.poppins(
                            fontSize: 13,
                            color: Colors.black38,
                          ),
                          filled: true,
                          fillColor: const Color(0xFFF2F5F9),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: Color(0xFFE3E9F1),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: const BorderSide(
                              color: _teal,
                              width: 1.4,
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton.filled(
                      style: IconButton.styleFrom(backgroundColor: _teal),
                      onPressed: _sending ? null : _send,
                      icon: _sending
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _bubble(ClassChatMsg m) {
    return Align(
      alignment: m.mine ? Alignment.centerRight : Alignment.centerLeft,
      child: GestureDetector(
        onTap: m.mine ? null : () => setState(() => _replyTo = m),
        child: Container(
          margin: const EdgeInsets.only(bottom: 8),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * .75,
          ),
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          decoration: BoxDecoration(
            color: m.mine ? _navy : const Color(0xFFF2F5F9),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${m.fromName} • ${_clock(m.at)}',
                style: GoogleFonts.poppins(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: m.mine ? Colors.white70 : _navy,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                m.text,
                style: GoogleFonts.poppins(
                  fontSize: 13,
                  color: m.mine ? Colors.white : _deepNavy,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
