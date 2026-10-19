import 'package:flutter/material.dart';

import '../../widgets/common.dart';

/// Honest stand-in for screens that are routed but not built yet.
class ComingSoonPage extends StatelessWidget {
  const ComingSoonPage({super.key, required this.title});
  final String title;

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          PageTitle(title: title),
          EmptyState(
            icon: Icons.construction_rounded,
            title: 'Not built yet',
            message: '$title is part of the rebuild and has not been implemented in this version of the app.',
          ),
        ],
      );
}
