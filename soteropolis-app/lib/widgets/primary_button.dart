import 'package:flutter/material.dart';

/// Large, high-contrast call-to-action button used across every screen.
///
/// Shows its own loading spinner in place of the label and disables itself
/// while [isLoading] is true, so every action gets immediate visual
/// feedback and can't be double-tapped mid-request (relevant for
/// /descartes and /resgates, where a double submit is exactly what the
/// idempotency-key handling exists to protect against - this button is the
/// first line of defense, not a replacement for it).
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: isLoading ? null : onPressed,
      child: isLoading
          ? const SizedBox(
              height: 24,
              width: 24,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: Colors.white,
              ),
            )
          : Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[Icon(icon), const SizedBox(width: 10)],
                Text(label),
              ],
            ),
    );
  }
}
