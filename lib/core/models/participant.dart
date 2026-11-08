class Participant {
  const Participant({
    required this.id,
    required this.displayName,
    this.canCall = false,
  });

  final String id;
  final String displayName;
  final bool canCall;
}
