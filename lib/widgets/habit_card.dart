import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/habit_summary.dart';

const Color _secondaryText = Color(0xFF8A8A8A);
const Color _cardBorder = Color(0xFFEDEDED);
const Color _successGreen = Color(0xFF4CAF50);
const Color _accent = Color(0xFF6FA37B); // one color for all the habits




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
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: done ? _successGreen.withOpacity(0.4) : _cardBorder,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: done ? _successGreen : _accent.withOpacity(0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(
                done ? Icons.check : Icons.camera_alt_outlined,
                color: done ? Colors.white : _accent,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                habit.name,
                style: GoogleFonts.poppins(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: done ? _successGreen : const Color(0xFF2E2E2E),
                ),
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_fire_department, size: 14, color: Color(0xFFF0B8AE)),
                    const SizedBox(width: 2),
                    Text('${habit.streak}', style: GoogleFonts.poppins(fontSize: 12, color: _secondaryText)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '+${habit.xpValue} XP',
                  style: GoogleFonts.poppins(fontSize: 11, fontWeight: FontWeight.w600, color: _accent),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
 