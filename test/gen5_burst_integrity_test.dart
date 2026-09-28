// Gen5 history-burst integrity: the ways a record could be trimmed off the
// band without ever having been stored, and the per-burst accounting that
// keeps "received", "decoded", "committed" and "acknowledged" apart.
//
// Each group pins one gap that the existing count gate did not close:
//   - a byte-identical repeat of a frame was tallied twice, and the gate has
//     no upper bound, so one duplicate could stand in for one LOST frame — the
//     burst passed, the ACK went out and the band trimmed the lost record;
//   - a type-47 record reassembled off a non-data characteristic was ingested
//     inline, ahead of the markers still in the serialized queue, and counted
//     into whichever burst the queue had open — the same masking, one burst
//     early;
//   - a record whose header carries unix 0 decoded, passed RecordGate (which
//     admits untimed records by design), counted as durable progress and was
//     ACKed — but no durable table can hold a record without a time, so its
//     bytes existed nowhere once the band trimmed them.
// The rest pin behaviour the fixes must NOT disturb: counter gaps, wraps and
// out-of-order frames are recorded, never rejected on their own and never
// filled; gen4 stays advisory.

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ble/ble_engine.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_protocol/openstrap_protocol.dart';

int _wallNow() => DateTime.now().millisecondsSinceEpoch ~/ 1000;

/// A gen5 v18 inner `Gen5V18Decoder` accepts (same shape gen5_wiring_test
/// uses): HR 64, dynamic accel 0.5 g, gravity z 1 g.
Uint8List _v18({required int ts, required int counter, int hr = 64}) {
  final inner = Uint8List(kGen5V18InnerLen);
  final v = ByteData.sublistView(inner);
  inner[0] = PacketType.historicalData;
  inner[1] = 18;
  inner[2] = 0x80;
  v.setUint32(3, counter, Endian.little);
  v.setUint32(7, ts, Endian.little);
  inner[14] = hr;
  v.setFloat32(33, 0.5, Endian.little);
  v.setFloat32(45, 1.0, Endian.little);
  return inner;
}

/// A gen4 v24 inner (the trusted path — no plausibility gate on fields).
Uint8List _gen4V24({required int ts, required int counter}) {
  final inner = Uint8List(89);
  inner[0] = PacketType.historicalData;
  inner[1] = 24;
  final v = ByteData.sublistView(inner);
  v.setUint32(3, counter, Endian.little);
  v.setUint32(7, ts, Endian.little);
  return inner;
}

Uint8List _start() =>
    Uint8List.fromList(<int>[PacketType.metadata, 0x01, SyncMeta.historyStart]);

/// HISTORY_END: expected count u32 @9, trim token @13:21 (marker A + B).
Uint8List _end({required int expected, required int token}) {
  final inner = Uint8List(24);
  inner[0] = PacketType.metadata;
  inner[1] = 0x02;
  inner[2] = SyncMeta.historyEnd;
  final v = ByteData.sublistView(inner);
  v.setUint32(3, 1786000000, Endian.little);
  v.setUint32(9, expected, Endian.little);
  v.setUint32(13, token, Endian.little);
  v.setUint32(17, 0x18, Endian.little);
  return inner;
}

List<int> _tokenBytes(int token) {
  final b = ByteData(8)
    ..setUint32(0, token, Endian.little)
    ..setUint32(4, 0x18, Endian.little);
  return b.buffer.asUint8List();
}

class _Commit {
  final List<RawRecord> raws;
  final List<Sample?> samples;
  final String? token;
  final List<ArchiveRecord> archives;
  _Commit(this.raws, this.samples, this.token, this.archives);
}

/// A band link driven through the REAL receive path (FrameRoutePolicy, the
/// serialized offload queue, the HISTORY_END handler) with the atomic commit
/// sink wired, as production always has it.
class _Link {
  final logs = <String>[];
  final frames = <Uint8List>[];
  final commits = <_Commit>[];

  /// Ordered `commit:<token|null>` / `ack:<token>` / `fail` events.
  final timeline = <String>[];
  final BandProfile band;
  late final BleEngine engine;

