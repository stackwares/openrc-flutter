/// `$RCAnonymousID:a1b2…` → `a1b2••••9f0e`: enough to tell rows apart.
String maskSubscriberId(String id) {
  final bare = id.startsWith(r'$RCAnonymousID:')
      ? id.substring(r'$RCAnonymousID:'.length)
      : id;
  if (bare.length <= 10) return bare;
  return '${bare.substring(0, 4)}••••${bare.substring(bare.length - 4)}';
}
