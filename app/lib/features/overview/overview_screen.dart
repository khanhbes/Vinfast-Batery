import 'package:flutter/material.dart';

import '../home/home_screen.dart';

/// V4 Overview entry point.
///
/// The existing Home surface remains the source of truth for vehicle battery
/// and insight widgets. Keeping this thin adapter lets navigation use the V4
/// information architecture without duplicating the established domain UI.
class OverviewScreen extends StatelessWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context) => const HomeScreen();
}