  _Link({this.band = BandProfile.gen5}) {
    engine = BleEngine(
      onRecord: (_, _) async {},
      onState: (_) {},
      log: logs.add,
    );
    engine.debugInstallFakeLink(
      band: band,
      onWrite: (f) async {
        frames.add(f);
        final p = parseFrame(f, profile: band);
        if (p != null && p.valid && p.inner[2] == Cmd.historicalDataResult) {
          if (p.inner.length >= 12 && p.inner[3] == 1) {
            final tok = p.inner.sublist(4, 12);
            timeline.add('ack:${_hex(tok)}');
          } else {
            timeline.add('fail');
          }
        }
        return true;
      },
      onCommit: (raws, samples, token,
          {archives, ecgRawPackets, deviceFamily}) async {
        commits.add(_Commit(List.of(raws), List.of(samples), token,
            List.of(archives ?? const <ArchiveRecord>[])));
        timeline.add('commit:$token');
      },
    );
  }

  static String _hex(List<int> b) =>
      b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

  String tokenHex(int token) => _hex(_tokenBytes(token));

  void rx(Uint8List inner, {String role = 'data'}) =>
      engine.debugReceiveFrame(Frame(inner, true, true), role: role);

  List<String> get acks =>
      timeline.where((e) => e.startsWith('ack:')).toList();
  int get fails => timeline.where((e) => e == 'fail').length;

  /// The accounting map of every HISTORY_END that got past the count gate
  /// (the `[SYNC] HistoryEnd` line).
  List<Map<String, dynamic>> get accounting => logs
      .where((l) => l.contains('[SYNC] HistoryEnd batch='))
      .map((l) => jsonDecode(RegExp(r'accounting=(\{.*\})$')
          .firstMatch(l)!
          .group(1)!) as Map<String, dynamic>)
      .toList();

  List<String> get shortLines =>
      logs.where((l) => l.contains('Burst packet-count SHORT')).toList();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(BleEngine.resetBandClaimForTest);
  tearDown(BleEngine.resetBandClaimForTest);

  final ts = _wallNow() - 3600;

  group('baseline — a complete gen5 burst', () {
    test('is committed with its token BEFORE the verbatim ACK, and its '
        'accounting separates received / decoded', () async {
      final l = _Link();
      l.rx(_start());
      for (var i = 0; i < 5; i++) {
        l.rx(_v18(ts: ts + i, counter: 10000 + i));
      }
      l.rx(_end(expected: 5, token: 0x5001));
      await pumpEventQueue();

      final tok = l.tokenHex(0x5001);
      expect(l.timeline, ['commit:$tok', 'ack:$tok']);
      expect(l.commits.single.raws, hasLength(5));
      final a = l.accounting.single;
      expect(a['expected'], 5);
      expect(a['received'], 5);
      expect(a['decoded'], 5);
      expect(a['duplicates'], 0);
      expect(a['shortfall'], 0);
      expect(a['counter_missing'], 0);
    });
  });

