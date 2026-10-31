// Synthetic desktop benchmark; not a device frame/battery measurement.
// The old implementation is retained only as the comparison reference.
// Run: dart run tool/hrv_timeline_benchmark.dart
import 'dart:math' as math;
import 'dart:io' show stdout;
import 'package:openstrap_edge/compute/onehz_pipeline.dart' show buildHrvTimeline;
List<Map<String, num>> oldTimeline(
  List<double> nn,
  List<double> nnTimes,
  double? originMs,
) {
  if (nn.length < 10 || nnTimes.length != nn.length || originMs == null) {
    return const [];
  }
  const winMs = 300000.0; // 5 min
  final out = <Map<String, num>>[];
  var lo = 0;
  for (var i = 0; i < nn.length; i++) {
    while (nnTimes[i] - nnTimes[lo] > winMs) {
      lo++;
    }
    // A FULL window, or nothing. `lo` cannot move until 5 min have elapsed, so
    // before that `[lo..i]` is a partial window — the first point used to be an
    // RMSSD over 10 beats (~8 s) drawn on a line documented as rolling 5-min
    // windows, with nothing marking it as the outlier-prone sample it is.
    if (nnTimes[i] - nnTimes[0] < winMs) continue;
    if (i - lo >= 10) {
      var ssd = 0.0;
      for (var k = lo + 1; k <= i; k++) {
        final diff = nn[k] - nn[k - 1];
        ssd += diff * diff;
      }
      final rmssd = math.sqrt(ssd / (i - lo));
      final tSec = ((originMs + nnTimes[i]) / 1000).round();
      if (out.isEmpty || tSec - out.last['t']! > 60) {
        out.add({'t': tSec, 'v': _round(rmssd, 1)});
      }
    }
  }
  return out;
}
double _round(double v, int dp) { final p = math.pow(10, dp); return (v * p).round() / p; }
void main() {
 final nn = List.generate(8 * 3600, (i) => 1000.0 + 20 * math.sin(i / 5));
 var t = 0.0;
 final times = [for (final rr in nn) t += rr];
 for (var warm = 0; warm < 3; warm++) { oldTimeline(nn, times, 1790000000000); buildHrvTimeline(nn, times, 1790000000000); }
 for (var run = 0; run < 5; run++) {
  final sw = Stopwatch()..start();
  final old = oldTimeline(nn, times, 1790000000000);
  sw.stop(); final before = sw.elapsedMicroseconds;
  sw.reset(); sw.start();
  final updated = buildHrvTimeline(nn, times, 1790000000000);
  sw.stop();
  if (old.toString() != updated.toString()) throw StateError('Continuous output changed');
  stdout.writeln('run=${run+1} old_us=$before new_us=${sw.elapsedMicroseconds} points=${updated.length}');
 }
}
