import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:hive_flutter/hive_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  Hive.registerAdapter(LeaderboardEntryAdapter());
  await Hive.openBox<LeaderboardEntry>('leaderboard');
  runApp(const QuizApp());
}

class LeaderboardEntry extends HiveObject {
  final String category;
  final int score;
  final DateTime date;

  LeaderboardEntry({
    required this.category,
    required this.score,
    required this.date,
  });

  LeaderboardEntry.fromMap(Map<String, dynamic> map)
      : category = map['category'],
        score = map['score'],
        date = DateTime.parse(map['date']);

  Map<String, dynamic> toMap() {
    return {
      'category': category,
      'score': score,
      'date': date.toIso8601String(),
    };
  }
}

class LeaderboardEntryAdapter extends TypeAdapter<LeaderboardEntry> {
  @override
  final int typeId = 0;

  @override
  LeaderboardEntry read(BinaryReader reader) {
    return LeaderboardEntry(
      category: reader.readString(),
      score: reader.readInt(),
      date: DateTime.fromMillisecondsSinceEpoch(reader.readInt()),
    );
  }

  @override
  void write(BinaryWriter writer, LeaderboardEntry obj) {
    writer.writeString(obj.category);
    writer.writeInt(obj.score);
    writer.writeInt(obj.date.millisecondsSinceEpoch);
  }
}

class QuizApp extends StatelessWidget {
  const QuizApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Customizable Quiz App',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const QuizSetupScreen(),
    );
  }
}

class QuizSetupScreen extends StatefulWidget {
  const QuizSetupScreen({super.key});

  @override
  _QuizSetupScreenState createState() => _QuizSetupScreenState();
}

class _QuizSetupScreenState extends State<QuizSetupScreen> {
  int _numberOfQuestions = 5;
  String? _selectedCategory;
  String? _selectedCategoryName;
  String? _selectedDifficulty;
  String? _selectedType;
  List<dynamic>? _categories;

  @override
  void initState() {
    super.initState();
    _fetchCategories();
  }

  Future<void> _fetchCategories() async {
    final response =
        await http.get(Uri.parse('https://opentdb.com/api_category.php'));
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      setState(() {
        _categories = data['trivia_categories'];
      });
    }
  }

  void _showErrorMessage(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz Setup')),
      body: _categories == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  DropdownButtonFormField<int>(
                    decoration:
                        const InputDecoration(labelText: 'Number of Questions'),
                    value: _numberOfQuestions,
                    items: [5, 10, 15]
                        .map((e) =>
                            DropdownMenuItem(value: e, child: Text('$e')))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _numberOfQuestions = value!),
                  ),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Category'),
                    items: _categories!
                        .map((category) => DropdownMenuItem(
                              value: jsonEncode({
                                'id': category['id'].toString(),
                                'name': category['name']
                              }),
                              child: Text(category['name']),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value != null) {
                        final selected = jsonDecode(value);
                        setState(() {
                          _selectedCategory = selected['id'];
                          _selectedCategoryName = selected['name'];
                        });
                      }
                    },
                  ),
                  DropdownButtonFormField<String>(
                    decoration: const InputDecoration(labelText: 'Difficulty'),
                    items: ['easy', 'medium', 'hard']
                        .map((difficulty) => DropdownMenuItem(
                            value: difficulty, child: Text(difficulty)))
                        .toList(),
                    onChanged: (value) =>
                        setState(() => _selectedDifficulty = value),
                  ),
                  DropdownButtonFormField<String>(
                    decoration:
                        const InputDecoration(labelText: 'Question Type'),
                    items: ['multiple', 'boolean']
                        .map((type) =>
                            DropdownMenuItem(value: type, child: Text(type)))
                        .toList(),
                    onChanged: (value) => setState(() => _selectedType = value),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: () {
                      if (_selectedCategoryName != null) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => QuizScreen(
                              numberOfQuestions: _numberOfQuestions,
                              category: _selectedCategory,
                              categoryName: _selectedCategoryName,
                              difficulty: _selectedDifficulty,
                              type: _selectedType,
                            ),
                          ),
                        );
                      } else {
                        _showErrorMessage(
                            'Please select valid options for the quiz setup.');
                      }
                    },
                    child: const Text('Start Quiz'),
                  ),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => const LeaderboardScreen(),
                        ),
                      );
                    },
                    child: const Text('View Leaderboard'),
                  ),
                ],
              ),
            ),
    );
  }
}

