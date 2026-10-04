import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:terminal_agent/l10n/l10n.dart';
import 'package:terminal_agent/models/connection_profile.dart';
import 'package:terminal_agent/models/terminal_shortcut.dart';
import 'package:terminal_agent/providers/app_state.dart';
import 'package:terminal_agent/services/tunnel_manager.dart';
import 'package:terminal_agent/theme/app_theme.dart';
import 'package:terminal_agent/views/terminal_quick_keys.dart';
import 'package:terminal_agent/views/terminal_tab.dart';

Future<AppState> _state(WidgetTester tester) async {
  SharedPreferences.setMockInitialValues({'app_language': 'en'});
  await L10n.load();
  final state = AppState();
  // Let the constructor's preferences load finish before editing the list.
  await tester.pumpAndSettle();
  return state;
}

Future<List<String>> _pump(
  WidgetTester tester,
  AppState state, {
  double width = 360,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 720);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final output = <String>[];
  await tester.pumpWidget(
    ChangeNotifierProvider<AppState>.value(
      value: state,
      child: MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (_, __) => Column(
              children: [
                const Spacer(),
                TerminalQuickKeys(
                  state: state,
                  onSend: output.add,
                  onAction: (action) => output.add('action:$action'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return output;
}

Future<void> _open(WidgetTester tester) async {
  await tester.drag(
    find.byKey(const ValueKey('top-key-row')),
    const Offset(-120, 0),
  );
  await tester.pumpAndSettle();
}

Future<List<String>> _pumpTerminal(WidgetTester tester, AppState state) async {
  state.createNewSession(
    profile: ConnectionProfile(
      id: 'test-host',
      name: 'Test',
      host: 'localhost',
      port: 22,
      username: 'user',
    ),
    connect: false,
  );
  final sent = <String>[];
  state.terminal.onOutput = sent.add;
  state.terminal.write('\x1b[?2004h');
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<AppState>.value(value: state),
        ChangeNotifierProvider<TunnelManager>.value(value: state.tunnels),
      ],
      child: const MaterialApp(home: Scaffold(body: TerminalTab())),
    ),
  );
  await tester.pumpAndSettle();
  await _open(tester);
  return sent;
}

void main() {
  testWidgets('multiline prompt buttons insert one paste without submitting',
      (tester) async {
    final state = await _state(tester);
    await state.setCustomShortcuts([
      TerminalShortcut(label: 'Review', value: 'Review the code\nExplain changes'),
    ]);
    final sent = await _pumpTerminal(tester, state);
    await tester.tap(find.text('Review'));
    await tester.pumpAndSettle();
    expect(sent.join(), '\x1b[200~Review the code\nExplain changes\x1b[201~');
  });

  testWidgets(
    'Paste inserts the clipboard immediately as one bracketed paste',
    (tester) async {
      final state = await _state(tester);
      final sent = await _pumpTerminal(tester, state);
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async => call.method == 'Clipboard.getData'
            ? {'text': 'first line\nsecond line'}
            : null,
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      state.toggleCtrl();
      state.toggleShift();
      await tester.pump();
      await tester.tap(find.text('PASTE'));
      await tester.pumpAndSettle();
      expect(sent.join(), '\x1b[200~first line\nsecond line\x1b[201~');
      expect(state.ctrlArmed, isFalse);
      expect(state.shiftArmed, isFalse);
    },
  );

  testWidgets(
    'Paste ignores an empty clipboard and a session switch during read',
    (tester) async {
      final state = await _state(tester);
      final sent = await _pumpTerminal(tester, state);
      final pending = Completer<Map<String, String>?>();
      var reads = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        SystemChannels.platform,
        (call) async {
          if (call.method != 'Clipboard.getData') return null;
          if (reads++ == 0) return {'text': ''};
          return pending.future;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      await tester.tap(find.text('PASTE'));
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      await tester.tap(find.text('PASTE'));
      await tester.pump();
      state.createNewSession(profile: state.activeProfile!, connect: false);
      final other = <String>[];
      state.terminal.onOutput = other.add;
      pending.complete({'text': 'clipboard'});
      await tester.pumpAndSettle();
      expect(sent, isEmpty);
      expect(other, isEmpty);
    },
  );

  testWidgets('arrow taps send keys; swipes replace the whole keyboard', (
    tester,
  ) async {
    final state = await _state(tester);
    await state.setShortcutLayout(TerminalShortcutLayout.inline);
    final sent = await _pump(tester, state);
    await tester.tap(find.text('↑'));
    await tester.pumpAndSettle();
    expect(sent, ['\x1b[A']);
    expect(find.text('PROMPT PANEL'), findsNothing);

    await _open(tester);
    expect(find.text('PROMPT PANEL'), findsOneWidget);
    expect(find.text('ESC'), findsNothing);
    expect(sent, ['\x1b[A'], reason: 'a swipe must never send an arrow');
    await tester.tap(find.text('EXIT'));
    await tester.tap(find.text('PASTE'));
    await tester.tap(find.text('ENTER'));
    expect(sent, ['\x1b[A', '\x03', 'action:paste', '\r']);

    await tester.drag(
      find.byKey(const ValueKey('custom-prompt-panel')),
      const Offset(120, 0),
    );
    await tester.pumpAndSettle();
    expect(find.text('ESC'), findsOneWidget);
    expect(find.text('PROMPT PANEL'), findsNothing);
  });

  testWidgets('middle swipes still change layers without opening prompts', (
    tester,
  ) async {
    final state = await _state(tester);
    await _pump(tester, state);
    final before = state.activeShortcutLayer;
    await tester.drag(find.byType(PageView), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(state.activeShortcutLayer, isNot(before));
    expect(find.text('PROMPT PANEL'), findsNothing);
  });

  testWidgets('returning from prompts restores the selected keyboard layer',
      (tester) async {
    final state = await _state(tester);
    await _pump(tester, state);
    await tester.tap(find.text('FN'));
    await tester.pumpAndSettle();
    await _open(tester);
    await tester.tap(find.byTooltip('Back to keyboard'));
    await tester.pumpAndSettle();
    expect(find.text('F5'), findsOneWidget);
  });

  for (final layout in [
    TerminalShortcutLayout.dpadLeft,
    TerminalShortcutLayout.dpadRight,
  ]) {
    testWidgets('$layout arrows can open the prompt panel', (tester) async {
      final state = await _state(tester);
      await state.setShortcutLayout(layout);
      final sent = await _pump(tester, state);
      await tester.drag(find.text('↑').first, const Offset(-100, 0));
      await tester.pumpAndSettle();
      expect(find.text('PROMPT PANEL'), findsOneWidget);
      expect(sent, isEmpty);
    });
  }

  for (final width in [320.0, 640.0]) {
    testWidgets('prompts scroll while controls stay on the right at $width', (
      tester,
    ) async {
      final state = await _state(tester);
      await state.setCustomShortcuts([
        for (var i = 0; i < 24; i++)
          TerminalShortcut(label: 'Prompt $i', value: 'command $i\\r'),
        TerminalShortcut(label: 'Hidden', value: 'hidden', enabled: false),
      ]);
      final sent = await _pump(tester, state, width: width);
      await _open(tester);
      final controls = tester.getRect(find.text('EXIT'));
      expect(
        controls.left,
        greaterThan(tester.getRect(find.text('Prompt 0')).right),
      );
      expect(controls.right, lessThan(width));
      expect(find.text('Hidden'), findsNothing);
      await tester.tap(find.text('Prompt 0'));
      expect(sent, ['command 0\r']);
      await tester.drag(find.byType(GridView), const Offset(0, -700));
      await tester.pumpAndSettle();
      expect(tester.getRect(find.text('EXIT')), controls);
      expect(find.text('PASTE'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('prompt settings edit, enable and reorder only user buttons', (
    tester,
  ) async {
    final state = await _state(tester);
    await state.setCustomShortcuts([
      TerminalShortcut(label: 'AGENTES', value: 'system:agents'),
      TerminalShortcut(label: 'First', value: 'first'),
      TerminalShortcut(label: 'Disabled', value: 'disabled', enabled: false),
      TerminalShortcut(label: 'Second', value: 'second\\r'),
    ]);
    await _pump(tester, state);
    await _open(tester);
    await tester.tap(find.byTooltip('Prompt settings'));
    await tester.pumpAndSettle();
    expect(find.text('PROMPT SETTINGS'), findsOneWidget);
    expect(find.text('AGENTES'), findsNothing);
    expect(find.text('Disabled'), findsOneWidget);

    final reorder = tester.widget<ReorderableListView>(
      find.byType(ReorderableListView),
    );
    // Move Second ahead of First; system actions must retain their slots.
    // ignore: deprecated_member_use
    reorder.onReorder!(2, 0);
    await tester.pumpAndSettle();
    expect(state.customShortcuts.map((s) => s.label), [
      'AGENTES',
      'Second',
      'First',
      'Disabled',
    ]);
    await tester.tap(find.byIcon(Icons.edit).first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'PEGAR');
    await tester.enterText(find.byType(TextField).last, 'git status\\r');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox).last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('CLOSE'));
    await tester.pumpAndSettle();
    expect(
      find.text('PEGAR'),
      findsOneWidget,
      reason: 'user button names must not be translated',
    );
    expect(find.text('Disabled'), findsOneWidget);
    final restored = AppState();
    await tester.pumpAndSettle();
    expect(restored.myShortcuts.map((s) => s.label), [
      'PEGAR',
      'First',
      'Disabled',
    ]);
    expect(restored.myShortcuts.first.parsedValue, 'git status\r');
  });

  testWidgets('empty panel keeps controls and can add a multiline prompt', (
    tester,
  ) async {
    final state = await _state(tester);
    await state.setCustomShortcuts([]);
    await state.setShortcutLayers([]);
    await _pump(tester, state);
    await tester.tap(find.byIcon(Icons.swap_horiz));
    await tester.pumpAndSettle();
    expect(find.text('EXIT'), findsOneWidget);
    await tester.tap(find.text('Add prompt'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add prompt'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 260);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'Review');
    await tester.enterText(
      find.byType(TextField).last,
      'Review this code\nExplain the changes',
    );
    await tester.ensureVisible(find.text('SAVE'));
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();
    expect(state.myShortcuts.single.label, 'Review');
    expect(
      state.myShortcuts.single.value,
      'Review this code\nExplain the changes',
    );
    expect(tester.takeException(), isNull);
  });
}
