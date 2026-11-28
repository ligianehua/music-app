import 'package:flutter_test/flutter_test.dart';
import 'package:shuage/audio/audio_engine.dart';

void main() {
  test('first index is the initial load, not an advance', () {
    final d = AdvanceDetector();
    expect(d.onIndex(0), isNull);
  });

  test('native moving on by itself is reported', () {
    final d = AdvanceDetector()..onIndex(0);
    expect(d.onIndex(1), 1);
    expect(d.onIndex(1), isNull, reason: '重复报告同一序号不算换歌');
    expect(d.onIndex(2), 2);
  });

  test('the echo of our own jump is swallowed', () {
    final d = AdvanceDetector()..onIndex(0);
    d.expect(5);
    expect(d.onIndex(5), isNull);
    expect(d.onIndex(6), 6, reason: '回声之后的自然换歌照常上报');
  });

  test('stale indices during rapid swipes are swallowed until the target arrives', () {
    final d = AdvanceDetector()..onIndex(0);
    d.expect(1);
    d.expect(2);
    expect(d.onIndex(1), isNull, reason: '迟到的中间序号');
    expect(d.onIndex(2), isNull);
    expect(d.onIndex(3), 3);
  });

  test('jumping to the index we are already on does not wait for an echo', () {
    final d = AdvanceDetector()..onIndex(3);
    d.expect(3); // 原生层不会为同一序号再报一次
    expect(d.onIndex(4), 4);
  });

  test('a failed jump stops waiting for its echo', () {
    final d = AdvanceDetector()..onIndex(0);
    d.expect(7);
    d.cancel();
    expect(d.onIndex(1), 1);
  });
}
