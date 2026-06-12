import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:mqtt_client/mqtt_client.dart';
import 'package:mqtt_client/mqtt_server_client.dart';
// Import package baru
import 'package:audioplayers/audioplayers.dart';
import 'package:file_picker/file_picker.dart';

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

  double _armScale = 1.0;
  double _disarmScale = 1.0;

  bool _isMotionActive = false;
  bool _runRight = true;
  Timer? _motionTimer;
  Timer? _runTimer;
  bool _isAlertDialogOpen = false;

  // Variabel untuk Audio Player
  final AudioPlayer _audioPlayer = AudioPlayer();
  String? _customAlarmPath;

  bool get isConnected => connectionState == 'Terhubung';

  @override
  void initState() {
    super.initState();
    _connectMqtt();
  }

  // --- FUNGSI UNTUK MEMILIH FILE MP3 DARI HP ---
  Future<void> _pickCustomAlarm() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.audio, // Hanya izinkan file audio/mp3
    );

    if (result != null) {
      setState(() {
        _customAlarmPath = result.files.single.path;
      });
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Suara Alarm Berhasil Dipilih: ${result.files.single.name}'),
            backgroundColor: Colors.green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _connectMqtt() async {
    if (_isClientInitialized && client.connectionStatus?.state == MqttConnectionState.connected) {
      client.disconnect();
    }

    String clientId = 'app_scurity_${DateTime.now().millisecond}';
    client = MqttServerClient('ws://broker.hivemq.com/mqtt', clientId);
    client.useWebSocket = true; 
    client.port = 8000;         
    client.keepAlivePeriod = 60;
    _isClientInitialized = true;

    client.onDisconnected = () {
      if (mounted) setState(() => connectionState = 'Terputus (Disconnected)');
    };

    final connMess = MqttConnectMessage().withClientIdentifier(clientId).startClean();
    client.connectionMessage = connMess;

    try {
      if (mounted) setState(() => connectionState = 'Menghubungkan...');
      await client.connect();
    } on SocketException catch (_) {
      if (mounted) setState(() => connectionState = 'Diblokir Jaringan');
      client.disconnect();
      return;
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

              if (payload.contains("SYSTEM ARMED")) isSystemArmed = true;
              if (payload.contains("SYSTEM DISARMED")) isSystemArmed = false;

              if (payload.contains("GERAKAN TERDETEKSI")) {
                _triggerMotionAnimation();
              }

              if (isAlert && !_isAlertDialogOpen) {
                _showIntruderAlert();
              }
            }
          });
        }
      });
    }
  }

  void _triggerMotionAnimation() {
    setState(() => _isMotionActive = true);
    
    _runTimer?.cancel();
    _runTimer = Timer.periodic(const Duration(milliseconds: 300), (timer) {
      if (mounted) setState(() => _runRight = !_runRight);
    });

    _motionTimer?.cancel();
    _motionTimer = Timer(const Duration(seconds: 4), () {
      if (mounted) {
        setState(() => _isMotionActive = false);
        _runTimer?.cancel();
      }
    });
  }

  // --- FUNGSI MOCKUP PENYUSUP DENGAN AUDIO ---
  void _showIntruderAlert() async {
    _isAlertDialogOpen = true;

    // Memutar MP3 jika pengguna sudah memilih file
    if (_customAlarmPath != null) {
      await _audioPlayer.setReleaseMode(ReleaseMode.loop); // Mode berulang/loop
      await _audioPlayer.play(DeviceFileSource(_customAlarmPath!));
    } else {
      // Jika belum milih MP3, beri peringatan kecil di bawah
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Penyusup terdeteksi! (Pilih MP3 di pojok kanan atas untuk suara alarm)')),
      );
    }

    if (!mounted) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.redAccent.withOpacity(0.8),
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.red[900],
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Column(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.yellowAccent, size: 90),
              SizedBox(height: 10),
              Text('AWAS PENYUSUP!', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 28, letterSpacing: 1)),
            ],
          ),
          content: const Text(
            'Sensor PIR mendeteksi pergerakan di area dalam kondisi gelap/Armed. Harap periksa keamanan segera!',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white, fontSize: 16),
          ),
          actionsAlignment: MainAxisAlignment.center,
          actions: [
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red[900],
                padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              ),
              onPressed: () {
                Navigator.of(context).pop();
                _isAlertDialogOpen = false;
                _audioPlayer.stop(); // MATIKAN MP3 SAAT TOMBOL DITEKAN
              },
              child: const Text('TUTUP ALARM', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
            )
          ],
        );
      },
    ).then((_) {
      _isAlertDialogOpen = false;
      _audioPlayer.stop(); // Memastikan audio mati jika dialog dipaksa tutup
    });
  }

  void _publishControl(String mode) {
    if (!isConnected) return;
    final builder = MqttClientPayloadBuilder();
    builder.addString(mode);
    client.publishMessage('sistem/control', MqttQos.atLeastOnce, builder.payload!);
    setState(() {
      isSystemArmed = (mode == 'on');
    });
  }

  Widget _buildCircularButton({
    required String title,
    required IconData icon,
    required Color activeColor,
    required bool isArmButton,
  }) {
    Color buttonColor = isConnected ? activeColor : Colors.grey[500]!;
    
    return Column(
      children: [
        GestureDetector(
          onTapDown: (_) => setState(() => isArmButton ? _armScale = 0.85 : _disarmScale = 0.85),
          onTapUp: (_) {
            setState(() => isArmButton ? _armScale = 1.0 : _disarmScale = 1.0);
            _publishControl(isArmButton ? 'on' : 'off');
          },
          onTapCancel: () => setState(() => isArmButton ? _armScale = 1.0 : _disarmScale = 1.0),
          child: AnimatedScale(
            scale: isArmButton ? _armScale : _disarmScale,
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutBack,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: buttonColor,
                shape: BoxShape.circle,
                boxShadow: isConnected
                    ? [BoxShadow(color: activeColor.withOpacity(0.4), blurRadius: 15, offset: const Offset(0, 8))]
                    : [],
              ),
              child: Icon(icon, color: Colors.white, size: 36),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(title, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 1, color: Theme.of(context).colorScheme.onSurface.withOpacity(0.8))),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SCURITY', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.0, fontSize: 22)),
        centerTitle: false,
        elevation: 0,
        backgroundColor: Colors.transparent,
        actions: [
          // TOMBOL PILIH MP3 ALARM KUSTOM
          IconButton(
            icon: Icon(
              Icons.library_music_rounded, 
              color: _customAlarmPath != null ? Colors.green : (isDark ? Colors.white70 : Colors.black54)
            ),
            tooltip: 'Pilih Suara Alarm MP3',
            onPressed: _pickCustomAlarm,
          ),
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
      body: RefreshIndicator(
        onRefresh: _connectMqtt,
        color: isDark ? Colors.cyanAccent : Colors.blueAccent,
        backgroundColor: colorScheme.surface,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 10),
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
                            isConnected ? (isSystemArmed ? 'ARMED / AKTIF' : 'DISARMED / NONAKTIF') : 'SISTEM OF
