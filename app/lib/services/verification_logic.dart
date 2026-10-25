/// Clean-up verification (C-12), the same rules as api/app/services/verification.py:
///  - no detection in the last [clearScenes] scenes -> cleared
///  - newest area below [shrinkRatio] x the first area -> shrinking
///  - otherwise -> still_present
/// [areas] are oldest first; 0 means the site was not detected in that scene.
String decideResult(List<double> areas, {int clearScenes = 2, double shrinkRatio = 0.8}) {
  if (areas.isEmpty) return 'still_present';
  final recent = areas.length > clearScenes ? areas.sublist(areas.length - clearScenes) : areas;
  if (recent.length >= clearScenes && recent.every((a) => a == 0)) return 'cleared';
  final present = areas.where((a) => a > 0).toList();
  if (present.length >= 2 && present.last < present.first * shrinkRatio) return 'shrinking';
  return 'still_present';
}
