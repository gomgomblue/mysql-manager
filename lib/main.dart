import 'package:flutter/material.dart';
import 'screens/login_screen.dart';
import 'screens/main_screen.dart';
import 'services/app_state.dart';
import 'services/app_state_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MySqlWebClientApp());
}

class MySqlWebClientApp extends StatefulWidget {
  const MySqlWebClientApp({Key? key}) : super(key: key);

  @override
  State<MySqlWebClientApp> createState() => _MySqlWebClientAppState();
}

class _MySqlWebClientAppState extends State<MySqlWebClientApp> {
  final AppState _appState = AppState();

  @override
  Widget build(BuildContext context) {
    return AppStateProvider(
      state: _appState,
      child: MaterialApp(
        title: 'gomgom mysql',
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          brightness: Brightness.dark,
          primaryColor: const Color(0xFF6366F1), // Indigo 500
          scaffoldBackgroundColor: const Color(0xFF0F172A), // Slate 900
          cardColor: const Color(0xFF1E293B), // Slate 800
          colorScheme: const ColorScheme.dark(
            primary: Color(0xFF6366F1),
            secondary: Color(0xFF8B5CF6),
            background: Color(0xFF0F172A),
            surface: Color(0xFF1E293B),
            error: Colors.redAccent,
          ),
          textTheme: const TextTheme(
            bodyLarge: TextStyle(color: Color(0xFFF1F5F9)),
            bodyMedium: TextStyle(color: Color(0xFFCBD5E1)),
          ),
          elevatedButtonTheme: ElevatedButtonThemeData(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              foregroundColor: Colors.white,
              elevation: 2,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          popupMenuTheme: const PopupMenuThemeData(
            color: Color(0xFF1E293B),
            textStyle: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        home: const AppRootWidget(),
      ),
    );
  }
}

class AppRootWidget extends StatelessWidget {
  const AppRootWidget({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final state = AppStateProvider.of(context);
    
    // Switch between Connection Login or DB Client main screen
    if (state.isConnected) {
      return const MainScreen();
    } else {
      return const LoginScreen();
    }
  }
}
