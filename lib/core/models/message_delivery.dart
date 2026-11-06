import 'participant.dart';

/// Immutable application receipt snapshot. The host is covered by acceptance.
class MessageDelivery {
  MessageDelivery({
    required this.sequence,
    required List<Participant> recipients,
    Set<String> received = const {},
  }) : recipients = List.unmodifiable(recipients),
       received = Set.unmodifiable(received);

  final int sequence;
  final List<Participant> recipients;
  final Set<String> received;

  int get checks =>
      recipients.isNotEmpty && received.length == recipients.length
      ? 3
      : received.isNotEmpty
      ? 2
      : 1;

  MessageDelivery acknowledge(String participantId) => MessageDelivery(
    sequence: sequence,
    recipients: recipients,
    received: {...received, participantId},
  );
}
