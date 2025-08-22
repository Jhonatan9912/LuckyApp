class User {
  final String name;
  final int identificationTypeId;
  final String identificationNumber;
  final String phone;             // solo dígitos
  final DateTime birthdate;
  final String password;
  final String email;

  // nuevos / existentes
  final bool? acceptTerms;
  final bool? acceptData;
  final String? referralCode;

  // 👇 NUEVO
  final String? countryCode;      // ej: +57

  User({
    required this.name,
    required this.identificationTypeId,
    required this.identificationNumber,
    required this.phone,
    required this.birthdate,
    required this.password,
    required this.email,
    this.acceptTerms,
    this.acceptData,
    this.referralCode,
    this.countryCode,             // 👈
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'identification_type_id': identificationTypeId,
    'identification_number': identificationNumber,
    'phone': phone, // solo dígitos
    'birthdate': birthdate.toIso8601String(),
    'password': password,
    'email': email,
    'accept_terms': acceptTerms,
    'accept_data': acceptData,
    'referral_code': referralCode,
    // 👇 IMPORTANTÍSIMO
    'country_code': countryCode,  // así lo espera el backend
  };
}