class QuizScreen extends StatefulWidget {
  final int numberOfQuestions;
  final String? category;
  final String? categoryName;
  final String? difficulty;
  final String? type;

  const QuizScreen({
    required this.numberOfQuestions,
    this.category,
    this.categoryName,
    this.difficulty,
    this.type,
    super.key,
  });

  @override
  _QuizScreenState createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  List<dynamic>? _questions;
  int _currentIndex = 0;
  int _score = 0;
  int _timeRemaining = 15;
  Timer? _timer;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchQuestions();
  }

  Future<void> _fetchQuestions() async {
    final url = Uri.parse(
        'https://opentdb.com/api.php?amount=${widget.numberOfQuestions}'
        '&category=${widget.category ?? ''}'
        '&difficulty=${widget.difficulty ?? ''}'
        '&type=${widget.type ?? ''}');
    final response = await http.get(url);
    if (response.statusCode == 200) {
      final data = json.decode(response.body);
      if (data['results'] != null && data['results'].isNotEmpty) {
        setState(() {
          _questions = data['results'];
          _isLoading = false;
          _startTimer();
        });
      } else {
        setState(() {
          _isLoading = false;
        });
        _showErrorMessage('No questions available. Please try again.');
      }
    } else {
      setState(() {
        _isLoading = false;
      });
      _showErrorMessage(
          'Failed to fetch questions. Please check your connection.');
    }
  }

  void _startTimer() {
    _timer?.cancel();
    setState(() => _timeRemaining = 15);
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_timeRemaining > 0) {
        setState(() => _timeRemaining--);
      } else {
        _nextQuestion(false);
      }
    });
  }

  void _nextQuestion(bool answeredCorrectly) {
    if (answeredCorrectly) _score++;
    if (_currentIndex + 1 < _questions!.length) {
      setState(() {
        _currentIndex++;
        _startTimer();
      });
    } else {
      _endQuiz();
    }
  }

  void _endQuiz() async {
    _timer?.cancel();
    final box = Hive.box<LeaderboardEntry>('leaderboard');
    final entry = LeaderboardEntry(
      category: widget.categoryName ?? 'General',
      score: _score,
      date: DateTime.now(),
    );
    await box.add(entry);

    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (context) => QuizSummary(
          score: _score,
          totalQuestions: _questions!.length,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _showErrorMessage(String message) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('OK'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final question = _questions![_currentIndex];
    final answers = [
      ...question['incorrect_answers'],
      question['correct_answer']
    ]..shuffle();

    return Scaffold(
      appBar: AppBar(
        title: Text('Question ${_currentIndex + 1}/${_questions!.length}'),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(
              value: (_currentIndex + 1) / _questions!.length),
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              question['question'],
              style: const TextStyle(fontSize: 18),
            ),
          ),
          Text('Time Remaining: $_timeRemaining'),
          ...answers.map((answer) {
            return ElevatedButton(
              onPressed: () =>
                  _nextQuestion(answer == question['correct_answer']),
              child: Text(answer),
            );
          }),
        ],
      ),
    );
  }
}

class QuizSummary extends StatelessWidget {
  final int score;
  final int totalQuestions;

  const QuizSummary({
    required this.score,
    required this.totalQuestions,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Quiz Summary')),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text('Score: $score/$totalQuestions'),
            ElevatedButton(
              onPressed: () {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(
                      builder: (context) => const QuizSetupScreen()),
                  (route) => false,
                );
              },
              child: const Text('Retake Quiz'),
            ),
          ],
        ),
      ),
    );
  }
}

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final box = Hive.box<LeaderboardEntry>('leaderboard');
    final entries = box.values.toList().cast<LeaderboardEntry>()
      ..sort((a, b) => b.score.compareTo(a.score));

    return Scaffold(
      appBar: AppBar(title: const Text('Leaderboard')),
      body: entries.isEmpty
          ? const Center(child: Text('No scores yet!'))
          : ListView.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) {
                final entry = entries[index];
                return ListTile(
                  title: Text(
                    'Category: ${entry.category}\nScore: ${entry.score}',
                    style: const TextStyle(fontSize: 16),
                  ),
                  subtitle: Text(
                    'Date: ${entry.date.toLocal()}'.split(' ')[0],
                    style: const TextStyle(color: Colors.grey),
                  ),
                  trailing: Text(
                    'Rank: ${index + 1}',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                );
              },
            ),
    );
  }
}
