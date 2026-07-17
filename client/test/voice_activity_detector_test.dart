import 'package:flutter_test/flutter_test.dart';
import 'package:nexusroom/core/network/rtc_service.dart';

void main() {
  test('voice activity holds through short pauses without flickering', () {
    final detector = VoiceActivityDetector(silenceSamplesToStop: 5);

    expect(detector.update(0.020), isTrue);
    for (var sample = 0; sample < 4; sample++) {
      expect(detector.update(0.0), isTrue);
    }
    expect(detector.update(0.020), isTrue);
    expect(detector.speaking, isTrue);
  });

  test('voice activity stops after sustained silence', () {
    final detector = VoiceActivityDetector(silenceSamplesToStop: 5);
    detector.update(0.020);

    for (var sample = 0; sample < 4; sample++) {
      expect(detector.update(0.0), isTrue);
    }
    expect(detector.update(0.0), isFalse);
  });
}
