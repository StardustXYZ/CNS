// Which addresses the app opens: only web addresses (https and http). A bad value saved in
// Firestore or in a backup file ("intent:", "javascript:", "tel:", …) is never launched.
import 'package:cns/pages/widgets.dart' show isWebLink;
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('si aprono solo gli indirizzi web', () {
    expect(isWebLink('https://www.deezer.com/artist/15741'), isTrue);
    expect(isWebLink('http://cdn.example/a.jpg'), isTrue);
    expect(isWebLink('https://open.spotify.com/search/Ava%20Max%20Heaven'), isTrue);
  });

  test('tutto il resto no', () {
    for (final bad in [
      'javascript:alert(1)',
      'JaVaScRiPt:alert(1)',
      'intent://x#Intent;scheme=http;end',
      'tel:+390000000',
      'sms:+390000000',
      'file:///sdcard/x',
      'content://x/y',
      '//evil.example/x',
      '/relativo',
      'Ava Max',
      '',
      '   ',
    ]) {
      expect(isWebLink(bad), isFalse, reason: bad);
    }
  });
}
