import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/reminder_service.dart';
import '../theme/app_theme.dart';

/// "Daily reminder" card for the Me page: an on/off switch and a time.
/// Self-contained: drop `const ReminderSettingsCard()` anywhere.
class ReminderSettingsCard extends StatefulWidget {
  const ReminderSettingsCard({super.key});

  @override
  State<ReminderSettingsCard> createState() => _ReminderSettingsCardState();
}

class _ReminderSettingsCardState extends State<ReminderSettingsCard> {
  ReminderSettings? _settings;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    ReminderService.loadSettings().then((s) {
      if (mounted) setState(() => _settings = s);
    });
  }

  void _toast(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _save(ReminderSettings next) async {
    setState(() {
      _busy = true;
      _settings = next;
    });
    await ReminderService.saveSettings(next);
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _toggle(bool on) async {
    final current = _settings;
    if (current == null) return;
    if (on) {
      final allowed = await ReminderService.requestPermission();
      if (!allowed) {
        _toast('Allow notifications for Growy in your phone settings.');
        return;
      }
    }
    await _save(current.copyWith(enabled: on));
    if (on && mounted) {
      _toast('Reminder set for ${_timeText(current)} every day.');
    }
  }

  Future<void> _pickTime() async {
    final current = _settings;
    if (current == null) return;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current.hour, minute: current.minute),
    );
    if (picked == null) return;
    await _save(current.copyWith(hour: picked.hour, minute: picked.minute));
  }

  String _timeText(ReminderSettings s) =>
      TimeOfDay(hour: s.hour, minute: s.minute).format(context);

  @override
  Widget build(BuildContext context) {
    final s = _settings;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 8, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: GrowyPalette.cardBorder),
      ),
      child: s == null
          ? const Padding(
              padding: EdgeInsets.all(12),
              child: Center(child: CircularProgressIndicator()),
            )
          : Column(
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.notifications_active_outlined,
                      color: AppColors.primary,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Daily reminder',
                            style: GoogleFonts.poppins(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: AppColors.textDark,
                            ),
                          ),
                          Text(
                            s.enabled
                                ? 'Every day at ${_timeText(s)}. Skipped when '
                                    "you've finished all your habits."
                                : 'Off',
                            style: GoogleFonts.poppins(
                              fontSize: 12,
                              color: GrowyPalette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Switch(
                      value: s.enabled,
                      activeColor: AppColors.primary,
                      onChanged: _busy ? null : _toggle,
                    ),
                  ],
                ),
                if (s.enabled) ...[
                  const Divider(height: 1),
                  InkWell(
                    onTap: _busy ? null : _pickTime,
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(36, 12, 8, 12),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Reminder time',
                              style: GoogleFonts.poppins(
                                fontSize: 13,
                                color: AppColors.textDark,
                              ),
                            ),
                          ),
                          Text(
                            _timeText(s),
                            style: GoogleFonts.poppins(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: AppColors.primary,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            color: GrowyPalette.textSecondary,
                          ),
                        ],
                      ),
                    ),
                  ),
                  // Only in debug builds: quick way to check it works.
                  if (kDebugMode)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextButton(
                        onPressed: () async {
                          await ReminderService.sendTestReminder();
                          _toast('Test reminder in about 1 minute. '
                              'You can close the app.');
                        },
                        child: const Text('Send a test reminder'),
                      ),
                    ),
                ],
              ],
            ),
    );
  }
}