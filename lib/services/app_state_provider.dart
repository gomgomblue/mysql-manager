import 'package:flutter/material.dart';
import 'app_state.dart';

class AppStateProvider extends InheritedNotifier<AppState> {
  const AppStateProvider({
    Key? key,
    required AppState state,
    required Widget child,
  }) : super(key: key, notifier: state, child: child);

  static AppState of(BuildContext context) {
    final provider = context.dependOnInheritedWidgetOfExactType<AppStateProvider>();
    if (provider == null) {
      throw Exception("AppStateProvider not found in context.");
    }
    return provider.notifier!;
  }
}
