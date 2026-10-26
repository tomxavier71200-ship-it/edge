// A detected workout's EDGES, trimmed where the wrist was walking.
//
// The detector ends a bout when heart rate comes back down, and heart rate
// stays up for a while after a ride — so a walk home after cycling became the
// ride's last 20 minutes (owner, 26 Oct 2026: rode 13:35–13:48, then walked at
// 75–108 steps/min with HR 125–150 until 14:08; the bout read 13:30–14:12).
// The band's own step counter says which minutes were gait.
//
// Only for a bout that is NOT itself gait: when most of its minutes are at
// walking pace it is a walk or a run, and nothing is trimmed. Steps absent
// (gen4 bands have no counter) → no evidence → no trim.

/// Steps per minute at or above which a minute counts as walking.
const int kGaitCadenceSpm = 40;

/// Consecutive walking minutes that end a non-gait bout.
const int kGaitRunMin = 3;

/// A bout that is gait in at least this share of its minutes is left alone.
const double kGaitBoutShare = .6;

/// The shortest bout a trim may leave; shorter, and the bout is kept as is.
const int kTrimMinMinutes = 10;

/// The trimmed minute range `[first, end)` of a bout whose per-minute step
/// cadence is [spm] (null = no counter that minute), or null for "keep the
/// bout as detected".
({int first, int end})? trimGaitEdges(List<int?> spm) {
  if (spm.isEmpty || spm.any((c) => c == null)) return null;
  bool gait(int i) => spm[i]! >= kGaitCadenceSpm;
  final gaitMin = [for (var i = 0; i < spm.length; i++) if (gait(i)) i].length;
  if (gaitMin >= kGaitBoutShare * spm.length) return null;

  var first = 0;
  while (first < spm.length && gait(first)) {
    first++;
  }
  var end = spm.length;
  for (var i = first; i + kGaitRunMin <= spm.length; i++) {
    if (List.generate(kGaitRunMin, (k) => gait(i + k)).every((g) => g)) {
      end = i;
      break;
    }
  }
  if (end - first < kTrimMinMinutes) return null;
  if (first == 0 && end == spm.length) return null;
  return (first: first, end: end);
}
