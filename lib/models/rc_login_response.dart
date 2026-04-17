class RcLoginResponse {
  final String? authenticationToken;
  final String? authenticationTokenExpiration;
  final String? distinctId;
  final String? email;

  const RcLoginResponse({
    this.authenticationToken,
    this.authenticationTokenExpiration,
    this.distinctId,
    this.email,
  });

  factory RcLoginResponse.fromJson(Map<String, dynamic> json) =>
      RcLoginResponse(
        authenticationToken: json['authentication_token'] as String?,
        authenticationTokenExpiration:
            json['authentication_token_expiration'] as String?,
        distinctId: json['distinct_id'] as String?,
        email: json['email'] as String?,
      );
}
