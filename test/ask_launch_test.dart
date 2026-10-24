import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/features/ask/ask_launch.dart';

void main() {
  test('a transaction query opens the sale, not Ask', () {
    final launch = AskLaunch.fromQuery({'transaction': '2000000123'});
    expect(launch.openAsk, isFalse);
    expect(launch.transactionId, '2000000123');
    expect(launch.prompt, isNull);
  });

  test('ask=1 with a transaction jumps to Ask about that sale', () {
    final launch = AskLaunch.fromQuery({
      'ask': '1',
      'transaction': '2000000123',
    });
    expect(launch.openAsk, isTrue);
    expect(launch.transactionId, '2000000123');
    expect(launch.prompt, isNull);
  });

  test('ask=true is the same flag as ask=1', () {
    expect(AskLaunch.fromQuery({'ask': 'true'}).openAsk, isTrue);
    expect(AskLaunch.fromQuery({'ask': 'TRUE'}).openAsk, isTrue);
  });

  test('a written ask query prefills the composer', () {
    final launch = AskLaunch.fromQuery({
      'ask': '  How was today vs yesterday?  ',
    });
    expect(launch.openAsk, isTrue);
    expect(launch.prompt, 'How was today vs yesterday?');
    expect(launch.transactionId, isNull);
  });

  test('a long ask query is capped', () {
    final launch = AskLaunch.fromQuery({
      'ask': 'x' * (AskLaunch.maxPromptChars + 40),
    });
    expect(launch.prompt, hasLength(AskLaunch.maxPromptChars));
  });

  test('newlines in an ask query collapse to spaces', () {
    final launch = AskLaunch.fromQuery({'ask': 'Why is\nMRR\tdown?'});
    expect(launch.prompt, 'Why is MRR down?');
  });

  test('a transaction id longer than the notifier cap is trimmed', () {
    final launch = AskLaunch.fromQuery({
      'transaction': 't' * 250,
    });
    expect(launch.transactionId, hasLength(AskLaunch.maxTransactionIdChars));
  });

  test('empty query is empty', () {
    expect(AskLaunch.fromQuery({}).isEmpty, isTrue);
    expect(AskLaunch.fromQuery({'ask': '  '}).isEmpty, isTrue);
  });
}
