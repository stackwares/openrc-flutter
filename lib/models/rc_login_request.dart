class RcLoginRequest {
  final String email;
  final String password;
  final String? otpCode;

  const RcLoginRequest({
    required this.email,
    required this.password,
    this.otpCode,
  });

  Map<String, dynamic> toJson() => {
    'email': email,
    'password': password,
    if (otpCode != null) 'otp_code': otpCode,
  };
}
