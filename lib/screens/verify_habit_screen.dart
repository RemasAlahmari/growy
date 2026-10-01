import 'dart:typed_data';
 
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import '../services/verification_service.dart';
import '../models/habit_summary.dart';

import '../theme/app_theme.dart';
 
const Color _secondaryText = Color(0xFF8A8A8A);
const Color _errorColor = Color(0xFFD9534F);

/// Opened from a habit card on Home. The user takes or picks a photo,
/// the backend checks it with CLIP, and the result is shown here.
/// Home reloads its data when this screen closes.
class VerifyHabitScreen extends StatefulWidget {
  const VerifyHabitScreen({super.key, required this.habit});
 
  final HabitSummary habit;
 
  @override
  State<VerifyHabitScreen> createState() => _VerifyHabitScreenState();
}

class _VerifyHabitScreenState extends State<VerifyHabitScreen> {
  final ImagePicker _picker = ImagePicker();
  final VerificationService _service = VerificationService();
 
  XFile? _photo;
  Uint8List? _photoBytes; // for the preview (works on Android and web)
  bool _isSubmitting = false;
  VerificationResult? _result;
  String? _error;
 
  bool get _isVerified => _result?.isVerified ?? false;
 
  Future<void> _pickPhoto(ImageSource source) async {
    try {
      // Resize before upload: CLIP only looks at a small image anyway,
      // and smaller files upload much faster.
      final photo = await _picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 80,
      );
      if (photo == null) return; // user cancelled
 
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = photo;
        _photoBytes = bytes;
        _result = null;
        _error = null;
      });
    } catch (e) {
      debugPrint('Image pick failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Could not open the camera or gallery.');
    }
  }
 
  Future<void> _submit() async {
    final photo = _photo;
    if (photo == null) return;
 
    setState(() {
      _isSubmitting = true;
      _error = null;
      _result = null;
    });
 
    try {
      final result = await _service.submitPhoto(
        habitId: widget.habit.id,
        photo: photo,
      );
      if (!mounted) return;
      setState(() => _result = result);
    } on VerificationException catch (e) {
      if (!mounted) return;
      setState(() => _error = e.message);
    } catch (e) {
      debugPrint('Verification failed: $e');
      if (!mounted) return;
      setState(() => _error = 'Something went wrong. Please try again.');
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }
 
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textDark),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          children: [
            Text(
              widget.habit.name,
              style: GoogleFonts.fraunces(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: AppColors.textDark,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Verify with a photo to earn ${widget.habit.xpValue} XP',
              style: GoogleFonts.poppins(fontSize: 13, color: _secondaryText),
            ),
            const SizedBox(height: 20),
            _InstructionCard(label: widget.habit.category),
            const SizedBox(height: 20),
            _PhotoPreview(bytes: _photoBytes),
            const SizedBox(height: 16),
            if (!_isVerified)
              Row(
                children: [
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.photo_camera_outlined,
                      label: 'Camera',
                      onPressed: _isSubmitting
                          ? null
                          : () => _pickPhoto(ImageSource.camera),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _SourceButton(
                      icon: Icons.photo_library_outlined,
                      label: 'Gallery',
                      onPressed: _isSubmitting
                          ? null
                          : () => _pickPhoto(ImageSource.gallery),
                    ),
                  ),
                ],
              ),
            if (_result != null) ...[
              const SizedBox(height: 20),
              _ResultBanner(result: _result!),
            ],
            if (_error != null) ...[
              const SizedBox(height: 16),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: GoogleFonts.poppins(fontSize: 13, color: _errorColor),
              ),
            ],
            const SizedBox(height: 24),
            _PrimaryButton(
              label: _isVerified ? 'Back to Home' : 'Verify Photo',
              isLoading: _isSubmitting,
              onPressed: _isVerified
                  ? () => Navigator.pop(context)
                  : (_photo == null || _isSubmitting ? null : _submit),
            ),
          ],
        ),
      ),
    );
  }
}
 
class _InstructionCard extends StatelessWidget {
  const _InstructionCard({required this.label});
 
  final String label; // the habit's CLIP label, e.g. "a person reading a book"
 
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.10),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Take a clear photo showing:',
            style: GoogleFonts.poppins(fontSize: 13, color: _secondaryText),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: GoogleFonts.poppins(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppColors.textDark,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Good light and the main subject in the middle work best.',
            style: GoogleFonts.poppins(fontSize: 12, color: _secondaryText),
          ),
        ],
      ),
    );
  }
}
 
class _PhotoPreview extends StatelessWidget {
  const _PhotoPreview({required this.bytes});
 
  final Uint8List? bytes;
 
  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Container(
          color: const Color(0xFFF4F4F4),
          child: bytes == null
              ? Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.add_a_photo_outlined,
                      size: 40,
                      color: _secondaryText,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'No photo yet',
                      style: GoogleFonts.poppins(
                        fontSize: 13,
                        color: _secondaryText,
                      ),
                    ),
                  ],
                )
              : Image.memory(bytes!, fit: BoxFit.cover),
        ),
      ),
    );
  }
}
 
class _SourceButton extends StatelessWidget {
  const _SourceButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });
 
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
 
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, color: AppColors.primary),
        label: Text(
          label,
          style: GoogleFonts.poppins(
            fontWeight: FontWeight.w600,
            color: AppColors.textDark,
          ),
        ),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFD8D8D8)),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
      ),
    );
  }
}
 
class _ResultBanner extends StatelessWidget {
  const _ResultBanner({required this.result});
 
  final VerificationResult result;
 
  @override
  Widget build(BuildContext context) {
    final passed = result.isVerified;
    final color = passed ? AppColors.primary : _errorColor;
    final confidence = result.confidence;
 
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            passed ? Icons.check_circle : Icons.cancel,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  passed
                      ? 'Verified! +${result.pointsEarned} XP'
                      : "Couldn't verify this photo",
                  style: GoogleFonts.poppins(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  passed
                      ? 'Nice work, your avatar is growing.'
                      : 'Try a clearer photo that shows the habit.',
                  style: GoogleFonts.poppins(
                    fontSize: 12,
                    color: _secondaryText,
                  ),
                ),
                // Helpful while tuning CLIP labels and thresholds;
                // remove before the final demo if you prefer.
                if (result.predictedLabel != null && confidence != null) ...[
                  const SizedBox(height: 6),
                  Text(
                    'Detected: ${result.predictedLabel} '
                    '(${(confidence * 100).toStringAsFixed(0)}%)',
                    style: GoogleFonts.poppins(
                      fontSize: 11,
                      color: _secondaryText,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
 
class _PrimaryButton extends StatelessWidget {
  const _PrimaryButton({
    required this.label,
    required this.isLoading,
    required this.onPressed,
  });
 
  final String label;
  final bool isLoading;
  final VoidCallback? onPressed;
 
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.primary.withOpacity(0.4),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : Text(
                label,
                style: GoogleFonts.fraunces(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
      ),
    );
  }
}