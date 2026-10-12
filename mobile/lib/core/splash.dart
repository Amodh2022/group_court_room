import 'package:flutter/material.dart';

import 'theme.dart';

/// Shown while the stored session is being read.
///
/// This is the sign-in gate. Until auth resolves we must not build *any*
/// route: a protected screen would otherwise mount, fire its requests
/// unauthenticated, and show the user an error for a question we had simply
/// not finished answering.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('⚖️', style: TextStyle(fontSize: 56)),
          const SizedBox(height: 20),
          Text(
            'SUE ME',
            style: context.text.labelSmall?.copyWith(fontSize: 13),
          ),
          const SizedBox(height: 28),
          SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: context.palette.accent,
            ),
          ),
        ],
      ),
    ),
  );
}
