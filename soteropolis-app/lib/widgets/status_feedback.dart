import 'package:flutter/material.dart';

import '../config/theme.dart';

/// Full-width banner giving immediate, unambiguous visual feedback for a
/// success or error state (SPEC: "immediate visual feedback on every
/// action" is an explicit accessibility requirement, not optional polish).
class StatusBanner extends StatelessWidget {
  const StatusBanner.success({super.key, required this.message})
    : _isError = false;

  const StatusBanner.error({super.key, required this.message})
    : _isError = true;

  final String message;
  final bool _isError;

  @override
  Widget build(BuildContext context) {
    final color = _isError ? AppTheme.error : AppTheme.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color, width: 2),
      ),
      child: Row(
        children: [
          Icon(
            _isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 28,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Centered loading state with an optional label, for whole-screen waits
/// (e.g. fetching ecopontos, submitting a descarte).
class LoadingState extends StatelessWidget {
  const LoadingState({super.key, this.label});

  final String? label;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const CircularProgressIndicator(),
          if (label != null) ...[
            const SizedBox(height: 16),
            Text(label!, style: const TextStyle(fontSize: 18)),
          ],
        ],
      ),
    );
  }
}
