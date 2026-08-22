import 'package:flutter/material.dart';

import 'worker_theme.dart';

typedef WorkerNavItem = ({IconData icon, IconData selectedIcon, String label});

const workerNavItems = <WorkerNavItem>[
  (icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'Home'),
  (icon: Icons.assignment_outlined, selectedIcon: Icons.assignment_rounded, label: 'Missions'),
  (icon: Icons.view_in_ar_outlined, selectedIcon: Icons.view_in_ar_rounded, label: 'Models'),
  (icon: Icons.account_balance_wallet_outlined, selectedIcon: Icons.account_balance_wallet_rounded, label: 'Earnings'),
  (icon: Icons.person_outline, selectedIcon: Icons.person_rounded, label: 'Profile'),
];

const _sidebarBreakpoint = 1024.0;

class WorkerShell extends StatelessWidget {
  const WorkerShell({
    super.key,
    required this.selectedIndex,
    required this.onNavChanged,
    required this.onRefresh,
    required this.body,
    this.available = true,
  });

  final int selectedIndex;
  final ValueChanged<int> onNavChanged;
  final VoidCallback onRefresh;
  final Widget body;
  final bool available;

  String get _title => switch (selectedIndex) {
        0 => 'EdgeMint AI | Worker Panel',
        1 => 'Missions',
        2 => 'Models',
        3 => 'Earnings',
        _ => 'Profile',
      };

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= _sidebarBreakpoint;

    if (wide) {
      return Scaffold(
        backgroundColor: WorkerColors.surface,
        body: Row(
          children: [
            _WorkerSidebar(
              selectedIndex: selectedIndex,
              onNavChanged: onNavChanged,
            ),
            Expanded(
              child: Column(
                children: [
                  _WorkerTopBar(
                    title: _title,
                    onRefresh: onRefresh,
                    available: available,
                  ),
                  Expanded(child: body),
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: WorkerColors.surface,
      appBar: _WorkerTopBar(
        title: _title,
        onRefresh: onRefresh,
        available: available,
        compact: true,
      ),
      body: body,
      bottomNavigationBar: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: onNavChanged,
        destinations: [
          for (final item in workerNavItems)
            NavigationDestination(
              icon: Icon(item.icon),
              selectedIcon: Icon(item.selectedIcon),
              label: item.label,
            ),
        ],
      ),
    );
  }
}

class _WorkerTopBar extends StatelessWidget implements PreferredSizeWidget {
  const _WorkerTopBar({
    required this.title,
    required this.onRefresh,
    required this.available,
    this.compact = false,
  });

  final String title;
  final VoidCallback onRefresh;
  final bool available;
  final bool compact;

  @override
  Size get preferredSize => Size.fromHeight(compact ? 56 : 64);

  @override
  Widget build(BuildContext context) {
    final bar = Container(
      height: preferredSize.height,
      padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 20),
      decoration: const BoxDecoration(
        color: WorkerColors.surfaceDim,
        border: Border(bottom: BorderSide(color: WorkerColors.outlineVariant)),
      ),
      child: Row(
        children: [
          if (!compact) ...[
            _BrandMark(compact: true),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: WorkerColors.onSurface,
                  ),
            ),
          ),
          IconButton(
            onPressed: onRefresh,
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Refresh',
            color: WorkerColors.onSurfaceVariant,
          ),
          Stack(
            clipBehavior: Clip.none,
            children: [
              IconButton(
                onPressed: () {},
                icon: const Icon(Icons.notifications_outlined),
                color: WorkerColors.onSurfaceVariant,
              ),
              if (available)
                Positioned(
                  right: 10,
                  top: 10,
                  child: Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: WorkerColors.primary,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 18,
            backgroundColor: WorkerColors.primaryContainer,
            child: const Text('EW', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (compact) {
      return AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: preferredSize.height,
        backgroundColor: WorkerColors.surfaceDim,
        title: Row(
          children: [
            const _BrandMark(compact: true),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(onPressed: onRefresh, icon: const Icon(Icons.sync_rounded)),
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: CircleAvatar(
              radius: 16,
              backgroundColor: WorkerColors.primaryContainer,
              child: Text('EW', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      );
    }
    return bar;
  }
}

class _WorkerSidebar extends StatelessWidget {
  const _WorkerSidebar({
    required this.selectedIndex,
    required this.onNavChanged,
  });

  final int selectedIndex;
  final ValueChanged<int> onNavChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 72,
      decoration: const BoxDecoration(
        color: WorkerColors.surfaceDim,
        border: Border(right: BorderSide(color: WorkerColors.outlineVariant)),
      ),
      child: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: _BrandMark(compact: false),
          ),
          Expanded(
            child: ListView.builder(
              itemCount: workerNavItems.length,
              itemBuilder: (context, index) {
                final item = workerNavItems[index];
                final selected = index == selectedIndex;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: Material(
                    color: selected
                        ? WorkerColors.primary.withValues(alpha: 0.18)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () => onNavChanged(index),
                      borderRadius: BorderRadius.circular(12),
                      child: SizedBox(
                        height: 48,
                        child: Icon(
                          selected ? item.selectedIcon : item.icon,
                          color: selected ? WorkerColors.primary : WorkerColors.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: IconButton(
              onPressed: () => onNavChanged(4),
              icon: Icon(
                selectedIndex == 4 ? Icons.settings : Icons.settings_outlined,
                color: selectedIndex == 4 ? WorkerColors.primary : WorkerColors.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.compact});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: compact ? 36 : 40,
      height: compact ? 36 : 40,
      decoration: BoxDecoration(
        color: WorkerColors.primary,
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: WorkerColors.primary.withValues(alpha: 0.35),
            blurRadius: 8,
          ),
        ],
      ),
      child: const Center(
        child: Text('E', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
    );
  }
}
