class Client {
  const Client({
    required this.id,
    required this.businessName,
    required this.email,
    required this.phone,
    required this.address,
    required this.country,
    required this.countryName,
    required this.isActive,
  });

  final int id;
  final String businessName;
  final String email;
  final String phone;
  final String address;
  final int country;
  final String countryName;
  final bool isActive;

  factory Client.fromJson(Map<String, dynamic> json) {
    return Client(
      id: json['id'] as int,
      businessName: json['business_name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      phone: json['phone'] as String? ?? '',
      address: json['address'] as String? ?? '',
      country: json['country'] as int? ?? 0,
      countryName: json['country_name'] as String? ?? '',
      isActive: json['is_active'] as bool? ?? true,
    );
  }
}
