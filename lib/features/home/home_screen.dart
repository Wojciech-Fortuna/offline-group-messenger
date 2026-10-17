import 'package:flutter/material.dart';
import 'package:offline_connectivity/offline_connectivity.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.connectivity});

  final OfflineConnectivity connectivity;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late Future<ConnectionCapabilities> _capabilities;

  @override
  void initState() {
    super.initState();
    _capabilities = widget.connectivity.getCapabilities();
  }

  void _refresh() {
    setState(() {
      _capabilities = widget.connectivity.getCapabilities();
    });
  }

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Offline Group Messenger')),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560),
            child: ListView(
              padding: const EdgeInsets.all(24),
              children: [
                Text(
                  'Stay close. Stay connected.',
                  style: textTheme.headlineLarge,
                ),
                const SizedBox(height: 12),
                Text(
                  'A space for your group, even without Internet.',
                  style: textTheme.bodyLarge,
                ),
                const SizedBox(height: 24),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Project preview', style: textTheme.titleMedium),
                        const SizedBox(height: 8),
                        const Text(
                          'The shared interface is ready to build on. '
                          'Creating groups and sending messages are not '
                          'implemented yet.',
                        ),
                        const SizedBox(height: 12),
                        FutureBuilder<ConnectionCapabilities>(
                          future: _capabilities,
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Could not check device support.'),
                                  TextButton(
                                    onPressed: _refresh,
                                    child: const Text('Try again'),
                                  ),
                                ],
                              );
                            }
                            if (!snapshot.hasData) {
                              return const Text('Checking device support...');
                            }
                            return Text(snapshot.requireData.description);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                const TextField(
                  maxLength: 40,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(labelText: 'Your name'),
                ),
                const SizedBox(height: 16),
                const FilledButton(
                  onPressed: null,
                  child: Text('Create a group'),
                ),
                const SizedBox(height: 8),
                const OutlinedButton(
                  onPressed: null,
                  child: Text('Join a group'),
                ),
                const SizedBox(height: 20),
                const Text(
                  'An Android phone will host the group. '
                  'Keep everyone within its Wi-Fi range.',
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
