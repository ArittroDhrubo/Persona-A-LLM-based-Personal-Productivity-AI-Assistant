import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:intl/intl.dart';
import 'dart:convert';
import 'dart:async';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import 'main.dart';

class ChatScreen extends StatefulWidget {
  const ChatScreen({Key? key}) : super(key: key);

  @override
  _ChatScreenState createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<ChatMessage> _messages = [];
  final AudioPlayer _audioPlayer = AudioPlayer();

  // Device info
  String _deviceName = 'unknown_device';

  // Speech Recognition
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechAvailable = false;
  String _recognizedText = '';

  // Auto-send timer
  Timer? _autoSendTimer;
  int _secondsRemaining = 0;

  WebSocketChannel? _channel;
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _isPlayingAudio = false;
  late Box<Event> eventBox;

  // FIXED: Changed to your actual IP - update this with your backend URL
  static const String WS_URL = 'ws://100.64.101.54:8000/ws/chat';

  @override
  void initState() {
    super.initState();
    eventBox = Hive.box<Event>('events');
    _speech = stt.SpeechToText();
    _initDeviceInfo();
    _initSpeech();
    _connectWebSocket();

    // Listen to audio player state
    _audioPlayer.onPlayerStateChanged.listen((state) {
      if (mounted) {
        setState(() {
          _isPlayingAudio = state == PlayerState.playing;
        });
      }
    });
  }

