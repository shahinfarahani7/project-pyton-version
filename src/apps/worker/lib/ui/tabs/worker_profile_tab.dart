import 'package:flutter/material.dart';

import '../../worker_app_controller.dart';
import 'worker_profile_credentials_section.dart';

class WorkerProfileTab extends StatelessWidget {
  const WorkerProfileTab({super.key, required this.controller});

  final WorkerAppController controller;

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListView(
      padding: EdgeInsets.fromLTRB(wide ? 24 : 16, 16, wide ? 24 : 16, 24),
      children: [
        WorkerProfileCredentialsSection(controller: controller),
      ],
    );
  }
}
