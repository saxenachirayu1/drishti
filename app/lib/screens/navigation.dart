import 'package:flutter/material.dart';

import 'home_shell.dart';
import 'impact_screen.dart';
import 'raise_screen.dart';
import 'track_screen.dart';

/// Opens the app on a tab: 'map', 'raise', 'track', 'impact', 'console', ...
void openShell(BuildContext context, String tab) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => HomeShell(initialTab: tab)));

void openRaise(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const RaiseScreen(standalone: true)));

void openTrack(BuildContext context, {String? reportId, String? code}) => Navigator.of(context).push(
  MaterialPageRoute<void>(
    builder: (_) => TrackScreen(standalone: true, reportId: reportId, code: code),
  ),
);

void openImpact(BuildContext context) =>
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ImpactScreen(standalone: true)));