  group('P0 — a duplicate frame cannot stand in for a lost one', () {
    test('lost #3 + duplicated #2 is 5 frames by the old tally — it must be '
        'REFUSED, not ACKed', () async {
      final l = _Link();
      l.rx(_start());
      l.rx(_v18(ts: ts, counter: 20000));
      l.rx(_v18(ts: ts + 1, counter: 20001));
      l.rx(_v18(ts: ts + 1, counter: 20001)); // byte-identical repeat
      // counter 20002 never arrives
      l.rx(_v18(ts: ts + 3, counter: 20003));
      l.rx(_v18(ts: ts + 4, counter: 20004));
      l.rx(_end(expected: 5, token: 0x5002));
      await pumpEventQueue();

      expect(l.acks, isEmpty,
          reason: 'OLD BEHAVIOUR: 5 tallied >= 5 expected, ACK sent, and the '
              'band trimmed record 20002, which exists nowhere');
      expect(l.fails, 1, reason: 'the failure result makes the band re-offer');
      expect(l.shortLines, hasLength(1));
      // What did arrive is still stored — without the token.
      expect(l.commits.single.token, isNull);
      expect(l.commits.single.raws.map((r) => r.counter),
          [20000, 20001, 20003, 20004],
          reason: 'the repeat is not buffered twice, and nothing is invented '
              'for the missing counter');
    });

    test('a duplicate with NO loss still passes, once', () async {
      final l = _Link();
      l.rx(_start());
      for (var i = 0; i < 4; i++) {
        l.rx(_v18(ts: ts + i, counter: 21000 + i));
      }
      l.rx(_v18(ts: ts + 2, counter: 21002)); // repeat
      l.rx(_end(expected: 4, token: 0x5003));
      await pumpEventQueue();

      expect(l.acks, [('ack:${l.tokenHex(0x5003)}')]);
      final a = l.accounting.single;
      expect(a['received'], 4);
      expect(a['duplicates'], 1);
      expect(a['decoded'], 4);
      expect(l.commits.single.raws, hasLength(4));
    });

    test('the seen-set is per burst: the same frame re-delivered under a '
        'replacement HISTORY_START is counted again', () async {
      final l = _Link();
      l.rx(_start());
      l.rx(_v18(ts: ts, counter: 22000));
      l.rx(_end(expected: 2, token: 0x5004)); // #22001 lost → refused
      await pumpEventQueue();
      expect(l.fails, 1);

      // The band re-offers the checkpoint: same frames, new window.
      l.rx(_start());
      l.rx(_v18(ts: ts, counter: 22000));
      l.rx(_v18(ts: ts + 1, counter: 22001));
      l.rx(_end(expected: 2, token: 0x5004));
      await pumpEventQueue();

      expect(l.acks, ['ack:${l.tokenHex(0x5004)}'],
          reason: 'recovery after failure: the complete re-delivery is ACKed');
      expect(l.accounting.last['duplicates'], 0);
    });

    test('DrainController: a discarded chunk forgets what it saw', () {
      final d = DrainController(
        onRecord: (_, _) async {},
        onRecordsBatch: null,
        onCommit: (_, _, _, {archives, ecgRawPackets, deviceFamily}) async {},
        onArchive: null,
        log: (_) {},
      );
      expect(d.admitBurstFrame('aa'), isTrue);
      expect(d.admitBurstFrame('aa'), isFalse);
      expect(d.duplicateFramesThisBurst, 1);
      d.discardOpenChunk();
      expect(d.admitBurstFrame('aa'), isTrue,
          reason: 'its buffered copy was thrown away — a re-send must be '
              'buffered again, not dropped as a repeat');
      d.rearm();
      expect(d.duplicateFramesThisBurst, 0);
    });

    test('gen4 is untouched: identical frames still tally twice (advisory '
        'count, no dedup)', () async {
      final l = _Link(band: BandProfile.gen4);
      final f = _gen4V24(ts: ts, counter: 9100);
      l.rx(_start());
      l.rx(f);
      l.rx(f);
      l.rx(_end(expected: 2, token: 0x5005));
      await pumpEventQueue();

      expect(l.accounting.single['received'], 2);
      expect(l.accounting.single['duplicates'], 0);
      expect(l.shortLines, isEmpty);
    });
  });

  group('P0 — a historical frame off a non-data role keeps its burst', () {
    test('it is not credited to the burst the queue still has open', () async {
      final l = _Link();
      // One GATT flurry: the queue has processed nothing past START_A when
      // burst B's first record lands on another characteristic.
      l.rx(_start());
      l.rx(_v18(ts: ts, counter: 23000));
      // 23001 is lost on air
      l.rx(_end(expected: 2, token: 0x5006));
      l.rx(_start());
      l.rx(_v18(ts: ts + 10, counter: 23010), role: 'events');
      l.rx(_v18(ts: ts + 11, counter: 23011));
      l.rx(_end(expected: 2, token: 0x5007));
      await pumpEventQueue();

      expect(l.acks, ['ack:${l.tokenHex(0x5007)}'],
          reason: 'OLD BEHAVIOUR: B\'s record was ingested inline into A, '
              'A tallied 2/2 and was ACKed (trimming the lost 23001), and B '
              'came up 1/2 short');
      expect(l.fails, 1, reason: 'A is refused: it really is one short');
    });
  });

