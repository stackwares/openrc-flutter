import 'package:flutter_test/flutter_test.dart';
import 'package:openrc/services/agent/agent_display_money.dart';
import 'package:openrc/services/commission_settings_store.dart';

void main() {
  test('applies blended fees then FX', () {
    const money = AgentDisplayMoney(
      currency: 'EUR',
      feesApplied: true,
      usdToDisplay: 0.5,
      settings: CommissionSettings(
        adjustmentEnabled: true,
        appleCommissionPercent: 20,
        googleCommissionPercent: 20,
      ),
    );
    expect(money.toDisplay(100, blended: true), closeTo(40, 0.001));
    expect(money.meta()['currency'], 'EUR');
    expect(money.meta()['fees_applied'], isTrue);
  });

  test('leaves USD unchanged when fees are off', () {
    const money = AgentDisplayMoney(
      currency: 'USD',
      feesApplied: false,
      usdToDisplay: 1,
      settings: CommissionSettings(),
    );
    expect(money.toDisplay(12.5), 12.5);
  });
}
