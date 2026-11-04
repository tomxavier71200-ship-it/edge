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

/// Cycling keeps the wrist comparatively still and does not accumulate real
/// foot steps. Walking to/from the bicycle is normally above one or both of
/// these limits.
const double kCyclingMotionMax = .20;
const int kCyclingStepMax = 39;

/// A ten-minute seed may contain a few potholes, wrist gestures, or false
/// on-wrist step increments. Requiring every minute would cut real rides.
const int kCyclingSeedMinutes = 10;
const int kCyclingSeedEvidenceMinutes = 7;
const int kCyclingSeedHighHrMinutes = 5;
const int kCyclingSeedStepObservedMinutes = 3;
const int kEdgeStopMinutes = 3;

/// The trimmed minute range `[first, end)` of a bout whose per-minute step
/// cadence is [spm] (null = no counter that minute), or null for "keep the
/// bout as detected".
({int first, int end})? trimGaitEdges(
  List<int?> spm, {
  List<double?>? motion,
  List<bool?>? training,
  List<bool?>? highHr,
  bool cyclingOnly = false,
}) {
  if (spm.isEmpty) return null;
  final hasTraining = training != null && training.length == spm.length;
  bool gait(int i) => spm[i] != null && spm[i]! >= kGaitCadenceSpm;
  final observedStepMin = spm.whereType<int>().length;
  final gaitMin = [
    for (var i = 0; i < spm.length; i++)
      if (gait(i)) i,
  ].length;
  if (observedStepMin > 0 && gaitMin >= kGaitBoutShare * observedStepMin) {
    return null;
  }

  // Prefer the actual low-motion/no-footstep cycling block when the recording
  // contains enough evidence to identify one. HR alone cannot do this: it rises
  // during the walk in and stays high during the walk out. A short rolling seed
  // tolerates handlebar bumps and false wrist-counter increments, then three
  // consecutive non-cycling or recovered-HR minutes define the edge.
  final hasMotion = motion != null && motion.length == spm.length;
  final hasHighHr = highHr != null && highHr.length == spm.length;
  if (hasMotion && hasHighHr) {
    bool cycling(int i) =>
        motion[i] != null &&
        motion[i]! <= kCyclingMotionMax &&
        (spm[i] == null || spm[i]! <= kCyclingStepMax);

    int? seedStart;
    for (var i = 0; i + kCyclingSeedMinutes <= spm.length; i++) {
      var evidence = 0, elevated = 0, stepsObserved = 0;
      for (var j = i; j < i + kCyclingSeedMinutes; j++) {
        if (cycling(j)) evidence++;
        if (highHr[j] == true) elevated++;
        if (spm[j] != null) stepsObserved++;
      }
      if (evidence >= kCyclingSeedEvidenceMinutes &&
          elevated >= kCyclingSeedHighHrMinutes &&
          stepsObserved >= kCyclingSeedStepObservedMinutes) {
        seedStart = i;
        break;
      }
    }
    if (seedStart != null) {
      var seedFirst = seedStart;
      var seedLast = seedStart + kCyclingSeedMinutes - 1;
      while (seedFirst <= seedLast && !cycling(seedFirst)) {
        seedFirst++;
      }
      while (seedLast >= seedFirst && !cycling(seedLast)) {
        seedLast--;
      }

      var first = seedFirst;
      var bad = 0;
      for (var i = seedFirst - 1; i >= 0; i--) {
        bad = cycling(i) ? 0 : bad + 1;
        if (bad >= kEdgeStopMinutes) {
          first = i + kEdgeStopMinutes;
          break;
        }
        first = i;
      }

      var end = seedLast + 1;
      var nonCycling = 0;
      var recovered = 0;
      for (var i = end; i < spm.length; i++) {
        nonCycling = cycling(i) ? 0 : nonCycling + 1;
        // Missing HR cannot establish that the rider recovered.
        recovered = highHr[i] == false ? recovered + 1 : 0;
        if (nonCycling >= kEdgeStopMinutes || recovered >= kEdgeStopMinutes) {
          final run = nonCycling >= kEdgeStopMinutes ? nonCycling : recovered;
          end = i - run + 1;
          break;
        }
        end = i + 1;
      }
      if (end - first >= kTrimMinMinutes && (first > 0 || end < spm.length)) {
        return (first: first, end: end);
      }
    }
  }

  if (cyclingOnly) return null;

  // The cadence-only fallback needs an observation for every minute. Missing
  // counter rows are absence, not zero steps, so do not infer a gait edge.
  if (spm.any((c) => c == null)) return null;

  var first = 0;
  while (first < spm.length && gait(first)) {
    first++;
  }
  var end = spm.length;
  for (var i = first; i + kGaitRunMin <= spm.length; i++) {
    if (List.generate(kGaitRunMin, (k) => gait(i + k)).every((g) => g)) {
      // Walking BETWEEN sets is an interior recovery, not the end. Retain
      // the bout if a sustained non-gait training block follows it. Use the
      // existing minimum core duration, rather than inventing another floor.
      var resumed = 0;
      var hasLaterCore = false;
      for (var j = i + kGaitRunMin; j < spm.length; j++) {
        // Cadence alone cannot distinguish a resumed ride/lifting block from
        // standing after arrival. Require continued elevated-HR evidence when
        // the caller has it; without such evidence, do not invent a resumed
        // training block merely because the step counter became quiet.
        final trainingMinute = hasTraining && training[j] == true;
        resumed = !gait(j) && trainingMinute ? resumed + 1 : 0;
        if (resumed >= kTrimMinMinutes) {
          hasLaterCore = true;
          break;
        }
      }
      if (hasLaterCore) continue;
      end = i;
      break;
    }
  }
  if (end - first < kTrimMinMinutes) return null;
  if (first == 0 && end == spm.length) return null;
  return (first: first, end: end);
}