  group('P0 — an untimed record is archived, never ACKed away', () {
    test('unix 0 lands in raw_archive whole; nothing is banked at epoch 0',
        () async {
      final l = _Link();
      l.rx(_start());
      l.rx(_v18(ts: ts, counter: 24000));
      l.rx(_v18(ts: 0, counter: 24001, hr: 70));
      l.rx(_v18(ts: ts + 2, counter: 24002));
      l.rx(_end(expected: 3, token: 0x5008));
      await pumpEventQueue();

      final c = l.commits.single;
      expect(c.token, l.tokenHex(0x5008));
      expect(c.raws.map((r) => r.counter), [24000, 24002],
          reason: 'OLD BEHAVIOUR: banked as a decoded record with no rec_ts — '
              'no durable 1 Hz row, only a samples stub at epoch 0');
      expect(c.samples.every((s) => s!.tsEpoch > 0), isTrue);
      final archived = c.archives.single;
      expect(archived.reason, 'untimed_rec_v18');
      expect(archived.counter, 24001);
      expect(archived.recTs, isNull, reason: 'never re-timed');
      expect(l.acks, ['ack:${l.tokenHex(0x5008)}'],
          reason: 'the bytes are durable, so it is real progress and still a '
              'count member — the burst is complete');
      expect(l.accounting.single['archived'], 1);
      expect(l.accounting.single['decoded'], 2);
    });
  });

  group('counter continuity is recorded, never filled, never over-rejected', () {
    test('a band-side counter gap with a COMPLETE count is ACKed; the gap is '
        'on record and no sample is invented', () async {
      final l = _Link();
      l.rx(_start());
      for (final c in [10421, 10422, 10423, 10425]) {
        l.rx(_v18(ts: ts + c - 10421, counter: c));
      }
      l.rx(_end(expected: 4, token: 0x5009));
      await pumpEventQueue();

      expect(l.acks, hasLength(1));
      final a = l.accounting.single;
      expect(a['counter_gaps'], 1);
      expect(a['counter_missing'], 1);
      expect(l.commits.single.raws.map((r) => r.counter),
          [10421, 10422, 10423, 10425]);
    });

    test('a missing MIDDLE frame is refused and shows as a counter gap',
        () async {
      final l = _Link();
      l.rx(_start());
      for (final c in [30000, 30001, 30003]) {
        l.rx(_v18(ts: ts + c - 30000, counter: c));
      }
      l.rx(_end(expected: 4, token: 0x500a));
      await pumpEventQueue();
      expect(l.acks, isEmpty);
      expect(l.fails, 1);
      expect(l.shortLines.single, contains('seqV18(gaps=1, missing=1'));
    });

    test('a missing FINAL frame leaves no counter gap — the count gate alone '
        'refuses it', () async {
      final l = _Link();
      l.rx(_start());
      for (final c in [31000, 31001, 31002]) {
        l.rx(_v18(ts: ts + c - 31000, counter: c));
      }
      l.rx(_end(expected: 4, token: 0x500b));
      await pumpEventQueue();
      expect(l.acks, isEmpty);
      expect(l.fails, 1);
      expect(l.shortLines.single, isNot(contains('seqV18')));
    });

    test('out-of-order frames are all kept and the burst passes', () async {
      final l = _Link();
      l.rx(_start());
      for (final c in [32000, 32002, 32001, 32003]) {
        l.rx(_v18(ts: ts + c - 32000, counter: c));
      }
      l.rx(_end(expected: 4, token: 0x500c));
      await pumpEventQueue();
      expect(l.acks, hasLength(1));
      expect(l.commits.single.raws, hasLength(4));
      expect(l.accounting.single['counter_backward'], 1,
          reason: 'recorded for diagnosis, not treated as loss');
    });

    test('a u32 wrap inside a burst is not corruption', () async {
      final l = _Link();
      l.rx(_start());
      final counters = [0xFFFFFFFE, 0xFFFFFFFF, 0, 1];
      for (var i = 0; i < counters.length; i++) {
        l.rx(_v18(ts: ts + i, counter: counters[i]));
      }
      l.rx(_end(expected: 4, token: 0x500d));
      await pumpEventQueue();
      expect(l.acks, hasLength(1));
      expect(l.commits.single.raws.map((r) => r.counter), counters);
      expect(
          l.logs.any((s) => s.contains('Record counter regressed')), isFalse,
          reason: 'CounterRegressionDetector treats the top-of-range roll-over '
              'as benign');
    });
  });

  group('empty and all-dropped bursts', () {
    test('an all-lost burst (expected 3, nothing arrived) is refused', () async {
      final l = _Link();
      l.rx(_start());
      l.rx(_end(expected: 3, token: 0x500e));
      await pumpEventQueue();
      expect(l.acks, isEmpty);
      expect(l.fails, 1);
    });
  });
}
