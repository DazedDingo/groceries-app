/// Short, idiomatic "time ago" string. Hand-rolled (instead of a package)
/// so the output is predictable in tests and free of locale surprises for
/// our simple settings/trip-sheet uses.
String timeAgo(DateTime when, {DateTime? now}) {
  final reference = now ?? DateTime.now();
  final diff = reference.difference(when);

  if (diff.isNegative) return 'just now';

  final seconds = diff.inSeconds;
  if (seconds < 45) return 'just now';

  final minutes = diff.inMinutes;
  if (minutes < 60) {
    return minutes == 1 ? '1 min ago' : '$minutes min ago';
  }

  final hours = diff.inHours;
  if (hours < 24) {
    return hours == 1 ? '1 hour ago' : '$hours hours ago';
  }

  final days = diff.inDays;
  if (days < 30) {
    return days == 1 ? 'yesterday' : '$days days ago';
  }

  final months = (days / 30).floor();
  if (months < 12) {
    return months == 1 ? '1 month ago' : '$months months ago';
  }

  final years = (days / 365).floor();
  return years == 1 ? '1 year ago' : '$years years ago';
}
