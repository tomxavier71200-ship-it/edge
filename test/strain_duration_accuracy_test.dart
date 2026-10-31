import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/manual_session.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/whoop_calibration.dart';
import 'package:openstrap_edge/state/app_state.dart';

const profile = Profile(ageYears: 30, weightKg: 75, heightCm: 180, sex: 'm');

void main() {
  test('a sparse minute earns only the seconds actually observed', () {
    final stats = computeManualSessionStats(
      hrTs: [0, 60, 120, 180],
      hrBpm: [150, 150, 150, 150],
      profile: profile,
      restingHr: 55,
      hrMax: 187,
    );
    // 150 bpm is reserve zone 3: four observed seconds, not four minutes.
    expect(stats.strain, closeTo(whoopWorkoutStrain(4 * 4 / 60), 1e-9));
  });

  test(
    'a partial minute does not get rounded up to a full minute of strain',
    () {
      final stats = computeManualSessionStats(
        hrTs: List.generate(10, (i) => i),
        hrBpm: List.filled(10, 150),
        profile: profile,
        restingHr: 55,
        hrMax: 187,
      );
      expect(stats.strain, closeTo(whoopWorkoutStrain(4 * 10 / 60), 1e-9));
    },
  );

  test('live and saved intervals score each zone before taking totals', () {
    final hr = List.generate(60, (i) => i < 30 ? 100 : 180);
    final saved = computeManualSessionStats(
      hrTs: List.generate(60, (i) => i),
      hrBpm: hr,
      profile: profile,
      restingHr: 55,
      hrMax: 187,
    );
    final live = LiveWorkoutState(
      startTime: DateTime(2026, 10, 31, 12),
      targetKcal: 300,
      type: 'cycling',
      age: 30,
      profile: profile,
      hrMax: 187,
      restingHr: 55,
    );
    for (var i = 0; i < hr.length; i++) {
      live.elapsed = Duration(seconds: i);
      live.accrueHr(hr[i]);
    }
    // Half below zone 1, half in zone 5: 0.5 * 16 = 8 minute-load units.
    expect(saved.strain, closeTo(whoopWorkoutStrain(8), 1e-9));
    expect(live.strain, closeTo(saved.strain!, 1e-9));
    expect(
      live.strain,
      greaterThan(
        strainFromPerMinuteHr(
          [140],
          profile: profile,
          restingHr: 55,
          hrMax: 187,
        )!,
      ),
    );
  });

  test('invalid sleep and reserve inputs cannot produce a confident score', () {
    expect(calibratedSleepPerformance(double.nan, 480, 80), isNull);
    expect(calibratedSleepPerformance(400, double.infinity, 80), isNull);
    expect(whoopSleepDebtMin(double.infinity, 400), isNull);
    expect(whoopStrainLoadPerMin(150, 55, double.infinity), isNull);
    expect(whoopStrainLoadPerMin(150, -1, 187), isNull);
  });
}
