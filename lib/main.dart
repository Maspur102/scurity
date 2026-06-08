import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

// 1. Default diubah menjadi ThemeMode.light agar langsung terang saat dibuka
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.light);

void main() {
  runApp(const ScurityApp());
}

class ScurityApp extends StatelessWidget {
  const ScurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (_, currentMode, __) {
        return MaterialApp(
          title: 'Scurity Smart Home',
          debugShowCheckedModeBanner: false,
          themeMode: currentMode,
          // Tema Terang
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF1A73E8),
              brightness: Brightness.light,
              background: const Color(0xFFF8F9FA),
              surface: Colors.white,
            ),
            scaffoldBackgroundColor: const Color(0xFFF8F9FA),
          ),
          // Tema Gelap
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorScheme: ColorScheme.fromSeed(
              seedColor: const Color(0xFF00E5FF),
              brightness: Brightness.dark,
              background: const Color(0xFF0B0E14),
              surface: const Color(0xFF161B22),
            ),
            scaffoldBackgroundColor: const Color(0xFF0B0E14),
          ),
          home: const DashboardScreen(),
        );
      },
    );
  }
}

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  late MqttServerClient client;
  bool _isClientInitialized = false;
  String connectionState = 'Memulai...';
  bool isSystemArmed = true;
  String cahayaStatus = 'Memuat...';
  List<Map<String, dynamic>> logs = [];

  // Variabel untuk animasi tombol membal
  double _armScale = 1.0;
  double _disarmScale = 1.0;

  bool get isConnected => connectionState == 'Terhubung';

  @override
  void initState() {
    super.initState();
    _connectMqtt();
  }

  Future<void> _connectMqtt() async {
    if (_isClientInitialized && client.connectionStatus?.state == MqttConnectionState.connected) {
      client.disconnect();
    }

    String clientId = 'scurity_app_${DateTime.now().millisecondsSinceEpoch}';
    client = MqttServerClient('broker.hivemq.com', clientId);
    client.port = 1883;
    client.keepAlivePeriod = 20;
    _isClientInitialized = true;

    client.onDisconnected = () {
      if (mounted) setState(() => connectionState = 'Terputus');
    };

    final connMess = MqttConnectMessage()
        .withClientIdentifier(clientId)
        .startClean()
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;

    try {
      if (mounted) setState(() => connectionState = 'Menghubungkan...');
      await client.connect();
    } catch (e) {
      if (mounted) setState(() => connectionState = 'Gagal Terhubung');
      client.disconnect();
      return;
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      if (mounted) setState(() => connectionState = 'Terhubung');

      client.subscribe('sistem/log', MqttQos.atMostOnce);
      client.subscribe('sistem/cahaya', MqttQos.atMostOnce);
      client.subscribe('sistem/notifikasi', MqttQos.atMostOnce);

      client.updates!.listen((List<MqttReceivedMessage<MqttMessage>> c) {
        final MqttPublishMessage recMess = c[0].payload as MqttPublishMessage;
        final String payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final String topic = c[0].topic;

        if (mounted) {
          setState(() {
            if (topic == 'sistem/cahaya') {
              cahayaStatus = payload.toUpperCase();
            } else {
              bool isAlert = topic == 'sistem/notifikasi' || payload.contains("PENYUSUP");
              logs.insert(0, {
                'time': "${DateTime.now().hour.toString().padLeft(2, '0')}:${DateTime.now().minute.toString().padLeft(2, '0')}",
                'msg': payload,
                'isAlert': isAlert
              });
              if (logs.length > 30) logs.removeLast();

              if (payload == "SYSTEM ARMED") isSystemArmed = true;
              if (payload == "SYSTEM DISARMED") isSystemArmed = false;
            }
          });
        }
      });
    }
  }

  void _publishControl(String mode) {
    if (!isConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Koneksi terputus! Tarik layar ke bawah untuk memuat ulang.'),
          backgroundColor: Colors.redAccent,
        ),
      );
      return;
    }

    final builder = MqttClientPayloadBuilder();
    builder.addString(mode);
    client.publishMessage('sistem/control', MqttQos.atLeastOnce, builder.payload!);
    setState(() {
      isSystemArmed = (mode == 'on');
    });
  }

  // Tombol Pintar dengan Animasi
  Widget _buildAnimatedButton({
    required String title,
    required IconData icon,
    required Color activeColor,
    required bool isArmButton,
  }) {
    Color buttonColor = isConnected ? activeColor : Colors.grey[500]!;
    
    return Expanded(
      child: GestureDetector(
        onTapDown: (_) => setState(() => isArmButton ? _armScale = 0.93 : _disarmScale = 0.93),
        onTapUp: (_) {
          setState(() => isArmButton ? _armScale = 1.0 : _disarmScale = 1.0);
          _publishControl(isArmButton ? 'on' : 'off');
        },
        onTapCancel: () => setState(() => isArmButton ? _armScale = 1.0 : _disarmScale = 1.0),
        child: AnimatedScale(
          scale: isArmButton ? _armScale : _disarmScale,
          duration: const Duration(milliseconds: 100),
          curve: Curves.easeInOut,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: buttonColor,
              borderRadius: BorderRadius.circular(20),
              boxShadow: isConnected
                  ? [BoxShadow(color: activeColor.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5))]
                  : [],
            ),
            child: Center(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SCURITY OS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 1.5, fontSize: 20)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () {
              themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          Container(
            margin: const EdgeInsets.only(right: 16, left: 8),
            child: CircleAvatar(
              radius: 6,
              backgroundColor: isConnected ? Colors.greenAccent : Colors.redAccent,
            ),
          )
        ],
      ),
      // Membungkus Body dengan RefreshIndicator dan CustomScrollView
      body: RefreshIndicator(
        onRefresh: _connectMqtt,
        color: isDark ? Colors.cyanAccent : Colors.blueAccent,
        backgroundColor: colorScheme.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(), // Wajib agar bisa di-scroll & di-refresh walau konten sedikit
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
                    // Hub Status Card
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 400),
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(28),
                        boxShadow: [
                          BoxShadow(
                            color: isDark ? Colors.black38 : Colors.grey.withOpacity(0.1),
                            blurRadius: 20,
                            offset: const Offset(0, 10),
                          )
                        ],
                        border: Border.all(color: colorScheme.onSurface.withOpacity(0.05)),
                      ),
                      child: Column(
                        children: [
                          Text(
                            'SISTEM KEAMANAN',
                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 2, color: colorScheme.onSurface.withOpacity(0.5)),
                          ),
                          const SizedBox(height: 15),
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isConnected 
                                ? (isSystemArmed ? Colors.green : Colors.red).withOpacity(0.1)
                                : Colors.grey.withOpacity(0.1),
                            ),
                            child: Icon(
                              isSystemArmed ? Icons.shield_rounded : Icons.shield_outlined,
                              size: 64,
                              color: isConnected ? (isSystemArmed ? Colors.green : Colors.red) : Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 15),
                          Text(
                            isConnected ? (isSystemArmed ? 'ARMED / AKTIF' : 'DISARMED / NONAKTIF') : 'SISTEM OFFLINE',
                            style: TextStyle(
                              fontSize: 22, 
                              fontWeight: FontWeight.w800, 
                              color: isConnected ? (isSystemArmed ? Colors.green : Colors.red) : Colors.grey,
                            ),
                          ),
                          const SizedBox(height: 5),
                          Text(
                            'Broker Status: $connectionState',
                            style: TextStyle(fontSize: 12, color: colorScheme.onSurface.withOpacity(0.4)),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // LDR Sensor Card
                    Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: colorScheme.onSurface.withOpacity(0.05)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wb_sunny_rounded, color: isConnected ? Colors.amber[600] : Colors.grey),
                          const SizedBox(width: 12),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('INTENSITAS CAHAYA', style: TextStyle(fontSize: 10, color: colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.bold)),
                              Text(isConnected ? cahayaStatus : 'Offline', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                            ],
                          )
                        ],
                      ),
                    ),
                    const SizedBox(height: 20),

                    // Baris Tombol Kontrol
                    Row(
                      children: [
                        _buildAnimatedButton(
                          title: 'ARM SYSTEM',
                          icon: Icons.lock_outline_rounded,
                          activeColor: Colors.green,
                          isArmButton: true,
                        ),
                        const SizedBox(width: 12),
                        _buildAnimatedButton(
                          title: 'DISARM SYSTEM',
                          icon: Icons.lock_open_rounded,
                          activeColor: Colors.red,
                          isArmButton: false,
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    Text('LOG KONSOL AKTIVITAS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: colorScheme.onSurface.withOpacity(0.6))),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            // SliverFillRemaining untuk List Log agar menyesuaikan sisa tinggi layar
            SliverFillRemaining(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Container(
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF05070A) : Colors.grey[200],
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: logs.isEmpty
                      ? Center(child: Text('Belum ada log aktivitas dari ESP32', style: TextStyle(color: colorScheme.onSurface.withOpacity(0.3), fontSize: 13)))
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: logs.length,
                          itemBuilder: (context, index) {
                            final log = logs[index];
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6.0),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('[${log['time']}] ', style: TextStyle(fontFamily: 'monospace', color: colorScheme.onSurface.withOpacity(0.4), fontSize: 12)),
                                  Expanded(
                                    child: Text(
                                      log['msg'],
                                      style: TextStyle(
                                        fontFamily: 'monospace',
                                        fontSize: 12,
                                        fontWeight: log['isAlert'] ? FontWeight.bold : FontWeight.normal,
                                        color: log['isAlert'] ? Colors.redAccent : (isDark ? Colors.greenAccent : Colors.black87),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    client.disconnect();
    super.dispose();
  }
}