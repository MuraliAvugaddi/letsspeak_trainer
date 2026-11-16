// =========================================================================
// 🔊 CLASS SOUND — choose where to hear the class + how loud
//   Speaker • Phone (ear, like a call) • Bluetooth • Headphones
//   Bluetooth / earphones connected → the sound goes there by itself.
// 🎓 TRAINER LOGO — trainers show the Let's Speak logo instead of a letter
// 📶 WEAK INTERNET — small badge / banner
// =========================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:letsspeak_trainer/rtc/live_room.dart';

const String kTrainerLogoAsset = 'assets/images/class_logo.png';

const Color _navy = Color(0xFF155A88);
const Color _teal = Color(0xFF28C2C2);
const Color _text = Color(0xFF16324A);
const Color _muted = Color(0xFF667F95);
const Color _line = Color(0xFFE3ECF3);

IconData classSoundIcon(SoundOut o) {
  switch (o) {
    case SoundOut.speaker:
      return Icons.volume_up_rounded;
    case SoundOut.phone:
      return Icons.phone_in_talk_rounded;
    case SoundOut.bluetooth:
      return Icons.bluetooth_audio_rounded;
    case SoundOut.headset:
      return Icons.headphones_rounded;
  }
}

String _hint(SoundOut o) {
  switch (o) {
    case SoundOut.speaker:
      return 'Loud speaker of the phone';
    case SoundOut.phone:
      return 'Hold the phone to your ear, like a call';
    case SoundOut.bluetooth:
      return 'Your wireless earphones';
    case SoundOut.headset:
      return 'Your wired earphones';
  }
}

/// App bar button: shows where the sound plays now. Tap → choose.
class ClassSoundButton extends StatelessWidget {
  final Color color;
  final double size;
  const ClassSoundButton({super.key, required this.color, this.size = 22});

  @override
  Widget build(BuildContext context) {
    if (!ClassSound.supported) return const SizedBox.shrink();
    return ValueListenableBuilder<SoundOut>(
      valueListenable: ClassSound.route,
      builder: (context, r, _) => IconButton(
        tooltip: 'Sound: ${ClassSound.label(r)}',
        onPressed: () => showClassSoundSheet(context),
        icon: Icon(classSoundIcon(r), color: color, size: size),
      ),
    );
  }
}

void showClassSoundSheet(BuildContext context) {
  ClassSound.refresh();
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.white,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (_) => const _SoundSheet(),
  );
}

class _SoundSheet extends StatelessWidget {
  const _SoundSheet();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([
        ClassSound.route,
        ClassSound.choices,
        ClassSound.level,
        ClassSound.bluetoothName,
      ]),
      builder: (context, _) {
        final route = ClassSound.route.value;
        final choices = ClassSound.choices.value;
        final level = ClassSound.level.value;
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(color: _line, borderRadius: BorderRadius.circular(4)),
                  ),
                ),
                const SizedBox(height: 14),
                Text('Sound', style: GoogleFonts.poppins(color: _text, fontSize: 17, fontWeight: FontWeight.w800)),
                Text(
                  'Where do you want to hear the class?',
                  style: GoogleFonts.poppins(color: _muted, fontSize: 12, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 12),
                for (final o in choices) _option(o, o == route),
                const SizedBox(height: 14),
                Text('Voice volume', style: GoogleFonts.poppins(color: _text, fontSize: 13.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    for (int i = 0; i < 3; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      Expanded(child: _levelChip(i, i == level)),
                    ],
                  ],
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF2F8FC),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, size: 16, color: _navy),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Bluetooth or earphones connected? The class sound goes there by itself.',
                          style: GoogleFonts.poppins(color: _muted, fontSize: 11, height: 1.35),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _option(SoundOut o, bool selected) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected ? _teal.withOpacity(.10) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => ClassSound.select(o),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: selected ? _teal : _line, width: selected ? 1.6 : 1),
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: selected ? _teal : _navy.withOpacity(.08),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(classSoundIcon(o), size: 19, color: selected ? Colors.white : _navy),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ClassSound.label(o),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(color: _text, fontSize: 13.5, fontWeight: FontWeight.w700),
                      ),
                      Text(
                        _hint(o),
                        style: GoogleFonts.poppins(color: _muted, fontSize: 11, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
                if (selected) const Icon(Icons.check_circle_rounded, color: _teal, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _levelChip(int i, bool selected) {
    return Material(
      color: selected ? _navy : Colors.white,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => ClassSound.setLevel(i),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: selected ? _navy : _line),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                const [Icons.volume_down_rounded, Icons.volume_up_rounded, Icons.campaign_rounded][i],
                size: 16,
                color: selected ? Colors.white : _navy,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  ClassSound.levelLabel(i),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.poppins(
                    color: selected ? Colors.white : _text,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 🎓 Trainer picture in the class = Let's Speak logo (not the first letter)
class TrainerLogoAvatar extends StatelessWidget {
  final double radius;
  final bool ring;
  final Color ringColor;
  const TrainerLogoAvatar({super.key, required this.radius, this.ring = false, this.ringColor = _teal});

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.all(ring ? 2 : 0),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: ring ? Border.all(color: ringColor, width: 2.5) : null,
      ),
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          border: Border.all(color: _line),
        ),
        child: ClipOval(
          child: Image.asset(
            kTrainerLogoAsset,
            width: size,
            height: size,
            fit: BoxFit.cover,
            cacheWidth: (size * 3).round(), // small copy in memory (the file is big)
            errorBuilder: (_, __, ___) => Icon(Icons.school_rounded, color: _navy, size: radius),
          ),
        ),
      ),
    );
  }
}

/// 📶 small "weak internet" badge (wifi with a slash)
class WeakNetDot extends StatelessWidget {
  final double size;
  const WeakNetDot({super.key, this.size = 18});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Weak internet',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xFFE85D5D),
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white, width: 1.5),
        ),
        child: Icon(Icons.signal_wifi_bad_rounded, size: size * .58, color: Colors.white),
      ),
    );
  }
}