  Future<void> _initDeviceInfo() async {
    try {
      final deviceInfo = DeviceInfoPlugin();

      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        setState(() {
          _deviceName = '${androidInfo.brand} ${androidInfo.model}';
        });
        print('📱 Device: $_deviceName');
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        setState(() {
          _deviceName = '${iosInfo.name} ${iosInfo.model}';
        });
        print('📱 Device: $_deviceName');
      }
    } catch (e) {
      print('Error getting device info: $e');
      _deviceName = 'unknown_device';
    }
  }

  Future<void> _initSpeech() async {
    try {
      final status = await Permission.microphone.request();

      if (status.isGranted) {
        _speechAvailable = await _speech.initialize(
          onError: (error) {
            print('Speech recognition error: $error');
            if (mounted) {
              setState(() {
                _isListening = false;
              });
            }
            _cancelAutoSendTimer();
          },
          onStatus: (status) {
            print('Speech recognition status: $status');
            if (status == 'done' || status == 'notListening') {
              if (mounted) {
                setState(() {
                  _isListening = false;
                });
                // Start auto-send timer when speech recognition finishes
                Future.delayed(const Duration(milliseconds: 500), () {
                  if (mounted && _messageController.text.trim().isNotEmpty && !_isListening) {
                    _startAutoSendTimer();
                  }
                });
              }
            }
          },
        );
        if (mounted) {
          setState(() {});
        }

        if (_speechAvailable) {
          print('✅ Speech recognition initialized successfully');
        } else {
          print('⚠️ Speech recognition not available');
        }
      } else {
        print('⚠️ Microphone permission denied');
        if (mounted) {
          _showPermissionDialog();
        }
      }
    } catch (e) {
      print('Error initializing speech: $e');
    }
  }

  void _showPermissionDialog() {
    if (!mounted) return;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Microphone Permission Required'),
        content: const Text(
          'This app needs microphone access to use voice commands. Please grant permission in settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _startAutoSendTimer() {
    _cancelAutoSendTimer();

    setState(() {
      _secondsRemaining = 3;
    });

    _autoSendTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (mounted) {
        setState(() {
          _secondsRemaining--;
        });

        if (_secondsRemaining <= 0) {
          _cancelAutoSendTimer();
          if (_messageController.text.trim().isNotEmpty) {
            _sendMessage();
          }
        }
      } else {
        timer.cancel();
      }
    });
  }

  void _cancelAutoSendTimer() {
    _autoSendTimer?.cancel();
    _autoSendTimer = null;
    if (mounted) {
      setState(() {
        _secondsRemaining = 0;
      });
    }
  }

  void _toggleListening() async {
    if (!_speechAvailable) {
      _addSystemMessage('Speech recognition not available. Please check permissions.');
      return;
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) {
        setState(() {
          _isListening = false;
        });
      }
    } else {
      _cancelAutoSendTimer(); // Cancel any existing timer

      if (mounted) {
        setState(() {
          _isListening = true;
          _recognizedText = '';
        });
      }

      await _speech.listen(
        onResult: (result) {
          if (mounted) {
            final newText = result.recognizedWords;

            setState(() {
              _recognizedText = newText;
              _messageController.text = _recognizedText;

              // Check if user said "confirm" - auto send immediately
              if (_recognizedText.toLowerCase().contains('confirm')) {
                // Remove "confirm" from the message
                final cleanedText = _recognizedText
                    .replaceAll(RegExp(r'\bconfirm\b', caseSensitive: false), '')
                    .trim();
                _messageController.text = cleanedText;

                // Stop listening and send
                Future.delayed(const Duration(milliseconds: 300), () async {
                  await _speech.stop();
                  _cancelAutoSendTimer();

                  if (mounted && cleanedText.isNotEmpty) {
                    _sendMessage();
                  }
                });
              }
            });
          }
        },
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 3),
        partialResults: true,
        cancelOnError: true,
        listenMode: stt.ListenMode.confirmation,
      );
    }
  }

  void _connectWebSocket() {
    if (_isConnecting || _isConnected) return;

    if (mounted) {
      setState(() {
        _isConnecting = true;
      });
    }

    try {
      _channel = WebSocketChannel.connect(Uri.parse(WS_URL));

      _channel!.stream.listen(
            (message) {
          _handleWebSocketMessage(message);
        },
        onError: (error) {
          print('WebSocket error: $error');
          if (mounted) {
            setState(() {
              _isConnected = false;
              _isConnecting = false;
            });
          }
          _addSystemMessage('Connection error. Please check if the server is running.');
        },
        onDone: () {
          print('WebSocket connection closed');
          if (mounted) {
            setState(() {
              _isConnected = false;
              _isConnecting = false;
            });
          }
          _addSystemMessage('Disconnected from server.');
        },
      );

      if (mounted) {
        setState(() {
          _isConnected = true;
          _isConnecting = false;
        });
      }

      _addSystemMessage('Connected to AI scheduler! Try saying: "Schedule a meeting tomorrow at 2PM"');
    } catch (e) {
      print('Connection failed: $e');
      if (mounted) {
        setState(() {
          _isConnected = false;
          _isConnecting = false;
        });
      }
      _addSystemMessage('Failed to connect. Make sure the server is running on $WS_URL');
    }
  }

  void _handleWebSocketMessage(dynamic message) {
    try {
      final data = json.decode(message);

      if (data['role'] == 'assistant') {
        if (mounted) {
          setState(() {
            _messages.add(ChatMessage(
              text: data['content'] ?? '',
              isUser: false,
              timestamp: DateTime.now(),
            ));
          });
        }

        // Sync appointments with local calendar
        if (data['appointments'] != null) {
          _syncAppointments(data['appointments']);
        }

        // Play audio if available
        if (data['audio'] != null && data['audio'] is String && data['audio'].isNotEmpty) {
          _playAudioFromHex(data['audio']);
        }

        _scrollToBottom();
      } else if (data['role'] == 'error') {
        _addSystemMessage('Error: ${data['content'] ?? 'Unknown error'}');
      }
    } catch (e) {
      print('Error parsing message: $e');
      _addSystemMessage('Error processing response');
    }
  }

  Future<void> _playAudioFromHex(String hexString) async {
    try {
      print('🔊 Playing audio response...');

      final bytes = _hexToBytes(hexString);

      if (bytes.isEmpty) {
        print('⚠️ Audio data is empty');
        return;
      }

      await _audioPlayer.play(BytesSource(bytes));

      print('✅ Audio playback started');
    } catch (e) {
      print('⚠️ Error playing audio: $e');
    }
  }

  Uint8List _hexToBytes(String hex) {
    if (hex.isEmpty) return Uint8List(0);

    final result = Uint8List(hex.length ~/ 2);
    for (var i = 0; i < hex.length; i += 2) {
      final byte = hex.substring(i, i + 2);
      result[i ~/ 2] = int.parse(byte, radix: 16);
    }
    return result;
  }

  void _syncAppointments(List<dynamic> appointments) {
    for (var appt in appointments) {
      try {
        final title = appt['title'] as String? ?? '';
        final date = appt['date'] as String? ?? '';
        final time = appt['time'] as String? ?? '';
        final endTime = appt['endTime'] as String? ?? '';
        final description = appt['description'] as String? ?? '';

        if (title.isEmpty || date.isEmpty || time.isEmpty) {
          print('⚠️ Invalid appointment data: missing required fields');
          continue;
        }

        // Parse date and time
        final dateTime = DateTime.parse('$date $time');

        // Parse end time
        DateTime endDateTime;
        if (endTime.isNotEmpty) {
          endDateTime = DateTime.parse('$date $endTime');
        } else {
          endDateTime = dateTime.add(const Duration(hours: 1));
        }

        // Check if appointment already exists
        bool exists = false;
        for (var e in eventBox.values) {
          if (e.title == title &&
              e.start.year == dateTime.year &&
              e.start.month == dateTime.month &&
              e.start.day == dateTime.day &&
              e.start.hour == dateTime.hour &&
              e.start.minute == dateTime.minute) {
            exists = true;
            break;
          }
        }

        // Only add if it doesn't exist
        if (!exists) {
          final newEvent = Event(
            title,
            dateTime,
            endDateTime,
            '',
            description,
          );
          eventBox.add(newEvent);
          print('✅ Synced appointment: $title at $dateTime');
        }
      } catch (e) {
        print('Error syncing appointment: $e');
      }
    }
  }

  void _addSystemMessage(String text) {
    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(
          text: text,
          isUser: false,
          isSystem: true,
          timestamp: DateTime.now(),
        ));
      });
    }
    _scrollToBottom();
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    _cancelAutoSendTimer(); // Cancel timer when sending

    if (!_isConnected) {
      _addSystemMessage('Not connected to server. Attempting to reconnect...');
      _connectWebSocket();
      return;
    }

    if (mounted) {
      setState(() {
        _messages.add(ChatMessage(
          text: text,
          isUser: true,
          timestamp: DateTime.now(),
        ));
      });
    }

    // FIXED: Send JSON payload matching server expectations
    final payload = json.encode({
      'message': text,
      'device_name': _deviceName,
    });

    print('📤 Sending: $payload');
    _channel?.sink.add(payload);
    _messageController.clear();
    _scrollToBottom();
  }

  void _scrollToBottom() {
    Future.delayed(const Duration(milliseconds: 100), () {
      if (_scrollController.hasClients && mounted) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _cancelAutoSendTimer();
    _channel?.sink.close();
    _messageController.dispose();
    _scrollController.dispose();
    _audioPlayer.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('AI Scheduler'),
            if (_deviceName != 'unknown_device')
              Text(
                _deviceName,
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.normal),
              ),
          ],
        ),
        actions: [
          // Voice recognition indicator
          if (_isListening)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Row(
                  children: const [
                    Icon(Icons.mic, color: Colors.red, size: 20),
                    SizedBox(width: 4),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.red),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Audio indicator
          if (_isPlayingAudio)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Center(
                child: Row(
                  children: const [
                    Icon(Icons.volume_up, color: Colors.green, size: 20),
                    SizedBox(width: 4),
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.green),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Connection indicator
          IconButton(
            icon: Icon(
              _isConnected ? Icons.cloud_done : Icons.cloud_off,
              color: _isConnected ? Colors.green : Colors.red,
            ),
            onPressed: () {
              if (!_isConnected) {
                _connectWebSocket();
              }
            },
            tooltip: _isConnected ? 'Connected' : 'Disconnected',
          ),
        ],
      ),
      body: Column(
        children: [
          // Connection status banner
          if (!_isConnected)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.orange,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Not connected to server',
                    style: TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _connectWebSocket,
                    child: const Text(
                      'Reconnect',
                      style: TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),

          // Auto-send countdown banner
          if (_secondsRemaining > 0)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(8),
              color: Colors.blue,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.timer, size: 16, color: Colors.white),
                  const SizedBox(width: 8),
                  Text(
                    'Sending in $_secondsRemaining second${_secondsRemaining > 1 ? 's' : ''}... (say "confirm" to send now)',
                    style: const TextStyle(color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: _cancelAutoSendTimer,
                    child: const Text(
                      'Cancel',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
            ),

          // Messages list
          Expanded(
            child: _messages.isEmpty
                ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.calendar_month,
                    size: 64,
                    color: Colors.grey[400],
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Start chatting with AI',
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.grey[600],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Type or tap the mic button',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Try: "Schedule dentist tomorrow at 2PM"',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Say "confirm" to send immediately',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[500],
                      fontStyle: FontStyle.italic,
                    ),
                  ),
                ],
              ),
            )
                : ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: _messages.length,
              itemBuilder: (context, index) {
                return _buildMessageBubble(_messages[index]);
              },
            ),
          ),

          // Input area
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.1),
                  blurRadius: 4,
                  offset: const Offset(0, -2),
                ),
              ],
            ),
            padding: const EdgeInsets.all(8),
            child: SafeArea(
              child: Row(
                children: [
                  // Microphone button
                  IconButton(
                    icon: Icon(
                      _isListening ? Icons.mic : Icons.mic_none,
                      color: _isListening
                          ? Colors.red
                          : (_speechAvailable ? Colors.blue : Colors.grey),
                      size: 28,
                    ),
                    onPressed: _speechAvailable
                        ? _toggleListening
                        : () {
                      _addSystemMessage(
                          'Speech recognition not available. Please check permissions.');
                    },
                    tooltip: _isListening ? 'Stop listening' : 'Start voice input',
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: _isListening
                            ? 'Listening... (say "confirm" to send)'
                            : 'Schedule an appointment...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                      maxLines: null,
                      textInputAction: TextInputAction.send,
                      onSubmitted: (_) => _sendMessage(),
                      onChanged: (_) {
                        // Cancel auto-send timer if user manually edits text
                        if (_secondsRemaining > 0 && !_isListening) {
                          _cancelAutoSendTimer();
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  FloatingActionButton(
                    onPressed: _sendMessage,
                    mini: true,
                    child: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage message) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
        message.isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!message.isUser) ...[
            CircleAvatar(
              radius: 16,
              backgroundColor: message.isSystem ? Colors.grey : Colors.blue,
              child: Icon(
                message.isSystem ? Icons.info : Icons.smart_toy,
                size: 16,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: message.isUser
                    ? Colors.blue
                    : message.isSystem
                    ? Colors.grey[300]
                    : Colors.grey[200],
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message.text,
                    style: TextStyle(
                      color: message.isUser ? Colors.white : Colors.black87,
                      fontSize: 15,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    DateFormat('HH:mm').format(message.timestamp),
                    style: TextStyle(
                      color:
                      message.isUser ? Colors.white70 : Colors.grey[600],
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (message.isUser) ...[
            const SizedBox(width: 8),
            const CircleAvatar(
              radius: 16,
              backgroundColor: Colors.blue,
              child: Icon(
                Icons.person,
                size: 16,
                color: Colors.white,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class ChatMessage {
  final String text;
  final bool isUser;
  final bool isSystem;
  final DateTime timestamp;

  ChatMessage({
    required this.text,
    required this.isUser,
    this.isSystem = false,
    required this.timestamp,
  });
}