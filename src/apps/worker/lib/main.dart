import 'package:flutter/material.dart';

void main() => runApp(const EdgeMintWorkerApp());

class EdgeMintWorkerApp extends StatelessWidget {
  const EdgeMintWorkerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'EdgeMint Worker',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF25C7A5),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      home: const WorkerHomePage(),
    );
  }
}

class WorkerHomePage extends StatefulWidget {
  const WorkerHomePage({super.key});

  @override
  State<WorkerHomePage> createState() => _WorkerHomePageState();
}

class _WorkerHomePageState extends State<WorkerHomePage> {
  bool available = true;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: const Text('EdgeMint'),
        actions: [
          IconButton(onPressed: () {}, icon: const Icon(Icons.notifications_none)),
          IconButton(onPressed: () {}, icon: const Icon(Icons.settings_outlined)),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: 0,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
          NavigationDestination(icon: Icon(Icons.assignment_outlined), label: 'Missions'),
          NavigationDestination(icon: Icon(Icons.view_in_ar_outlined), label: 'Models'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: 'Earnings'),
          NavigationDestination(icon: Icon(Icons.person_outline), label: 'Profile'),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Card(
              color: colorScheme.primaryContainer,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Ready for missions',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 6),
                    const Text('Your device is protected and ready for verified work.'),
                    const SizedBox(height: 16),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Worker availability'),
                      value: available,
                      onChanged: (value) => setState(() => available = value),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            _readinessCard(context),
            const SizedBox(height: 12),
            Card(
              child: ListTile(
                leading: const Icon(Icons.document_scanner_outlined),
                title: const Text('OCR Document'),
                subtitle: const Text('Estimated: 4 min • €0.018'),
                trailing: FilledButton(onPressed: () {}, child: const Text('View mission')),
              ),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Earnings summary', style: Theme.of(context).textTheme.titleMedium),
                    const SizedBox(height: 12),
                    const Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _Metric('Estimated', '€0.018'),
                        _Metric('Pending', '€2.40'),
                        _Metric('Verified', '€18.75'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),
            const ListTile(
              leading: Icon(Icons.rocket_launch_outlined),
              title: Text('2 new missions available'),
              trailing: Icon(Icons.chevron_right),
            ),
            const Center(child: Text('Last sync 1 min ago')),
          ],
        ),
      ),
    );
  }
}

Widget _readinessCard(BuildContext context) {
  return Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device readiness', style: Theme.of(context).textTheme.titleMedium),
          const _Status('Battery', '78%', Icons.battery_full),
          const _Status('Temperature', 'Normal', Icons.thermostat),
          const _Status('Network', 'Wi-Fi', Icons.wifi),
          const _Status('Storage', '12 GB free', Icons.storage),
          const _Status('Models', 'Ready', Icons.view_in_ar),
        ],
      ),
    ),
  );
}

class _Status extends StatelessWidget {
  const _Status(this.label, this.value, this.icon);

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value),
          const SizedBox(width: 8),
          const Icon(Icons.check_circle, color: Colors.green),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(label),
        Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      ],
    );
  }
}
