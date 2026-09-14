// Copyright (C) 2026 @nightcodex7
// Copyright (C) 2025-2026 cogwheel0
// SPDX-License-Identifier: GPL-3.0-or-later

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:yet_another_luci_app/modules/dhcp_dns/models/dhcp_dns_info.dart';
import 'package:yet_another_luci_app/widgets/add_static_lease_dialog.dart';

void main() {
  testWidgets(
    'AddStaticLeaseDialog initializes without error when parameters are null',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => const AddStaticLeaseDialog(),
                  );
                },
                child: const Text('Open Dialog'),
              ),
            ),
          ),
        ),
      );

      // Open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      // Verify dialog title is rendered and no LateInitializationError occurred
      expect(find.text('Add Static Lease'), findsOneWidget);
      expect(find.text('MAC Address'), findsOneWidget);
      expect(find.text('Hostname / Client Name'), findsOneWidget);
      expect(find.text('Save Reservation'), findsOneWidget);

      // Verify initial clean state without premature error messages
      expect(find.text('MAC address cannot be empty'), findsNothing);
      expect(find.text('Hostname cannot be empty'), findsNothing);
      expect(find.text('IPv4 address cannot be empty'), findsNothing);
      expect(find.textContaining('Paste MAC'), findsNothing);
    },
  );

  testWidgets(
    'AddStaticLeaseDialog renders Remove Lease button and confirmation dialog in edit mode',
    (WidgetTester tester) async {
      final mapping = DhcpStaticMapping(
        macAddress: '11:22:33:44:55:66',
        ipAddress: '192.168.1.150',
        hostname: 'Printer-Device',
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () {
                  showDialog(
                    context: context,
                    builder: (ctx) => AddStaticLeaseDialog(
                      existingMapping: mapping,
                    ),
                  );
                },
                child: const Text('Open Edit Dialog'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('Open Edit Dialog'));
      await tester.pumpAndSettle();

      // Verify edit title and buttons
      expect(find.text('Edit Static Lease'), findsOneWidget);
      expect(find.text('Update Reservation'), findsOneWidget);
      expect(find.text('Remove Lease'), findsOneWidget);

      // Tap Remove Lease button
      await tester.tap(find.text('Remove Lease'));
      await tester.pumpAndSettle();

      // Verify confirmation dialog appears
      expect(find.text('Remove Static Lease'), findsOneWidget);
      expect(find.text('Remove Reservation'), findsOneWidget);
      expect(find.textContaining('Printer-Device'), findsWidgets);
    },
  );
}
