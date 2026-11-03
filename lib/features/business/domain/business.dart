class Business {
  final String id;
  final String name;
  final String ownerId;
  final String city;
  final String phone;
  final String status;
  const Business({
    required this.id,
    required this.name,
    required this.ownerId,
    required this.city,
    required this.phone,
    required this.status,
  });
}

enum BusinessRole { owner, manager, sales, kitchenStaff, eventStaff }

extension BusinessRoleLabel on BusinessRole {
  String get displayName => switch (this) {
    BusinessRole.owner => 'Owner',
    BusinessRole.manager => 'Manager',
    BusinessRole.sales => 'Sales',
    BusinessRole.kitchenStaff => 'Kitchen staff',
    BusinessRole.eventStaff => 'Event staff',
  };
  String get wireValue => switch (this) {
    BusinessRole.owner => 'owner',
    BusinessRole.manager => 'manager',
    BusinessRole.sales => 'sales',
    BusinessRole.kitchenStaff => 'kitchen_staff',
    BusinessRole.eventStaff => 'event_staff',
  };
  static BusinessRole fromWire(String raw) => BusinessRole.values.firstWhere(
    (role) => role.wireValue == raw,
    orElse: () => BusinessRole.eventStaff,
  );
}

class BusinessMembership {
  final String uid;
  final String businessId;
  final BusinessRole role;
  final bool active;
  const BusinessMembership({
    required this.uid,
    required this.businessId,
    required this.role,
    required this.active,
  });
  bool get canViewFinance =>
      active && (role == BusinessRole.owner || role == BusinessRole.manager);
  bool get canManageTeam => active && role == BusinessRole.owner;
}
