import 'participant.dart';

/// Immutable receipt snapshot, including the host when it is a recipient.
class MessageDelivery {
  MessageDelivery({
    required this.sequence,
    this.hostId,
    required List<Participant> recipients,
    Set<String> received = const {},
  }) : recipients = List.unmodifiable(recipients),
       received = Set.unmodifiable(received);

  final int sequence;
  final String? hostId;
  final List<Participant> recipients;
  final Set<String> received;

  int get checks =>
      recipients.isNotEmpty && received.length == recipients.length
      ? 3
      : received.any((id) => id != hostId)
      ? 2
      : 1;

  MessageDelivery acknowledge(String participantId) => MessageDelivery(
    sequence: sequence,
    hostId: hostId,
    recipients: recipients,
    received: {...received, participantId},
  );
}
