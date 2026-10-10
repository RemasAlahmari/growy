import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../core/motion/motion.dart';
import '../theme/app_theme.dart';

/// Growy logo badge; falls back to a placeholder until assets/images/growy_logo.png exists.
class GrowyLogo extends StatelessWidget {
  final double width;
  final double height;
  const GrowyLogo({super.key, required this.width, required this.height});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/images/growy_logo.png',
      width: width,
      height: height,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => SizedBox(
        width: width,
        height: height,
        child: Icon(Icons.emoji_people, color: AppColors.primary, size: 48),
      ),
    );
  }
}

class GrowyPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback onPressed;
  final double width;
  final double height;
  final double fontSize;

  const GrowyPrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.width = double.infinity,
    this.height = 54,
    this.fontSize = 17,
  });

  @override
  Widget build(BuildContext context) {
    return GrowyPressEffect(
      child: Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          elevation: 0,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          label,
          style: GoogleFonts.fraunces(
            color: Colors.white,
            fontWeight: FontWeight.w700,
            fontSize: fontSize,
            letterSpacing: 0.2,
          ),
        ),
      ),
      ),
    );
  }
}

/// Label above the field, 54px tall outlined input with prefix icon.
class GrowyField extends StatelessWidget {
  final String label;
  final String hint;
  final IconData icon;
  final TextEditingController? controller;
  final TextInputType? keyboardType;
  final bool isPassword;
  final bool obscure;
  final VoidCallback? onToggleObscure;

  const GrowyField({
    super.key,
    required this.label,
    required this.hint,
    required this.icon,
    this.controller,
    this.keyboardType,
    this.isPassword = false,
    this.obscure = false,
    this.onToggleObscure,
  });

  OutlineInputBorder _border(Color color, double width) => OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: color, width: width),
      );

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          controller: controller,
          keyboardType: keyboardType,
          obscureText: isPassword && obscure,
          textAlignVertical: TextAlignVertical.center,
          style: GoogleFonts.poppins(fontSize: 16, color: AppColors.mainText),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: GoogleFonts.poppins(fontSize: 16, color: AppColors.placeholder),
            prefixIcon: Icon(icon, color: AppColors.secondaryText, size: 20),
            suffixIcon: isPassword
                ? IconButton(
                    icon: Icon(
                      obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                      color: AppColors.secondaryText,
                      size: 20,
                    ),
                    onPressed: onToggleObscure,
                  )
                : null,
            filled: true,
            fillColor: AppColors.inputFill,
            constraints: const BoxConstraints(minHeight: 54, maxHeight: 54),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16),
            enabledBorder: _border(AppColors.border, 1),
            focusedBorder: _border(AppColors.primary, 1.5),
          ),
        ),
      ],
    );
  }
}

enum GrowyGender { male, female }

extension GrowyGenderApi on GrowyGender {
  /// Value sent to the backend.
  String get apiValue => name; // 'male' / 'female'
  String get label => this == GrowyGender.male ? 'Male' : 'Female';
  IconData get icon =>
      this == GrowyGender.male ? Icons.male_rounded : Icons.female_rounded;
}

/// "Gender" label with two choice tiles, styled like [GrowyField].
class GrowyGenderPicker extends StatelessWidget {
  final GrowyGender? value;
  final ValueChanged<GrowyGender> onChanged;
  final String? errorText;

  const GrowyGenderPicker({
    super.key,
    required this.value,
    required this.onChanged,
    this.errorText,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Gender',
          style: GoogleFonts.poppins(
            fontSize: 13,
            fontWeight: FontWeight.w500,
            color: AppColors.secondaryText,
          ),
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            for (final g in GrowyGender.values) ...[
              if (g != GrowyGender.values.first) const SizedBox(width: 12),
              Expanded(child: _GenderTile(
                gender: g,
                selected: value == g,
                hasError: errorText != null,
                onTap: () => onChanged(g),
              )),
            ],
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 200),
          alignment: Alignment.topLeft,
          child: errorText == null
              ? const SizedBox(width: double.infinity)
              : Padding(
                  padding: const EdgeInsets.only(top: 6, left: 4),
                  child: Text(
                    errorText!,
                    style: GoogleFonts.poppins(
                      fontSize: 12,
                      color: GrowyPalette.error,
                    ),
                  ),
                ),
        ),
      ],
    );
  }
}

class _GenderTile extends StatelessWidget {
  final GrowyGender gender;
  final bool selected;
  final bool hasError;
  final VoidCallback onTap;

  const _GenderTile({
    required this.gender,
    required this.selected,
    required this.hasError,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = selected
        ? AppColors.primary
        : (hasError ? GrowyPalette.error : AppColors.border);
    final foreground = selected ? AppColors.primary : AppColors.secondaryText;
    final radius = BorderRadius.circular(12);

    return Semantics(
      button: true,
      selected: selected,
      label: gender.label,
      excludeSemantics: true,
      child: GrowyPressEffect(
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              height: 54,
              decoration: BoxDecoration(
                color: selected ? GrowyPalette.primaryTint : AppColors.inputFill,
                borderRadius: radius,
                border: Border.all(color: borderColor, width: selected ? 1.5 : 1),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(gender.icon, size: 20, color: foreground),
                  const SizedBox(width: 6),
                  Text(
                    gender.label,
                    style: GoogleFonts.poppins(
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      color: selected ? AppColors.primary : AppColors.mainText,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Prefix Link" footer row.
class GrowyFooterLink extends StatelessWidget {
  final String prefix;
  final String link;
  final VoidCallback onTap;
  const GrowyFooterLink({
    super.key,
    required this.prefix,
    required this.link,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Text.rich(
        TextSpan(
          text: '$prefix ',
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.secondaryText,
          ),
          children: [
            TextSpan(
              text: link,
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class GrowyTitle extends StatelessWidget {
  final String title;
  final String subtitle;
  final double gap;
  const GrowyTitle({
    super.key,
    required this.title,
    required this.subtitle,
    required this.gap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        SizedBox(height: gap),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.fraunces(
            fontSize: 26,
            fontWeight: FontWeight.w700,
            color: AppColors.mainText,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.poppins(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: AppColors.secondaryText,
          ),
        ),
      ],
    );
  }
}

/// One decorative low-opacity circle, placed via Positioned inside a Stack.
class GrowyCircle extends StatelessWidget {
  final Color color;
  final double size;
  final double? left, right, top, bottom;
  const GrowyCircle({
    super.key,
    required this.color,
    required this.size,
    this.left,
    this.right,
    this.top,
    this.bottom,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: left,
      right: right,
      top: top,
      bottom: bottom,
      child: IgnorePointer(
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.2),
          ),
        ),
      ),
    );
  }
}

/// The slowly drifting green + peach circles at the bottom of Login and
/// Sign Up (see core/motion/growy_background_blobs.dart).
List<Widget> bottomCircles() => const [
      Positioned.fill(
        child: GrowyBackgroundBlobs(preset: GrowyBlobPreset.auth),
      ),
    ];