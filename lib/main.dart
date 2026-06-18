import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';

void main() {
  runApp(const SecurityApp());
}

class SecurityApp extends StatelessWidget {
  const SecurityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Security Dashboard',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blueGrey),
        useMaterial3: true,
      ),
      home: const DashboardScreen(),
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
  
  // State variables untuk UI
  String connectionState = 'Disconnected';
  String statusCahaya = 'Menunggu data...';
  String statusSistem = 'Menunggu data...';
  String notifikasi = 'Aman';
  bool isSystemArmed = true;

  @override
  void initState() {
    super.initState();
    _setupMqttClient();
  }

  Future<void> _setupMqttClient() async {
    // Setup client sesuai dengan konfigurasi ESP32 kamu
    client = MqttServerClient('broker.hivemq.com', 'flutter_client_${DateTime.now().millisecondsSinceEpoch}');
    client.port = 1883;
    client.logging(on: false);
    client.keepAlivePeriod = 20;
    
    final connMess = MqttConnectMessage()
        .withClientIdentifier('flutter_client_${DateTime.now().millisecondsSinceEpoch}')
        .withWillQos(MqttQos.atLeastOnce);
    client.connectionMessage = connMess;

    try {
      setState(() => connectionState = 'Connecting...');
      await client.connect();
    } on NoConnectionException catch (e) {
      print('MQTT Client exception: $e');
      client.disconnect();
    } on SocketException catch (e) {
      print('MQTT Socket exception: $e');
      client.disconnect();
    }

    if (client.connectionStatus!.state == MqttConnectionState.connected) {
      setState(() => connectionState = 'Connected');
      
      // Subscribe ke topik yang dikirim ESP32
      client.subscribe('sistem/cahaya', MqttQos.atMostOnce);
      client.subscribe('sistem/notifikasi', MqttQos.atMostOnce);
      client.subscribe('sistem/status', MqttQos.atMostOnce);

      // Listener untuk pesan masuk
      client.updates!.listen((List<MqttReceivedMessage<MqttMessage?>>? c) {
        final recMess = c![0].payload as MqttPublishMessage;
        final payload = MqttPublishPayload.bytesToStringAsString(recMess.payload.message);
        final topic = c[0].topic;

        setState(() {
          if (topic == 'sistem/cahaya') {
            statusCahaya = payload;
          } else if (topic == 'sistem/notifikasi') {
            notifikasi = payload;
          } else if (topic == 'sistem/status') {
            statusSistem = payload;
          }
        });
      });
    } else {
      setState(() => connectionState = 'Failed to connect');
      client.disconnect();
    }
  }

  // Fungsi untuk mengirim perintah ON/OFF ke ESP32 Pintu
  void _toggleSystem(bool value) {
    final builder = MqttClientPayloadBuilder();
    builder.addString(value ? 'on' : 'off');
    
    client.publishMessage('sistem/control', MqttQos.atMostOnce, builder.payload!);
    
    setState(() {
      isSystemArmed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Home Security Control'),
        backgroundColor: Colors.blueGrey.shade800,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Status Koneksi
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: connectionState == 'Connected' ? Colors.green.shade100 : Colors.red.shade100,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Broker Status: $connectionState',
                style: const TextStyle(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 24),

            // Card Notifikasi
            Card(
              color: notifikasi.contains('PENYUSUP') ? Colors.red.shade100 : Colors.green.shade50,
              child: Padding(
                padding: const EdgeInsets.all(20.0),
                child: Column(
                  children: [
                    const Text('Status Keamanan', style: TextStyle(fontSize: 16)),
                    const SizedBox(height: 8),
                    Text(
                      notifikasi,
                      style: TextStyle(
                        fontSize: 24, 
                        fontWeight: FontWeight.bold,
                        color: notifikasi.contains('PENYUSUP') ? Colors.red.shade900 : Colors.green.shade900,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Sensor Data Row
            Row(
              children: [
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(Icons.light_mode, size: 40, color: Colors.orange),
                          const SizedBox(height: 8),
                          const Text('Kondisi Cahaya'),
                          Text(statusCahaya, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        children: [
                          const Icon(Icons.security, size: 40, color: Colors.blue),
                          const SizedBox(height: 8),
                          const Text('Sistem PIR'),
                          Text(statusSistem, style: const TextStyle(fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),

            // Control Switch (ARM/DISARM)
            const Text(
              'Control Panel',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('DISARMED', style: TextStyle(fontWeight: FontWeight.bold)),
                Switch(
                  value: isSystemArmed,
                  activeColor: Colors.red,
                  onChanged: (value) {
                    _toggleSystem(value);
                  },
                ),
                const Text('ARMED', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
              ],
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
