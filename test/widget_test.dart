import 'package:flutter_test/flutter_test.dart';
import 'package:catering_pro/features/business/domain/business.dart';

void main() {
  test('business role wire values round trip', () {
    for (final role in BusinessRole.values) {
      expect(BusinessRoleLabel.fromWire(role.wireValue), role);
      expect(role.displayName, isNotEmpty);
    }
  });

  test('owner and manager have different staff permissions', () {
    BusinessMembership member(BusinessRole role, {bool active = true}) =>
        BusinessMembership(
          uid: 'test-user',
          businessId: 'test-business',
          role: role,
          active: active,
        );

    expect(member(BusinessRole.owner).canViewFinance, isTrue);
    expect(member(BusinessRole.owner).canManageTeam, isTrue);
    expect(member(BusinessRole.manager).canViewFinance, isTrue);
    expect(member(BusinessRole.manager).canManageTeam, isFalse);
    expect(member(BusinessRole.sales).canViewFinance, isFalse);
    expect(member(BusinessRole.owner, active: false).canViewFinance, isFalse);
  });
}
