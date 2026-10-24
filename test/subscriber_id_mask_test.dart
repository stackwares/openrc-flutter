import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/core/utils/subscriber_id_mask.dart';

void main() {
  test('masks anonymous ids the way the table does', () {
    expect(
      maskSubscriberId(r'$RCAnonymousID:abcdefghijklmnop'),
      'abcd••••mnop',
    );
  });

  test('leaves short ids intact', () {
    expect(maskSubscriberId('short'), 'short');
  });
}
