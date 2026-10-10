import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/habit_summary.dart';
import '../theme/app_theme.dart';

Color get _secondaryText => GrowyPalette.textSecondary;
Color get _cardBorder => GrowyPalette.cardBorder;
Color get _successGreen => GrowyPalette.success;
Color get _accent => GrowyPalette.primary;

class HabitCard extends StatelessWidget {
  const HabitCard({super.key, required this.habit, required this.onTap});

  final HabitSummary habit;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final done = habit.completedToday;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      // Border and icon change smoothly when the habit becomes done.
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: done ? _successGreen.withOpacity(0.4) : _cardBorder,
          ),
        ),
        child: Row(
          children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: done ? _successGreen : _accent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOutBack,
                transitionBuilder: (child, animation) =>
                    ScaleTransition(scale: animation, child: child),
                child: Icon(
                  done ? Icons.check : Icons.camera_alt_outlined,
                  key: ValueKey(done),
                  color: done ? Colors.white : _accent,
                  size: 20,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                habit.name,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: done ? _successGreen : GrowyPalette.textMain,
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      size: 14,
                      color: Color(0xFFF0B8AE),
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${habit.streak}',
                      style: GoogleFonts.poppins(
                        fontSize: 12,
                        color: _secondaryText,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '+${habit.xpValue} XP',
                  style: GoogleFonts.poppins(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _accent,
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
