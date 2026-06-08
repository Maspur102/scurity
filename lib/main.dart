import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

// Notifier global untuk menghandle perubahan tema secara real-time
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.dark);

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
          // Tema Terang (Modern Clean Minimalist)
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
          // Tema Gelap (Futuristic Cyberpunk Slate)
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
  String connectionState = 'Memulai...';
  bool isSystemArmed = true; 
  String cahayaStatus = 'Memuat...';
  List<Map<String, dynamic>> logs = [];

  @override
  void initState() {
    super.initState();
    _connectMqtt();
  }

  Future<void> _connectMqtt() async {
    String clientId = 'scurity_app_${DateTime.now().millisecondsSinceEpoch}';
    client = MqttServerClient('broker.hivemq.com', clientId);
    client.port = 1883;
    client.keepAlivePeriod = 20;
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
      
      // Menyesuaikan dengan topik dari program ESP32 kamu
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
              // Menampung log & notifikasi dari ESP32
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
    if (client.connectionStatus?.state != MqttConnectionState.connected) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(mode);
    client.publishMessage('sistem/control', MqttQos.atLeastOnce, builder.payload!);
    setState(() {
      isSystemArmed = (mode == 'on');
    });
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
          // Tombol Toggle Light/Dark Mode Modern
          IconButton(
            icon: Icon(isDark ? Icons.light_mode_rounded : Icons.dark_mode_rounded),
            onPressed: () {
              themeNotifier.value = isDark ? ThemeMode.light : ThemeMode.dark;
            },
          ),
          // Indikator Status Koneksi MQTT Broker
          Container(
            margin: const EdgeInsets.only(right: 16, left: 8),
            child: CircleAvatar(
              radius: 6,
              backgroundColor: connectionState == 'Terhubung' ? Colors.greenAccent : Colors.redAccent,
            ),
          )
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 10),
            // Hub Status Card (Glassmorphic look)
            Container(
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
                  // Indikator Utama ARMED/DISARMED berbentuk status ring modern
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: (isSystemArmed ? Colors.green : Colors.red).withOpacity(0.1),
                    ),
                    child: Icon(
                      isSystemArmed ? Icons.shield_rounded : Icons.shield_outlined,
                      size: 64,
                      color: isSystemArmed ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 15),
                  Text(
                    isSystemArmed ? 'ARMED / AKTIF' : 'DISARMED / NONAKTIF',
                    style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: isSystemArmed ? Colors.green : Colors.red),
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

            // LDR Sensor Monitor Row
            Row(
              children: [
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.surface,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: colorScheme.onSurface.withOpacity(0.05)),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.wb_sunny_rounded, color: Colors.amber[600]),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('INTENSITAS CAHAYA', style: TextStyle(fontSize: 10, color: colorScheme.onSurface.withOpacity(0.5), fontWeight: FontWeight.bold)),
                            Text(cahayaStatus, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                          ],
                        )
                      ],
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // Tombol Aktivasi Kontrol Utama
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => _publishControl('on'),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.green.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5))],
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_outline_rounded, color: Colors.white),
                            SizedBox(width: 8),
                            Text('ARM SYSTEM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: InkWell(
                    onTap: () => _publishControl('off'),
                    borderRadius: BorderRadius.circular(20),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 18),
                      decoration: BoxDecoration(
                        color: Colors.red,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [BoxShadow(color: Colors.red.withOpacity(0.3), blurRadius: 12, offset: const Offset(0, 5))],
                      ),
                      child: const Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.lock_open_rounded, color: Colors.white),
                            SizedBox(width: 8),
                            Text('DISARM SYSTEM', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16)),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Log Console Terminal Style
            Text('LOG KONSOL AKTIVITAS', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: colorScheme.onSurface.withOpacity(0.6))),
            const SizedBox(height: 8),
            Expanded(
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
            const SizedBox(height: 16),
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