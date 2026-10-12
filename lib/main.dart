import 'package:flutter/material.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:table_calendar/table_calendar.dart';
import 'package:path_provider/path_provider.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'chat.dart'; // Import the chat screen

part 'main.g.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final dir = await getApplicationDocumentsDirectory();
  await Hive.initFlutter(dir.path);
  Hive.registerAdapter(EventAdapter());
  await Hive.openBox<Event>('events');

  // Initialize timezone for zonedSchedule
  tz.initializeTimeZones();

  runApp(SmartCalendarApp());
}

class SmartCalendarApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SmartCalendar',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      darkTheme: ThemeData.dark().copyWith(
        useMaterial3: true,
      ),
      home: SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class SplashScreen extends StatefulWidget {
  @override
  _SplashScreenState createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(seconds: 2), () {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => MainScreen()),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.calendar_month,
              size: 80,
              color: Colors.blue,
            ),
            const SizedBox(height: 16),
            const Text(
              '🗓 SmartCalendar',
              style: TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            const Text(
              'AI-Powered Scheduling',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  DateTime _selectedDay = DateTime.now();
  late Box<Event> eventBox;
  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
  FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    eventBox = Hive.box<Event>('events');

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidSettings);
    flutterLocalNotificationsPlugin.initialize(initSettings);
  }

  void _scheduleNotification(Event event) async {
    final scheduledTime = event.start.subtract(const Duration(minutes: 10));

    final androidDetails = AndroidNotificationDetails(
      'reminder_channel',
      'Event Reminders',
      channelDescription: 'Reminders for SmartCalendar events',
      importance: Importance.max,
      priority: Priority.high,
    );
    final details = NotificationDetails(android: androidDetails);

    await flutterLocalNotificationsPlugin.zonedSchedule(
      event.hashCode,
      'Reminder: ${event.title}',
      'Starts at ${DateFormat('hh:mm a').format(event.start)}',
      tz.TZDateTime.from(scheduledTime, tz.local),
      details,
      androidAllowWhileIdle: true,
      uiLocalNotificationDateInterpretation:
      UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
  }

  List<Event> _getEventsForDay(DateTime day) {
    return eventBox.values.where((e) => isSameDay(e.start, day)).toList();
  }

  void _showDeleteAllDialog() {
    final totalEvents = eventBox.length;

    if (totalEvents == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No events to delete'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: const [
            Icon(Icons.warning, color: Colors.red),
            SizedBox(width: 8),
            Text('Delete All Events?'),
          ],
        ),
        content: Text(
          'Are you sure you want to delete all $totalEvents event${totalEvents > 1 ? 's' : ''}? This action cannot be undone.',
          style: const TextStyle(fontSize: 16),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
            ),
            onPressed: () async {
              // Close dialog first
              Navigator.pop(context);

              // Delete all events
              await eventBox.clear();

              // Cancel all notifications
              await flutterLocalNotificationsPlugin.cancelAll();

              // Force UI refresh
              if (mounted) {
                setState(() {
                  // This will trigger a complete rebuild
                });
              }

              // Show success message
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Deleted $totalEvents event${totalEvents > 1 ? 's' : ''}'),
                    backgroundColor: Colors.green,
                    duration: const Duration(seconds: 2),
                  ),
                );
              }
            },
            child: const Text('Delete All'),
          ),
        ],
      ),
    );
  }

  void _showAddEventDialog() {
    final _formKey = GlobalKey<FormState>();
    String title = '';
    String location = '';
    String notes = '';
    DateTime start = DateTime.now();
    DateTime end = DateTime.now().add(const Duration(hours: 1));

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add Event'),
        content: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Title'),
                  validator: (val) =>
                  val == null || val.isEmpty ? 'Enter title' : null,
                  onChanged: (val) => title = val,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Location'),
                  onChanged: (val) => location = val,
                ),
                TextFormField(
                  decoration: const InputDecoration(labelText: 'Notes / Link'),
                  onChanged: (val) => notes = val,
                ),
                const SizedBox(height: 10),
                ElevatedButton.icon(
                  onPressed: () async {
                    final pickedDate = await showDatePicker(
                      context: context,
                      initialDate: start,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (pickedDate != null) {
                      final pickedTime = await showTimePicker(
                        context: context,
                        initialTime: TimeOfDay.fromDateTime(start),
                      );
                      if (pickedTime != null) {
                        setState(() {
                          start = DateTime(
                            pickedDate.year,
                            pickedDate.month,
                            pickedDate.day,
                            pickedTime.hour,
                            pickedTime.minute,
                          );
                          end = start.add(const Duration(hours: 1));
                        });
                      }
                    }
                  },
                  icon: const Icon(Icons.access_time),
                  label: const Text('Pick Date & Time'),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (_formKey.currentState!.validate()) {
                final newEvent = Event(title, start, end, location, notes);
                eventBox.add(newEvent);
                _scheduleNotification(newEvent);
                setState(() {});
                Navigator.pop(context);
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
  }

  Widget _buildEventList(DateTime day) {
    final events = _getEventsForDay(day);
    if (events.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.event_busy,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'No events today',
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tap + to add or use AI chat',
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }
    return ListView.builder(
      itemCount: events.length,
      itemBuilder: (_, index) {
        final event = events[index];
        final duration = event.end.difference(event.start);
        final durationText = duration.inHours > 0
            ? '${duration.inHours}h ${duration.inMinutes % 60}m'
            : '${duration.inMinutes}m';

        return Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          elevation: 2,
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.blue,
              child: Icon(
                Icons.event,
                color: Colors.white,
                size: 20,
              ),
            ),
            title: Text(
              event.title,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Row(
                  children: [
                    Icon(Icons.access_time, size: 14, color: Colors.grey[600]),
                    const SizedBox(width: 4),
                    Text(
                      '${DateFormat('hh:mm a').format(event.start)} - ${DateFormat('hh:mm a').format(event.end)}',
                      style: TextStyle(color: Colors.grey[700]),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '($durationText)',
                      style: TextStyle(color: Colors.grey[600], fontSize: 12),
                    ),
                  ],
                ),
                if (event.location.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Text(
                        event.location,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                    ],
                  ),
                ],
                if (event.notes.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.notes, size: 14, color: Colors.grey[600]),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          event.notes,
                          style: TextStyle(color: Colors.grey[700]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            trailing: IconButton(
              icon: const Icon(Icons.delete, color: Colors.redAccent),
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Delete Event?'),
                    content: Text('Are you sure you want to delete "${event.title}"?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Cancel'),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () {
                          event.delete();
                          setState(() {});
                          Navigator.pop(context);
                        },
                        child: const Text('Delete'),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final todayEvents = _getEventsForDay(DateTime.now());
    final totalEvents = eventBox.length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('SmartCalendar'),
        actions: [
          // Delete All Button
          if (totalEvents > 0)
            IconButton(
              icon: const Icon(Icons.delete_sweep),
              tooltip: 'Delete All Events',
              onPressed: _showDeleteAllDialog,
            ),
          // AI Chat Button
          IconButton(
            icon: const Icon(Icons.chat_bubble),
            tooltip: 'AI Scheduler',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              );
            },
          ),
          // Today's event count badge
          if (todayEvents.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${todayEvents.length} today',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          TableCalendar(
            firstDay: DateTime.utc(2020),
            lastDay: DateTime.utc(2100),
            focusedDay: _selectedDay,
            selectedDayPredicate: (day) => isSameDay(_selectedDay, day),
            onDaySelected: (selected, focused) {
              setState(() {
                _selectedDay = selected;
              });
            },
            calendarStyle: const CalendarStyle(
              todayDecoration: BoxDecoration(
                color: Colors.blue,
                shape: BoxShape.circle,
              ),
              selectedDecoration: BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            headerStyle: const HeaderStyle(
              formatButtonVisible: false,
              titleCentered: true,
            ),
            // Show dots for days with events
            eventLoader: (day) {
              return _getEventsForDay(day);
            },
          ),
          const Divider(height: 1),
          // Selected date header
          Container(
            padding: const EdgeInsets.all(12),
            color: Colors.grey[100],
            child: Row(
              children: [
                Icon(Icons.calendar_today, size: 20, color: Colors.grey[700]),
                const SizedBox(width: 8),
                Text(
                  DateFormat('EEEE, MMMM d, y').format(_selectedDay),
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.grey[800],
                  ),
                ),
                const Spacer(),
                if (_getEventsForDay(_selectedDay).isNotEmpty)
                  Text(
                    '${_getEventsForDay(_selectedDay).length} event${_getEventsForDay(_selectedDay).length > 1 ? 's' : ''}',
                    style: TextStyle(
                      fontSize: 14,
                      color: Colors.grey[600],
                    ),
                  ),
              ],
            ),
          ),
          Expanded(child: _buildEventList(_selectedDay)),
        ],
      ),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          // AI Chat FAB
          FloatingActionButton(
            heroTag: 'ai_chat',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const ChatScreen()),
              );
            },
            child: const Icon(Icons.smart_toy),
            backgroundColor: Colors.purple,
            tooltip: 'AI Scheduler',
          ),
          const SizedBox(height: 12),
          // Manual Add FAB
          FloatingActionButton(
            heroTag: 'add_manual',
            onPressed: _showAddEventDialog,
            child: const Icon(Icons.add),
            tooltip: 'Add Event',
          ),
        ],
      ),
    );
  }
}

// 🧠 Event Model
@HiveType(typeId: 0)
class Event extends HiveObject {
  @HiveField(0)
  String title;

  @HiveField(1)
  DateTime start;

  @HiveField(2)
  DateTime end;

  @HiveField(3)
  String location;

  @HiveField(4)
  String notes;

  Event(this.title, this.start, this.end, this.location, this.notes);
}