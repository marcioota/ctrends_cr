import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:provider/provider.dart';

String? _globalFcmToken;

class WebViewControllerProvider with ChangeNotifier {
  InAppWebViewController? _controller;

  InAppWebViewController? get controller => _controller;

  set controller(InAppWebViewController? ctrl) {
    _controller = ctrl;

    if (_controller != null) {
      _controller!.addJavaScriptHandler(
        handlerName: 'getFCMToken',
        callback: (args) async {
          print('📨 JavaScript pediu o FCM Token!');
          if (_globalFcmToken != null) {
            _controller!.evaluateJavascript(source: """
              if (window.receiveFcmToken) {
                window.receiveFcmToken(${jsonEncode(_globalFcmToken)});
              }
            """);
          } else {
            print('⚠️ Token ainda não disponível');
          }
        },
      );
    }

    notifyListeners();
  }
}

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

const bool isLocalDev = true;
final String devUrl = 'http://192.168.0.33:9000';
final String prodUrl = 'https://ctrends.esystem.com.br';

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  _showForegroundNotification(message);
}

Future<void> _initLocalNotifications() async {
  const androidSettings = AndroidInitializationSettings('@mipmap/orange_blue');
  const initSettings = InitializationSettings(android: androidSettings);

  await flutterLocalNotificationsPlugin.initialize(initSettings);

  const AndroidNotificationChannel channel = AndroidNotificationChannel(
    'default_channel',
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

  const androidDetails = AndroidNotificationDetails(
    'default_channel',
    'Notificações',
    channelDescription: 'Notificações gerais',
    importance: Importance.max,
    priority: Priority.high,
    playSound: true,
    icon: '@mipmap/orange_blue',
  );

  const notificationDetails = NotificationDetails(android: androidDetails);

  flutterLocalNotificationsPlugin.show(
    DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title,
    body,
    notificationDetails,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  await _initLocalNotifications();
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  runApp(
    ChangeNotifierProvider(
      create: (_) => WebViewControllerProvider(),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        home: WebViewScreen(),
      ),
    ),
  );
}

class WebViewScreen extends StatefulWidget {
  @override
  _WebViewScreenState createState() => _WebViewScreenState();
}

class _WebViewScreenState extends State<WebViewScreen>
    with WidgetsBindingObserver {
  InAppWebViewController? _webViewController;
  String fcmToken = '';
  bool isLoading = true;

  String get initialUrl => isLocalDev ? devUrl : prodUrl;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    requestNotificationPermission();

    // Armazena token assim que possível
    FirebaseMessaging.instance.getToken().then((token) {
      setState(() {
        _globalFcmToken = token;
      });
      if (token != null) {
        _sendTokenToWebView(token);
      }
      print('📲 Token inicial do FCM: $_globalFcmToken');
    });

    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showForegroundNotification(message);

      // Extrai os campos do data payload, caso existam
      final data = message.data;
      if (data.containsKey('tipo') && data.containsKey('processo_id')) {
        _sendMessageToWebView({
          'tipo': data['tipo'],
          'processo_id': data['processo_id'],
        });
      }
    });
  }

  void _sendTokenToWebView(String token) {
    _webViewController?.evaluateJavascript(source: """
      if (window.onFlutterFCMToken) {
        window.onFlutterFCMToken(${jsonEncode(token)});
      }
    """);
  }

  void _sendMessageToWebView(Map<String, dynamic> data) {
    final payload = jsonEncode({
      "processo_id": data['processo_id'],
      "tipo": data['tipo'],
    });

    _webViewController?.evaluateJavascript(source: """
    if (window.onFlutterNotification) {
      window.onFlutterNotification($payload);
    }
  """);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void requestNotificationPermission() async {
    final status = await Permission.notification.status;
    if (!status.isGranted) {
      await Permission.notification.request();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _webViewController?.reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          InAppWebView(
            initialUrlRequest: URLRequest(url: Uri.parse(initialUrl)),
            initialOptions: InAppWebViewGroupOptions(
              crossPlatform: InAppWebViewOptions(
                javaScriptEnabled: true,
                useShouldOverrideUrlLoading: true,
                mediaPlaybackRequiresUserGesture: false,
              ),
              android: AndroidInAppWebViewOptions(
                useHybridComposition: true,
                mixedContentMode:
                    AndroidMixedContentMode.MIXED_CONTENT_ALWAYS_ALLOW,
              ),
            ),
            onWebViewCreated: (controller) {
              _webViewController = controller;

              // Atualiza o Provider
              final webviewProvider = Provider.of<WebViewControllerProvider>(
                  context,
                  listen: false);
              webviewProvider.controller = controller;

              controller.addJavaScriptHandler(
                handlerName: 'FCM',
                callback: (args) async {
                  if (args.isNotEmpty && args[0] == 'get_token') {
                    final token = _globalFcmToken ??
                        await FirebaseMessaging.instance.getToken();

                    if (token != null) {
                      print(
                          '✅ Enviando token FCM por JavaScriptHandler: $token');
                      controller.evaluateJavascript(source: """
          if (window.receiveFcmToken) {
            window.receiveFcmToken(${jsonEncode(token)});
          }
        """);
                    } else {
                      print('❌ Token FCM ainda está nulo');
                    }
                  }
                },
              );
            },
            onLoadStop: (controller, url) {
              setState(() => isLoading = false);

              // Envia o token FCM automaticamente após o carregamento
              if (_globalFcmToken != null) {
                controller.evaluateJavascript(source: """
      if (window.receiveFcmToken) {
        window.receiveFcmToken(${jsonEncode(_globalFcmToken)});
      }
    """);
              }
            },
            onLoadError: (controller, url, code, message) {
              print("Erro ao carregar: $message");
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
                    Text('Carregando...',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.w500)),
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
