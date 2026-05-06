import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'providers/feed_provider.dart';
import 'providers/settings_provider.dart';
import 'screens/home_screen.dart';
import 'screens/history_screen.dart';
import 'screens/settings_screen.dart';
import 'services/storage_service.dart';
import 'services/audio_service.dart';
import 'services/notification_service.dart';
import 'utils/constants.dart';

class FeedReminderApp extends StatefulWidget {
  const FeedReminderApp({super.key});

  @override
  State<FeedReminderApp> createState() => _FeedReminderAppState();
}

class _FeedReminderAppState extends State<FeedReminderApp> {
  int _currentIndex = 0;

  final List<Widget> _screens = const [
    HomeScreen(),
    HistoryScreen(),
    SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<StorageService>(
          create: (_) => StorageService(),
        ),
        Provider<AudioService>(
          create: (_) => AudioService(),
        ),
        Provider<NotificationService>(
          create: (_) => NotificationService(),
        ),
        ChangeNotifierProxyProvider<StorageService, SettingsProvider>(
          create: (context) =>
              SettingsProvider(storage: context.read<StorageService>()),
          update: (context, storage, previous) =>
              previous ?? SettingsProvider(storage: storage),
        ),
        ChangeNotifierProxyProvider3<StorageService, AudioService,
            NotificationService, FeedProvider>(
          create: (context) => FeedProvider(
            storage: context.read<StorageService>(),
            audioService: context.read<AudioService>(),
            notificationService: context.read<NotificationService>(),
          ),
          update: (context, storage, audio, notification, previous) =>
              previous ??
              FeedProvider(
                storage: storage,
                audioService: audio,
                notificationService: notification,
              ),
        ),
      ],
      child: MaterialApp(
        title: AppStrings.appName,
        debugShowCheckedModeBanner: false,
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppColors.pink,
            surface: AppColors.background,
          ),
          useMaterial3: true,
          fontFamily: 'SF Pro Display',
        ),
        home: _buildMainScreen(),
      ),
    );
  }

  Widget _buildMainScreen() {
    return Scaffold(
      body: PageView(
        controller: PageController(initialPage: _currentIndex),
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        children:_screens ,
      ),
      bottomNavigationBar: SafeArea(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            _screens.length,
            (index) => _buildDot(index),
          ),
        ),
      ),
    );
  }

  Widget _buildDot(int index) {
    final isActive = index == _currentIndex;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.symmetric(horizontal: 4),
      width: isActive ? 24 : 8,
      height: 8,
      decoration: BoxDecoration(
        color: isActive ? AppColors.pink : AppColors.textLight.withOpacity(0.3),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}
