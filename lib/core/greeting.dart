/// The English time-of-day greeting shared by the home hero and the profile
/// header, so both always say the same thing at the same hour.
String greetingForNow([DateTime? at]) {
  final hour = (at ?? DateTime.now()).hour;
  if (hour >= 5 && hour < 12) return 'Good morning';
  if (hour >= 12 && hour < 18) return 'Good afternoon';
  return 'Good evening';
}
