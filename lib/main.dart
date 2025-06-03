import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart'; // salvar última URL
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings(
      '@mipmap/orange_blue'); // use temporariamente este ícone

  const initSettings = InitializationSettings(android: androidSettings);
  await flutterLocalNotificationsPlugin.initialize(initSettings);

  // 👇 Cria o canal manualmente
  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'default_channel', // ✅ mesmo nome
    'Notificações',
    description: 'Canal padrão de notificações',
    importance: Importance.max,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(channel);
}

void _showForegroundNotification(RemoteMessage message) {
  final title =
      message.notification?.title ?? message.data['title'] ?? 'Notificação';
  final body =
      message.notification?.body ?? message.data['body'] ?? 'Entre em contato';
  final processo_id = message.data['processo_id'];
  final tipo = message.data['tipo'];
  print('processo_id ${processo_id}');
  print('tipo ${tipo}');
  const androidDetails = AndroidNotificationDetails(
    'default_channel',
    'Notificações',
    channelDescription: 'Notificações gerais',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    icon: '@mipmap/orange_blue', // evite @mipmap/orange se não for white-only
  );

  const notificationDetails = NotificationDetails(android: androidDetails);

  flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    notificationDetails,
  );
}

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  await Firebase.initializeApp();
  print("📨 (BG) Mensagem em background: ${message.data}");
  _showForegroundNotification(message);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await _initLocalNotifications();

  FirebaseMessaging.onBackgroundMessage(
      _firebaseMessagingBackgroundHandler); // ✅ ADICIONE AQUI

  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: WebViewScreen(),
    );
  }
}

class WebViewScreen extends StatefulWidget {
  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen> {
  InAppWebViewController? _webViewController;
  String? _fcmToken;
  bool isLoading = true;
  String initialUrl = 'https://ctrends.esystem.com.br?';

  @override
  void initState() {
    super.initState();
    requestNotificationPermission();

    if (Platform.isAndroid) {
      InAppWebViewController.setWebContentsDebuggingEnabled(true);
    }

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      print('📨 Mensagem recebida em foreground: ${message.data}');
      _showForegroundNotification(message);
    });

    _loadLastUrl();

    // Firebase + notificações continuam iguais...
  }

  void requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  Future<void> _loadLastUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final savedUrl = prefs.getString('last_url');
    if (savedUrl != null) {
      setState(() {
        initialUrl = savedUrl;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: WebUri(initialUrl)),
            initialOptions: InAppWebViewGroupOptions(
              crossPlatform: InAppWebViewOptions(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
              ),
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;
            },
            onLoadStop: (controller, url) async {
              final prefs = await SharedPreferences.getInstance();
              if (url != null) {
                await prefs.setString('last_url', url.toString());
              }
              setState(() {
                isLoading = false;
              });
            },
            onReceivedError: (controller, request, error) async {
              // opcional: mostrar página offline
              print('Erro ao carregar: $error');
            },
          ),
          if (isLoading)
            Container(
              color: Colors.white,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset('assets/icon/orange.png', width: 100),
                    SizedBox(height: 20),
                    Text(
                      'Carregando...',
                      style:
                          TextStyle(fontSize: 18, fontWeight: FontWeight.w500),
                    ),
                    CircularProgressIndicator(),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
