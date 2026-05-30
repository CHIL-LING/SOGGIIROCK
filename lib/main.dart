import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('abbreviations');
  await Hive.openBox('studyRecords');
  await Hive.openBox('sentences');
  await Hive.openBox('reminders');
  runApp(const SoggiApp());
}

const Color kBlue        = Color(0xFF1A6CF6);
const Color kBlueSky     = Color(0xFF398FCC);
const Color kBlueLight   = Color(0xFFE8F0FE);
const Color kBlueDark    = Color(0xFF0F4AB3);
const Color kPurple      = Color(0xFF6a8fa9);
const Color kPurpleLight = Color(0xFFF3EFFE);
const Color kTimerBg     = Color(0xFFBED3F7);

String encodeWord(String raw) => raw.replaceAll(' ', '*');
String decodeWordForSearch(String word) => word.replaceAll('*', '');

bool _hasFinalConsonant(String char) {
  if (char.isEmpty) return false;
  final code = char.codeUnitAt(0);
  if (code < 0xAC00 || code > 0xD7A3) return false;
  return (code - 0xAC00) % 28 != 0;
}

class AbbreviationModel {
  final String id, word;
  final List<String> initial, medial, final_;
  final bool isComposite, isConcurrent, isAttached, isFavorite;

  AbbreviationModel({
    required this.id, required this.word,
    this.initial = const [], this.medial = const [], this.final_ = const [],
    this.isComposite = false, this.isConcurrent = false,
    this.isAttached = false, this.isFavorite = false,
  });

  String get searchKey => decodeWordForSearch(word);
  String get displayWord => word.replaceAll('*', ' ');

  Map<String, dynamic> toMap() => {
    'id': id, 'word': word, 'initial': initial, 'medial': medial, 'final_': final_,
    'isComposite': isComposite, 'isConcurrent': isConcurrent,
    'isAttached': isAttached, 'isFavorite': isFavorite,
  };

  factory AbbreviationModel.fromMap(Map m) => AbbreviationModel(
    id: m['id'] as String, word: m['word'] as String,
    initial: List<String>.from(m['initial'] ?? []),
    medial: List<String>.from(m['medial'] ?? []),
    final_: List<String>.from(m['final_'] ?? []),
    isComposite: m['isComposite'] as bool? ?? false,
    isConcurrent: m['isConcurrent'] as bool? ?? false,
    isAttached: m['isAttached'] as bool? ?? false,
    isFavorite: m['isFavorite'] as bool? ?? false,
  );

  AbbreviationModel copyWith({
    String? word, List<String>? initial, List<String>? medial, List<String>? final_,
    bool? isComposite, bool? isConcurrent, bool? isAttached, bool? isFavorite,
  }) => AbbreviationModel(
    id: id, word: word ?? this.word, initial: initial ?? this.initial,
    medial: medial ?? this.medial, final_: final_ ?? this.final_,
    isComposite: isComposite ?? this.isComposite, isConcurrent: isConcurrent ?? this.isConcurrent,
    isAttached: isAttached ?? this.isAttached, isFavorite: isFavorite ?? this.isFavorite,
  );

  String get strokeDisplay {
    final parts = <String>[];
    if (initial.isNotEmpty) parts.add(initial.join('+'));
    if (medial.isNotEmpty) parts.add(medial.join('+'));
    if (final_.isNotEmpty) parts.add(final_.map((v) => v == 'ㅋ' ? '(ㅋ)' : v).join('+'));
    return parts.join(' / ');
  }

  List<String> get typeLabels {
    final l = <String>[];
    if (isConcurrent) l.add('동시');
    if (isComposite) l.add('합성');
    if (isAttached) l.add('붙여쓰기');
    return l;
  }

  Color get typeColor {
    if (isConcurrent) return kPurple;
    if (isComposite) return kBlueSky;
    return kBlue;
  }
}

class StudyRecordModel {
  final String date, memo;
  final int? studyHours, studyMinutes, speechChars, essayChars, wpm;
  StudyRecordModel({required this.date, this.studyHours, this.studyMinutes,
    this.speechChars, this.essayChars, this.wpm, this.memo = ''});
  bool get hasData => studyHours != null || studyMinutes != null ||
      speechChars != null || essayChars != null || wpm != null || memo.isNotEmpty;
  Map<String, dynamic> toMap() => {'date': date, 'studyHours': studyHours,
    'studyMinutes': studyMinutes, 'speechChars': speechChars, 'essayChars': essayChars,
    'wpm': wpm, 'memo': memo};
  factory StudyRecordModel.fromMap(Map m) => StudyRecordModel(
    date: m['date'] as String, studyHours: m['studyHours'] as int?,
    studyMinutes: m['studyMinutes'] as int?, speechChars: m['speechChars'] as int?,
    essayChars: m['essayChars'] as int?, wpm: m['wpm'] as int?,
    memo: m['memo'] as String? ?? '');
}

class SavedSentenceModel {
  final String id, text, createdAt;
  SavedSentenceModel({required this.id, required this.text, required this.createdAt});
  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'createdAt': createdAt};
  factory SavedSentenceModel.fromMap(Map m) => SavedSentenceModel(
    id: m['id'] as String, text: m['text'] as String, createdAt: m['createdAt'] as String);
}

class ReminderModel {
  final String id, type, target, date;
  final int intervalDays;
  final bool repeat;
  bool active;
  ReminderModel({required this.id, required this.type, required this.target,
    required this.date, this.intervalDays = 1, this.repeat = false, this.active = true});
  Map<String, dynamic> toMap() => {'id': id, 'type': type, 'target': target, 'date': date,
    'intervalDays': intervalDays, 'repeat': repeat, 'active': active};
  factory ReminderModel.fromMap(Map m) => ReminderModel(
    id: m['id'] as String, type: m['type'] as String, target: m['target'] as String,
    date: m['date'] as String, intervalDays: m['intervalDays'] as int? ?? 1,
    repeat: m['repeat'] as bool? ?? false, active: m['active'] as bool? ?? true);
}

class Store {
  static Box get _ab => Hive.box('abbreviations');
  static Box get _re => Hive.box('studyRecords');
  static Box get _se => Hive.box('sentences');
  static Box get _rm => Hive.box('reminders');

  static List<AbbreviationModel> getAbbreviations() =>
      _ab.values.map((e) => AbbreviationModel.fromMap(Map.from(e as Map))).toList();
  static Future<void> saveAbbreviation(AbbreviationModel a) => _ab.put(a.id, a.toMap());
  static Future<void> deleteAbbreviation(String id) => _ab.delete(id);
  static bool existsWord(String word, {String? excludeId}) {
    final key = decodeWordForSearch(word);
    return getAbbreviations().any((a) => decodeWordForSearch(a.word) == key && a.id != excludeId);
  }

  static List<StudyRecordModel> getRecords() =>
      _re.values.map((e) => StudyRecordModel.fromMap(Map.from(e as Map))).toList();
  static List<StudyRecordModel> getRecordsWithData() => getRecords().where((r) => r.hasData).toList();
  static StudyRecordModel? getRecord(String date) {
    try { return getRecords().firstWhere((r) => r.date == date); } catch (_) { return null; }
  }
  static Future<void> saveRecord(StudyRecordModel r) => _re.put(r.date, r.toMap());
  static Future<void> deleteRecord(String date) => _re.delete(date);

  static List<SavedSentenceModel> getSentences() =>
      _se.values.map((e) => SavedSentenceModel.fromMap(Map.from(e as Map))).toList();
  static Future<void> saveSentence(SavedSentenceModel s) => _se.put(s.id, s.toMap());
  static Future<void> deleteSentence(String id) => _se.delete(id);

  static List<ReminderModel> getReminders() =>
      _rm.values.map((e) => ReminderModel.fromMap(Map.from(e as Map))).toList();
  static Future<void> saveReminder(ReminderModel r) => _rm.put(r.id, r.toMap());
  static Future<void> deleteReminder(String id) => _rm.delete(id);
  static Future<void> toggleReminder(String id) async {
    final r = getReminders().firstWhere((e) => e.id == id);
    r.active = !r.active;
    await saveReminder(r);
  }
  static ReminderModel? findReminder(String target) {
    try { return getReminders().firstWhere((r) => r.target == target); } catch (_) { return null; }
  }
}

class StudyTimer extends ChangeNotifier {
  static final StudyTimer _instance = StudyTimer._();
  static StudyTimer get instance => _instance;
  StudyTimer._();
  Timer? _timer;
  int _seconds = 0;
  bool _running = false;
  bool get running => _running;
  int get hours => _seconds ~/ 3600;
  int get minutes => (_seconds % 3600) ~/ 60;
  String get display {
    final h = _seconds ~/ 3600, m = (_seconds % 3600) ~/ 60, s = _seconds % 60;
    if (h > 0) return '${h.toString().padLeft(2,'0')}:${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
    return '${m.toString().padLeft(2,'0')}:${s.toString().padLeft(2,'0')}';
  }
  void start() {
    if (_running) return;
    _running = true;
    _timer = Timer.periodic(const Duration(seconds: 1), (_) { _seconds++; notifyListeners(); });
    notifyListeners();
  }
  void pause() { _running = false; _timer?.cancel(); notifyListeners(); }
  void reset() { _running = false; _timer?.cancel(); _seconds = 0; notifyListeners(); }
  String get todayKey {
    final now = DateTime.now();
    final base = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
    return '${base.year}-${base.month.toString().padLeft(2,'0')}-${base.day.toString().padLeft(2,'0')}';
  }
  Future<void> saveToRecord() async {
    if (_seconds == 0) return;
    final key = todayKey;
    final ex = Store.getRecord(key);
    await Store.saveRecord(StudyRecordModel(
      date: key, studyHours: hours, studyMinutes: minutes,
      speechChars: ex?.speechChars, essayChars: ex?.essayChars,
      wpm: ex?.wpm, memo: ex?.memo ?? ''));
  }
}

// ── 문장 분석 (으(므)로 / 와(과) 실시간 치환) ──────────────────────────
class _Span {
  final String text, type;
  final AbbreviationModel? abbr;
  final String? resolvedText;
  const _Span({required this.text, required this.type, this.abbr, this.resolvedText});
}

List<_Span> analyzeText(String raw, List<AbbreviationModel> abbrevs) {
  final normalized = raw.replaceAll(' ', '*');
  List<_Span> parts = [_Span(text: normalized, type: 'normal')];
  final sorted = [...abbrevs]..sort((a, b) => b.word.length.compareTo(a.word.length));

  for (final a in sorted) {
    final next = <_Span>[];
    final isFlexible = a.word.contains('으(므)로') || a.word.contains('와(과)');

    if (isFlexible) {
      final variants = <String>{};
      if (a.word.contains('으(므)로')) {
        variants.add(a.word.replaceAll('으(므)로', '므로'));
        variants.add(a.word.replaceAll('으(므)로', '으로'));
      }
      if (a.word.contains('와(과)')) {
        variants.add(a.word.replaceAll('와(과)', '과'));
        variants.add(a.word.replaceAll('와(과)', '와'));
      }
      variants.add(a.word);
      final sortedV = variants.toList()..sort((x, y) => y.length.compareTo(x.length));

      for (final p in parts) {
        if (p.type != 'normal') { next.add(p); continue; }
        bool matched = false;
        for (final variant in sortedV) {
          if (p.text.contains(variant)) {
            final segs = p.text.split(variant);
            for (int i = 0; i < segs.length; i++) {
              if (segs[i].isNotEmpty) next.add(_Span(text: segs[i], type: 'normal'));
              if (i < segs.length - 1) {
                String type = 'abbr';
                if (a.isConcurrent) type = 'concurrent';
                else if (a.isComposite) type = 'composite';
                next.add(_Span(text: variant, type: type, abbr: a, resolvedText: variant));
              }
            }
            matched = true; break;
          }
        }
        if (!matched) next.add(p);
      }
    } else {
      for (final p in parts) {
        if (p.type != 'normal') { next.add(p); continue; }
        final segs = p.text.split(a.word);
        for (int i = 0; i < segs.length; i++) {
          if (segs[i].isNotEmpty) next.add(_Span(text: segs[i], type: 'normal'));
          if (i < segs.length - 1) {
            String type = 'abbr';
            if (a.isConcurrent) type = 'concurrent';
            else if (a.isComposite) type = 'composite';
            next.add(_Span(text: a.word, type: type, abbr: a, resolvedText: a.word));
          }
        }
      }
    }
    parts = next;
  }

  return parts.map((p) {
    if (p.type == 'normal') return _Span(text: p.text.replaceAll('*', ' '), type: 'normal');
    return _Span(text: p.text, type: p.type, abbr: p.abbr,
        resolvedText: (p.resolvedText ?? p.text).replaceAll('*', ' '));
  }).toList();
}

// ── 검색 정렬: 유사도 높은 순 → 가나다순 ──────────────────────────────
int _similarity(String word, String query) {
  if (word == query) return 100;
  if (word.startsWith(query)) return 80;
  if (word.contains(query)) return 60;
  return 0;
}

List<AbbreviationModel> sortedSearchResults(List<AbbreviationModel> all, String query) {
  if (query.isEmpty) return all;
  final qNorm = query.replaceAll(' ', '').replaceAll('*', '');
  final filtered = all.where((a) {
    final wNorm = a.searchKey.replaceAll(' ', '');
    return wNorm.contains(qNorm) || a.word.contains(query) || a.searchKey.contains(query);
  }).toList();
  filtered.sort((a, b) {
    final sa = _similarity(a.searchKey, qNorm);
    final sb = _similarity(b.searchKey, qNorm);
    if (sa != sb) return sb.compareTo(sa);
    return a.searchKey.compareTo(b.searchKey);
  });
  return filtered;
}

// ── 앱 ────────────────────────────────────────────────────────────────
class SoggiApp extends StatelessWidget {
  const SoggiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '속끼록', debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kBlue), useMaterial3: true),
    home: const SplashScreen());
}

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const MainShell()));
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBlue,
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('⌨️', style: TextStyle(fontSize: 52)),
      const SizedBox(height: 12),
      const Text('속끼록', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: Colors.white, letterSpacing: 2)),
      const SizedBox(height: 6),
      Text('약어 학습 · 기록 · 복습', style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.75))),
      const SizedBox(height: 40),
      SizedBox(width: 40, child: LinearProgressIndicator(
          backgroundColor: Colors.white.withOpacity(0.3), color: Colors.white,
          borderRadius: BorderRadius.circular(4))),
    ])));
}

// ── 메인 쉘 (IndexedStack으로 탭 상태 유지) ─────────────────────────
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override State<MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<MainShell> {
  int _idx = 0;
  final _screens = const [
    HomeScreen(), SentenceAnalyzerScreen(), SearchScreen(),
    SentenceRegisterScreen(), RemindersScreen(),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: IndexedStack(index: _idx, children: _screens),
    bottomNavigationBar: SafeArea(child: Container(
      decoration: const BoxDecoration(border: Border(top: BorderSide(color: Color(0xFFF0F0F0)))),
      child: BottomNavigationBar(
        currentIndex: _idx, onTap: (i) => setState(() => _idx = i),
        selectedItemColor: kBlue, unselectedItemColor: Colors.grey,
        showUnselectedLabels: true, type: BottomNavigationBarType.fixed,
        selectedFontSize: 10, unselectedFontSize: 10,
        selectedIconTheme: const IconThemeData(size: 24),
        unselectedIconTheme: const IconThemeData(size: 24),
        items: const [
          BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.home_rounded)), label: '홈'),
          BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.search_rounded)), label: '약어확인'),
          BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.menu_book_rounded)), label: '약어검색'),
          BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.bookmark_rounded)), label: '문장등록'),
          BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.notifications_rounded)), label: '리마인드'),
        ]))));
}

// ── 홈 ────────────────────────────────────────────────────────────────
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  late DateTime _month;
  String? _selected;
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = _todayKey();
    StudyTimer.instance.addListener(_onTick);
  }
  @override void dispose() { StudyTimer.instance.removeListener(_onTick); super.dispose(); }
  void _onTick() { if (mounted) setState(() {}); }
  String _todayKey() {
    final now = DateTime.now();
    final base = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
    return '${base.year}-${base.month.toString().padLeft(2,'0')}-${base.day.toString().padLeft(2,'0')}';
  }
  String _fmt(DateTime d) => '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('studyRecords').listenable(),
      builder: (context, box, _) {
        final record = _selected != null ? Store.getRecord(_selected!) : null;
        final hasData = record?.hasData ?? false;
        final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
        final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;
        final markedDates = Store.getRecordsWithData().map((r) => r.date).toSet();
        final timer = StudyTimer.instance;
        final calW = (MediaQuery.of(context).size.width * 0.85).clamp(0.0, 340.0);
        return Scaffold(backgroundColor: Colors.white,
          body: SafeArea(child: SingleChildScrollView(child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('${_month.year}년 ${_month.month}월',
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
                  const Text('속끼록', style: TextStyle(fontSize: 12, color: Colors.grey)),
                ]),
                Row(children: [
                  IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month - 1)),
                      icon: const Icon(Icons.chevron_left, color: kBlue, size: 22)),
                  IconButton(onPressed: () => setState(() => _month = DateTime(_month.year, _month.month + 1)),
                      icon: const Icon(Icons.chevron_right, color: kBlue, size: 22)),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GraphScreen())),
                    child: Container(width: 34, height: 34,
                      decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Icon(Icons.bar_chart_rounded, color: kBlue, size: 20)))),
                ]),
              ])),
            const SizedBox(height: 8),
            Center(child: SizedBox(width: calW, child: Column(children: [
              Row(children: ['일','월','화','수','목','금','토'].map((d) => Expanded(
                child: Center(child: Text(d, style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600))))).toList()),
              const SizedBox(height: 4),
              GridView.builder(
                shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 7, mainAxisSpacing: 5, crossAxisSpacing: 5, childAspectRatio: 1.1),
                itemCount: firstWeekday + daysInMonth,
                itemBuilder: (context, index) {
                  if (index < firstWeekday) return const SizedBox();
                  final day = index - firstWeekday + 1;
                  final key = _fmt(DateTime(_month.year, _month.month, day));
                  final marked = markedDates.contains(key);
                  final isSel = key == _selected;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = key),
                    child: Stack(alignment: Alignment.center, children: [
                      if (isSel) Container(decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(10))),
                      if (marked && !isSel) Container(width: 28, height: 28,
                        decoration: BoxDecoration(shape: BoxShape.circle,
                          boxShadow: [BoxShadow(color: kBlueSky.withOpacity(0.45), blurRadius: 8, spreadRadius: 4)],
                          color: kBlueSky.withOpacity(0.25))),
                      Text('$day', style: TextStyle(fontSize: 12,
                        fontWeight: isSel || marked ? FontWeight.w700 : FontWeight.w400,
                        color: isSel ? Colors.white : marked ? kBlueDark : Colors.black87)),
                    ]));
                }),
            ]))),
            const SizedBox(height: 12),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: kTimerBg, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.timer_rounded, color: kBlueDark, size: 26),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('오늘 공부 시간', style: TextStyle(fontSize: 11, color: kBlueDark)),
                    Text(timer.display, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: kBlueDark, letterSpacing: 2)),
                  ])),
                  Row(children: [
                    _TimerBtn(icon: timer.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      onTap: () async { if (timer.running) { timer.pause(); await timer.saveToRecord(); } else { timer.start(); } }),
                    const SizedBox(width: 8),
                    _TimerBtn(icon: Icons.stop_rounded,
                      onTap: () async { await timer.saveToRecord(); timer.reset(); }),
                  ]),
                ]))),
            const SizedBox(height: 10),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(16)),
                child: hasData
                  ? _RecordCard(record: record!,
                      onEdit: () => _showRecordDialog(context, existing: record),
                      onDelete: () => _confirmDeleteRecord(context, record.date))
                  : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_selected ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ElevatedButton(
                        onPressed: () => _showRecordDialog(context),
                        style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7)),
                        child: const Text('기록 추가', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700))),
                    ]))),
            const SizedBox(height: 16),
          ]))));
      });
  }

  void _showRecordDialog(BuildContext context, {StudyRecordModel? existing}) {
    final date = _selected!;
    int? hours = existing?.studyHours, minutes = existing?.studyMinutes;
    int? speech = existing?.speechChars, essay = existing?.essayChars;
    final wpmCtrl = TextEditingController(text: existing?.wpm?.toString() ?? '');
    final memoCtrl = TextEditingController(text: existing?.memo ?? '');
    final charOpts = [for (int c = 110; c <= 300; c += 10) c];
    final hourOpts = [for (int h = 0; h <= 12; h++) h];
    final minOpts = [0,5,10,15,20,25,30,35,40,45,50,55];

    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$date 기록', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _lbl('공부 시간'),
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(value: hours, hint: const Text('시간'),
              decoration: _inputDeco(null),
              items: hourOpts.map((h) => DropdownMenuItem(value: h, child: Text('$h시간'))).toList(),
              onChanged: (v) => setS(() => hours = v))),
            const SizedBox(width: 8),
            Expanded(child: DropdownButtonFormField<int>(value: minutes, hint: const Text('분'),
              decoration: _inputDeco(null),
              items: minOpts.map((m) => DropdownMenuItem(value: m, child: Text('$m분'))).toList(),
              onChanged: (v) => setS(() => minutes = v))),
          ]),
          const SizedBox(height: 12),
          _lbl('자수 · 타수'),
          Row(children: [
            Expanded(child: DropdownButtonFormField<int>(value: speech, hint: const Text('연설'),
              decoration: _inputDeco(null),
              items: charOpts.map((c) => DropdownMenuItem(value: c, child: Text('연$c'))).toList(),
              onChanged: (v) => setS(() => speech = v))),
            const SizedBox(width: 4),
            Expanded(child: DropdownButtonFormField<int>(value: essay, hint: const Text('논술'),
              decoration: _inputDeco(null),
              items: charOpts.map((c) => DropdownMenuItem(value: c, child: Text('논$c'))).toList(),
              onChanged: (v) => setS(() => essay = v))),
            const SizedBox(width: 4),
            Expanded(child: TextField(controller: wpmCtrl, keyboardType: TextInputType.number,
              decoration: _inputDeco('타수'))),
          ]),
          const SizedBox(height: 12),
          _lbl('메모 (선택)'),
          TextField(
            controller: memoCtrl,
            maxLines: 10,
            decoration: _inputDeco('1. '),
            onChanged: (val) {
              final lines = val.split('\n');
              if (lines.length >= 2) {
                final prev = lines[lines.length - 2];
                final last = lines.last;
                final match = RegExp(r'^(\d+)\.\s').firstMatch(prev);
                if (match != null && last.isEmpty) {
                  final nextNum = int.parse(match.group(1)!) + 1;
                  final newText = '${val}$nextNum. ';
                  memoCtrl.value = TextEditingValue(text: newText,
                      selection: TextSelection.collapsed(offset: newText.length));
                }
              }
            }),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              final rec = StudyRecordModel(date: date, studyHours: hours, studyMinutes: minutes,
                speechChars: speech, essayChars: essay,
                wpm: int.tryParse(wpmCtrl.text.trim()), memo: memoCtrl.text.trim());
              if (!rec.hasData) {
                Navigator.pop(ctx);
                if (context.mounted) showDialog(context: context, builder: (c2) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('기록 없음', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  content: const Text('하나 이상의 항목을 입력해 주세요.'),
                  actions: [ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(c2), child: const Text('확인'))]));
                return;
              }
              await Store.saveRecord(rec);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('저장')),
        ])));
  }

  void _confirmDeleteRecord(BuildContext context, String date) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('기록 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('$date 의 기록을 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () async { await Store.deleteRecord(date); if (ctx.mounted) Navigator.pop(ctx); },
          child: const Text('삭제')),
      ]));
  }
}

class _TimerBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _TimerBtn({required this.icon, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: Container(width: 36, height: 36,
      decoration: BoxDecoration(color: kBlueDark.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: kBlueDark, size: 20)));
}

class _RecordCard extends StatelessWidget {
  final StudyRecordModel record;
  final VoidCallback onEdit, onDelete;
  const _RecordCard({required this.record, required this.onEdit, required this.onDelete});
  String _time() {
    final h = record.studyHours ?? 0, m = record.studyMinutes ?? 0;
    if (h == 0 && m == 0) return '-';
    if (h == 0) return '$m분';
    if (m == 0) return '$h시간';
    return '$h시간 $m분';
  }
  @override Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(record.date, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      Row(children: [
        TextButton(onPressed: onEdit, child: const Text('수정', style: TextStyle(color: kBlue, fontSize: 12))),
        TextButton(onPressed: onDelete, child: const Text('삭제', style: TextStyle(color: Colors.red, fontSize: 12))),
      ]),
    ]),
    const SizedBox(height: 6),
    // 한 줄에 공부시간 / 연설 / 논술 / 타수
    Row(children: [
      _SI(label: '공부', value: _time()),
      const SizedBox(width: 8), _Div(), const SizedBox(width: 8),
      _SI(label: '연설', value: record.speechChars != null ? '${record.speechChars}자' : '-'),
      const SizedBox(width: 6),
      _SI(label: '논술', value: record.essayChars  != null ? '${record.essayChars}자'  : '-'),
      const SizedBox(width: 6),
      _SI(label: '타수', value: record.wpm         != null ? '${record.wpm}타'          : '-'),
    ]),
    if (record.memo.isNotEmpty) ...[
      const SizedBox(height: 8),
      Container(width: double.infinity, padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.7), borderRadius: BorderRadius.circular(8)),
        child: SelectableText(record.memo, style: const TextStyle(fontSize: 12, color: Colors.black87))),
    ],
  ]);
}
class _SI extends StatelessWidget {
  final String label, value; const _SI({required this.label, required this.value});
  @override Widget build(BuildContext context) => Column(children: [
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
    const SizedBox(height: 2),
    Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kBlueDark)),
  ]);
}
class _Div extends StatelessWidget {
  @override Widget build(BuildContext context) => Container(width: 1, height: 28, color: const Color(0xFFC8D8F8));
}

// ── 그래프 ─────────────────────────────────────────────────────────────
class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});
  @override State<GraphScreen> createState() => _GraphScreenState();
}
class _GraphScreenState extends State<GraphScreen> {
  String _period = 'week', _filter = 'wpm';
  List<_BD> _getData() {
    final recs = Store.getRecordsWithData(); final now = DateTime.now();
    double? val(StudyRecordModel r) { switch (_filter) {
      case 'wpm': return r.wpm?.toDouble(); case 'speech': return r.speechChars?.toDouble();
      case 'essay': return r.essayChars?.toDouble();
      case 'time': final t=(r.studyHours??0)*60+(r.studyMinutes??0); return t>0?t.toDouble():null;
      default: return null; } }
    if (_period == 'week') {
      final mon=now.subtract(Duration(days:now.weekday-1)); final days=['월','화','수','목','금','토','일'];
      return List.generate(7,(i){ final d=mon.add(Duration(days:i));
        final k='${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
        try{return _BD(label:days[i],value:val(recs.firstWhere((r)=>r.date==k)));}
        catch(_){return _BD(label:days[i],value:null);}});
    } else if (_period=='month') {
      return [[1,6],[7,12],[13,18],[19,24],[25,30],[31,31]].map((r){
        final vals=<double>[];
        for(int d=r[0];d<=r[1];d++){ final k='${now.year}-${now.month.toString().padLeft(2,'0')}-${d.toString().padLeft(2,'0')}';
          try{final v=val(recs.firstWhere((r)=>r.date==k));if(v!=null)vals.add(v);}catch(_){}}
        return _BD(label:'${r[0]}~${r[1]}일',value:vals.isEmpty?null:vals.reduce((a,b)=>a+b)/vals.length);
      }).toList();
    } else {
      return [['1~3월',[1,2,3]],['4~6월',[4,5,6]],['7~9월',[7,8,9]],['10~12월',[10,11,12]]].map((q){
        final months=q[1] as List<int>;
        final vals=recs.where((r)=>months.contains(int.parse(r.date.split('-')[1]))).map(val).where((v)=>v!=null).map((v)=>v!).toList();
        return _BD(label:q[0] as String,value:vals.isEmpty?null:vals.reduce((a,b)=>a+b)/vals.length);
      }).toList();
    }
  }
  @override Widget build(BuildContext context) {
    final data=_getData(); final maxVal=data.map((d)=>d.value??0).fold(0.0,(a,b)=>a>b?a:b);
    final chartMax=maxVal>0?maxVal*1.2:300.0;
    return Scaffold(backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor:Colors.white,elevation:0,
        leading:IconButton(icon:const Icon(Icons.arrow_back_ios_rounded,color:kBlue),onPressed:()=>Navigator.pop(context)),
        title:const Text('학습 그래프',style:TextStyle(fontWeight:FontWeight.w900,fontSize:18))),
      body: Padding(padding:const EdgeInsets.all(16),child:Column(children:[
        SingleChildScrollView(scrollDirection:Axis.horizontal,child:Row(children:[
          _PB(label:'1주',value:'week',sel:_period,onTap:(v)=>setState(()=>_period=v)),const SizedBox(width:6),
          _PB(label:'1달',value:'month',sel:_period,onTap:(v)=>setState(()=>_period=v)),const SizedBox(width:6),
          _PB(label:'1년',value:'year',sel:_period,onTap:(v)=>setState(()=>_period=v)),const SizedBox(width:16),
          _PB(label:'타수',value:'wpm',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),const SizedBox(width:6),
          _PB(label:'연설',value:'speech',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),const SizedBox(width:6),
          _PB(label:'논술',value:'essay',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),const SizedBox(width:6),
          _PB(label:'시간(분)',value:'time',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),
        ])),
        const SizedBox(height:24),
        Expanded(child:data.every((d)=>d.value==null)?const Center(child:Text('기록이 없습니다',style:TextStyle(color:Colors.grey))):Row(crossAxisAlignment:CrossAxisAlignment.end,children:data.map((d){
          final ratio=d.value!=null?d.value!/chartMax:0.0;
          return Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[
            if(d.value!=null)Text(d.value!.round().toString(),style:const TextStyle(fontSize:10,color:kBlue,fontWeight:FontWeight.w700)),
            const SizedBox(height:4),
            Flexible(child:FractionallySizedBox(heightFactor:ratio>0?ratio:0.02,child:Container(decoration:BoxDecoration(color:d.value!=null?kBlue:Colors.grey[300],borderRadius:const BorderRadius.vertical(top:Radius.circular(4)))))),
            const SizedBox(height:6),
            Text(d.label,style:const TextStyle(fontSize:10,color:Colors.grey),textAlign:TextAlign.center),
          ])));
        }).toList())),
      ])));
  }
}
class _BD{final String label;final double? value;const _BD({required this.label,required this.value});}
class _PB extends StatelessWidget {
  final String label,value,sel;final void Function(String) onTap;
  const _PB({required this.label,required this.value,required this.sel,required this.onTap});
  @override Widget build(BuildContext context){final isSel=value==sel;return GestureDetector(onTap:()=>onTap(value),child:Container(
    padding:const EdgeInsets.symmetric(horizontal:14,vertical:6),
    decoration:BoxDecoration(color:isSel?kBlue:kBlueLight,borderRadius:BorderRadius.circular(20)),
    child:Text(label,style:TextStyle(color:isSel?Colors.white:kBlue,fontWeight:FontWeight.w700,fontSize:12))));}
}

// ── 전역 상태 ───────────────────────────────────────────────────────────
final _analyzerCtrl     = TextEditingController();
bool  _analyzerAnalyzed = false;
final _searchScrollCtrl = ScrollController(); // 스크롤 위치 유지

// ── 약어확인 탭 ──────────────────────────────────────────────────────────
class SentenceAnalyzerScreen extends StatefulWidget {
  const SentenceAnalyzerScreen({super.key});
  @override State<SentenceAnalyzerScreen> createState() => _SentenceAnalyzerScreenState();
}
class _SentenceAnalyzerScreenState extends State<SentenceAnalyzerScreen> {
  final _focusNode = FocusNode();
  AbbreviationModel? _selectedAbbr;
  OverlayEntry? _tooltipOverlay;

  @override void dispose() { _focusNode.dispose(); _tooltipOverlay?.remove(); super.dispose(); }

  void _showAbbrTooltip(BuildContext context, AbbreviationModel abbr, Offset position) {
    _tooltipOverlay?.remove(); _tooltipOverlay = null;
    final screenW = MediaQuery.of(context).size.width;
    final overlay = Overlay.of(context);
    _tooltipOverlay = OverlayEntry(builder: (_) => Stack(children: [
      Positioned.fill(child: GestureDetector(onTap: _closeTooltip, behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand())),
      Positioned(
        left: position.dx.clamp(8.0, screenW - 208.0),
        top: (position.dy - 76).clamp(8.0, double.infinity),
        child: Material(color: Colors.transparent, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 200),
          decoration: BoxDecoration(
            color: Colors.white,              // 흰색 배경
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E8FF)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0,3))]),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(abbr.displayWord, style: TextStyle(color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 13)),
              if (abbr.isFavorite) const Text(' ⭐', style: TextStyle(fontSize: 10)),
              ...abbr.typeLabels.map((l) {
                final c = l == '동시' ? kPurple : l == '합성' ? kBlueSky : kBlueDark;
                return Container(margin: const EdgeInsets.only(left: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(l, style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w700)));
              }),
            ]),
            if (abbr.strokeDisplay.isNotEmpty) ...[
              const SizedBox(height: 3),
              Text(abbr.strokeDisplay, style: const TextStyle(fontSize: 11, color: Colors.grey)),
            ],
          ]))))],
    ));
    overlay.insert(_tooltipOverlay!);
    setState(() => _selectedAbbr = abbr);
  }

  void _closeTooltip() {
    _tooltipOverlay?.remove(); _tooltipOverlay = null;
    if (mounted) setState(() => _selectedAbbr = null);
  }

  void _confirmClear(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('모두 지우기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: const Text('입력한 문장을 모두 지울까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () {
            _analyzerCtrl.clear(); _analyzerAnalyzed = false;
            Navigator.pop(ctx); setState(() {});
          },
          child: const Text('지우기')),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('abbreviations').listenable(),
      builder: (context, box, _) {
        final abbrevs = Store.getAbbreviations();
        final text = _analyzerCtrl.text;
        final parts = _analyzerAnalyzed ? analyzeText(text, abbrevs) : <_Span>[];
        final found = _analyzerAnalyzed
            ? parts.where((p) => p.type != 'normal').map((p) => p.abbr!).toSet().toList()
            : <AbbreviationModel>[];

        return GestureDetector(
          onTap: () { _closeTooltip(); FocusScope.of(context).requestFocus(_focusNode); },
          child: Scaffold(backgroundColor: Colors.white, resizeToAvoidBottomInset: true,
            body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(children: [
                  const Expanded(child: Text('문장 내 약어 추출',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                  if (_analyzerCtrl.text.isNotEmpty)
                    GestureDetector(
                      onTap: () => _confirmClear(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(20)),
                        child: const Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.clear_rounded, size: 14, color: Colors.red),
                          SizedBox(width: 4),
                          Text('모두 지우기', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w600)),
                        ]))),
                ])),
              Expanded(child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(controller: _analyzerCtrl, focusNode: _focusNode, maxLines: 4,
                    onChanged: (_) => setState(() => _analyzerAnalyzed = false),
                    decoration: InputDecoration(
                      hintText: '분석할 문장을 입력하세요...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBlue)))),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: ElevatedButton(
                    onPressed: () => setState(() => _analyzerAnalyzed = true),
                    style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('약어 분석하기', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
                  if (_analyzerAnalyzed && text.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 16),
                        child: Center(child: Text('문장을 먼저 입력해 주세요.', style: TextStyle(color: Colors.grey)))),
                  if (_analyzerAnalyzed && text.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, runSpacing: 6, children: [
                      _Leg(color: kBlue, label: '일반 약어'),
                      _Leg(color: kBlueSky, label: '합성약어'),
                      _Leg(color: kPurple, label: '동시처리약어'),
                      const Text('⭐ 즐겨찾기', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                    const SizedBox(height: 8),
                    Container(width: double.infinity, padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFF8F9FF),
                          borderRadius: BorderRadius.circular(12), border: Border.all(color: kBlueLight)),
                      child: Wrap(children: parts.map((p) {
                        Color color = Colors.black87; FontWeight fw = FontWeight.w400;
                        if (p.type == 'abbr')       { color = kBlue;    fw = FontWeight.w700; }
                        if (p.type == 'composite')  { color = kBlueSky; fw = FontWeight.w700; }
                        if (p.type == 'concurrent') { color = kPurple;  fw = FontWeight.w700; }
                        final displayText = (p.resolvedText ?? p.text) + (p.abbr?.isFavorite == true ? '⭐' : '');
                        if (p.abbr != null) {
                          final isSelected = _selectedAbbr?.id == p.abbr!.id;
                          return GestureDetector(
                            onTapUp: (details) {
                              if (isSelected) { _closeTooltip(); }
                              else { _showAbbrTooltip(context, p.abbr!, details.globalPosition); }
                            },
                            child: Container(
                              decoration: isSelected ? BoxDecoration(color: color.withOpacity(0.12),
                                  borderRadius: BorderRadius.circular(3)) : null,
                              child: Text(displayText, style: TextStyle(fontSize: 16, color: color, fontWeight: fw, height: 1.8,
                                  decoration: isSelected ? TextDecoration.underline : null, decorationColor: color))));
                        }
                        return Text(displayText, style: TextStyle(fontSize: 16, color: color, fontWeight: fw, height: 1.8));
                      }).toList())),
                    if (found.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('사용된 약어 (${found.length}개)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey)),
                        IconButton(icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                          onPressed: () {
                            final t = found.map((a) => '${a.displayWord}: ${a.strokeDisplay}').join('\n');
                            Clipboard.setData(ClipboardData(text: t));
                            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                content: Text('약어 목록이 복사되었습니다'), backgroundColor: kBlue,
                                duration: Duration(seconds: 1)));
                          }),
                      ]),
                      const SizedBox(height: 4),
                      GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 1.6),
                        itemCount: found.length,
                        itemBuilder: (ctx, i) => _AbbrGridCard(abbr: found[i])),
                      const SizedBox(height: 16),
                    ],
                  ],
                ]))),
            ]))));
      });
  }
}

class _AbbrGridCard extends StatelessWidget {
  final AbbreviationModel abbr;
  const _AbbrGridCard({required this.abbr});
  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFEEF0F8))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
      Row(children: [
        Flexible(child: Text(abbr.displayWord, style: TextStyle(color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 12), overflow: TextOverflow.ellipsis)),
        if (abbr.isFavorite) const Text('⭐', style: TextStyle(fontSize: 9)),
      ]),
      if (abbr.typeLabels.isNotEmpty) Wrap(spacing: 2, children: abbr.typeLabels.map((l) {
        final c = l == '동시' ? kPurple : l == '합성' ? kBlueSky : kBlueDark;
        return Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
          decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
          child: Text(l, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.w700)));
      }).toList()),
      if (abbr.strokeDisplay.isNotEmpty)
        Text(abbr.strokeDisplay, style: const TextStyle(fontSize: 9, color: Colors.grey),
            overflow: TextOverflow.ellipsis, maxLines: 1),
    ]));
}

// ── 약어검색 탭 ──────────────────────────────────────────────────────────
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override State<SearchScreen> createState() => _SearchScreenState();
}
class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  bool _showFavOnly = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('abbreviations').listenable(),
      builder: (context, box, _) {
        final q = _ctrl.text.trim();
        final all = Store.getAbbreviations();
        var results = q.isEmpty ? all : sortedSearchResults(all, q);
        if (_showFavOnly) results = results.where((a) => a.isFavorite).toList();

        return Scaffold(backgroundColor: Colors.white,
          body: SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12), child: Row(children: [
              const Expanded(child: Text('약어 검색', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              GestureDetector(onTap: () => setState(() => _showFavOnly = !_showFavOnly),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _showFavOnly ? const Color(0xFFFFD700).withOpacity(0.15) : kBlueLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _showFavOnly ? const Color(0xFFFFD700) : Colors.transparent, width: 1.2)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_rounded, size: 16, color: _showFavOnly ? const Color(0xFFFFD700) : Colors.grey),
                    const SizedBox(width: 4),
                    Text('즐겨찾기', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: _showFavOnly ? const Color(0xFFB8860B) : Colors.grey)),
                  ]))),
              ElevatedButton.icon(
                onPressed: () => _showEditDialog(context),
                icon: const Icon(Icons.add, size: 16), label: const Text('추가'),
                style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6))),
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
              controller: _ctrl, onChanged: (_) => setState(() {}),
              decoration: InputDecoration(hintText: '단어로 검색하세요...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBlue))))),
            const SizedBox(height: 8),
            Expanded(child: results.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_showFavOnly ? '즐겨찾기한 약어가 없습니다' : '약어가 없습니다',
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  if (!_showFavOnly) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(onPressed: () => _showEditDialog(context),
                      style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBlue),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      child: const Text('약어 추가하기', style: TextStyle(fontWeight: FontWeight.w700))),
                  ]]))
              : ListView.builder(
                  controller: _searchScrollCtrl,  // 스크롤 위치 유지
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final a = results[index];
                    return _AbbrListTile(abbr: a,
                      onFav: () async { await Store.saveAbbreviation(a.copyWith(isFavorite: !a.isFavorite)); },
                      onEdit: () => _showEditDialog(context, existing: a),
                      onDelete: () => _confirmDelete(context, a),
                      onRemind: () => _showReminderDialog(context, a.word, 'word'));
                  })),
          ])));
      });
  }

  void _showEditDialog(BuildContext context, {AbbreviationModel? existing}) {
    final wordCtrl    = TextEditingController(text: existing?.word.replaceAll('*', ' ') ?? '');
    final initialCtrl = TextEditingController(text: existing?.initial.isNotEmpty == true ? existing!.initial.join('+') : '');
    final medialCtrl  = TextEditingController(text: existing?.medial.isNotEmpty  == true ? existing!.medial.join('+')  : '');
    final finalCtrl   = TextEditingController(text: existing?.final_.isNotEmpty  == true ? existing!.final_.join('+')  : '');
    bool isComposite  = existing?.isComposite  ?? false;
    bool isConcurrent = existing?.isConcurrent ?? false;
    bool isAttached   = existing?.isAttached   ?? false;
    bool isFavorite   = existing?.isFavorite   ?? false;
    final outerCtx    = context;

    Future<void> doSave(bool c1, bool c2, bool c3, bool c4) async {
      final rawWord = wordCtrl.text.trim();
      if (rawWord.isEmpty) return;
      final word = encodeWord(rawWord);
      List<String> pf(String s) => s.split(RegExp(r'[+\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      await Store.saveAbbreviation(AbbreviationModel(
        id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
        word: word, initial: pf(initialCtrl.text), medial: pf(medialCtrl.text), final_: pf(finalCtrl.text),
        isComposite: c1, isConcurrent: c2, isAttached: c3, isFavorite: c4));
    }

    Future<void> doSaveFlow(BuildContext dCtx, bool c1, bool c2, bool c3, bool c4) async {
      final rawWord = wordCtrl.text.trim();
      if (rawWord.isEmpty) return;
      final word = encodeWord(rawWord);
      final isDup = Store.existsWord(word, excludeId: existing?.id);
      Navigator.pop(dCtx);
      bool? ok;
      if (isDup) {
        ok = await showDialog<bool>(context: outerCtx, builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('중복 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text('이미 존재합니다. 그래도 저장할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c, true), child: const Text('저장'))]));
      } else {
        ok = await showDialog<bool>(context: outerCtx, builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('저장 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text('저장할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c, true), child: const Text('저장'))]));
      }
      if (ok == true) await doSave(c1, c2, c3, c4);
    }

    showDialog(context: context, barrierColor: Colors.black.withOpacity(0.3),
      builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing == null ? '약어 추가' : '약어 수정',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('단어'),
            TextField(controller: wordCtrl, decoration: _inputDeco(''), textInputAction: TextInputAction.next),
            const SizedBox(height: 4),
            Text('※ 띄어쓰기는 저장 시 * 로 자동 변환됩니다', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            _lbl('초성'),
            TextField(controller: initialCtrl, decoration: _inputDeco(''), textInputAction: TextInputAction.next),
            const SizedBox(height: 8),
            _lbl('중성'),
            TextField(controller: medialCtrl, decoration: _inputDeco(''), textInputAction: TextInputAction.next),
            const SizedBox(height: 8),
            _lbl('종성'),
            // 엔터로 저장
            TextField(controller: finalCtrl, decoration: _inputDeco(''),
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => doSaveFlow(dCtx, isComposite, isConcurrent, isAttached, isFavorite)),
            const SizedBox(height: 4),
            Text('※ 종성 ㅋ → 자동으로 (ㅋ) 표시  |  여러 값은 + 로 구분',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            const SizedBox(height: 14),
            _TypeToggleRow(
              isComposite: isComposite, isConcurrent: isConcurrent,
              isAttached: isAttached, isFavorite: isFavorite,
              onCompositeChanged: (v) => setS(() => isComposite = v),
              onConcurrentChanged: (v) => setS(() => isConcurrent = v),
              onAttachedChanged: (v) => setS(() => isAttached = v),
              onFavoriteChanged: (v) => setS(() => isFavorite = v)),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(dCtx),
                child: const Text('취소', style: TextStyle(color: Colors.grey))),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
              onPressed: () => doSaveFlow(dCtx, isComposite, isConcurrent, isAttached, isFavorite),
              child: const Text('다음')),
          ]);
      }));
  }

  void _confirmDelete(BuildContext context, AbbreviationModel a) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('삭제 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('"${a.displayWord}" 약어를 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () async { await Store.deleteAbbreviation(a.id); if (ctx.mounted) Navigator.pop(ctx); },
          child: const Text('삭제')),
      ]));
  }
}

// ── 토글 분류 버튼 ──────────────────────────────────────────────────────
class _TypeToggleRow extends StatelessWidget {
  final bool isComposite, isConcurrent, isAttached, isFavorite;
  final ValueChanged<bool> onCompositeChanged, onConcurrentChanged, onAttachedChanged, onFavoriteChanged;
  const _TypeToggleRow({required this.isComposite, required this.isConcurrent,
    required this.isAttached, required this.isFavorite,
    required this.onCompositeChanged, required this.onConcurrentChanged,
    required this.onAttachedChanged, required this.onFavoriteChanged});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
    _ToggleChip(label: '합성약어', color: kBlueSky, selected: isComposite, onTap: () => onCompositeChanged(!isComposite)),
    _ToggleChip(label: '동시처리', color: kPurple, selected: isConcurrent, onTap: () => onConcurrentChanged(!isConcurrent)),
    _ToggleChip(label: '붙여쓰기', color: kBlueDark, selected: isAttached, onTap: () => onAttachedChanged(!isAttached)),
    _ToggleChip(label: '즐겨찾기', color: const Color(0xFFFFAA00), selected: isFavorite,
        onTap: () => onFavoriteChanged(!isFavorite), icon: Icons.star_rounded),
  ]);
}
class _ToggleChip extends StatelessWidget {
  final String label; final Color color; final bool selected;
  final VoidCallback onTap; final IconData? icon;
  const _ToggleChip({required this.label, required this.color, required this.selected, required this.onTap, this.icon});
  @override
  Widget build(BuildContext context) => GestureDetector(onTap: onTap,
    child: AnimatedContainer(duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(
        color: selected ? color.withOpacity(0.15) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: selected ? color : Colors.transparent, width: 1.5)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (icon != null) ...[Icon(icon, size: 14, color: selected ? color : Colors.grey), const SizedBox(width: 4)],
        Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: selected ? color : Colors.grey)),
      ])));
}

// ── 더보기 메뉴 (빈 곳 터치로만 닫힘) ──────────────────────────────────
class _MenuItem { final String label; final VoidCallback onTap; final bool isDestructive;
  const _MenuItem({required this.label, required this.onTap, this.isDestructive = false}); }

class _AbbrListTile extends StatefulWidget {
  final AbbreviationModel abbr;
  final VoidCallback? onFav, onEdit, onDelete, onRemind;
  const _AbbrListTile({required this.abbr, this.onFav, this.onEdit, this.onDelete, this.onRemind});
  @override State<_AbbrListTile> createState() => _AbbrListTileState();
}
class _AbbrListTileState extends State<_AbbrListTile> {
  OverlayEntry? _menuOverlay;
  bool _menuOpen = false;

  void _openMenu(BuildContext btnCtx) {
    if (_menuOpen) { _closeMenu(); return; }
    final box = btnCtx.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset(box.size.width, box.size.height));
    final screenW = MediaQuery.of(btnCtx).size.width;
    final items = [
      _MenuItem(label: widget.abbr.isFavorite ? '⭐ 즐겨찾기 해제' : '☆ 즐겨찾기 추가',
          onTap: () { _closeMenu(); widget.onFav?.call(); }),
      if (widget.onEdit != null) _MenuItem(label: '✏️ 수정', onTap: () { _closeMenu(); widget.onEdit!(); }),
      if (widget.onRemind != null) _MenuItem(label: '🔔 리마인드 설정', onTap: () { _closeMenu(); widget.onRemind!(); }),
      if (widget.onDelete != null) _MenuItem(label: '🗑 삭제', isDestructive: true,
          onTap: () { _closeMenu(); widget.onDelete!(); }),
    ];
    _menuOverlay = OverlayEntry(builder: (_) => Stack(children: [
      Positioned.fill(child: GestureDetector(onTap: _closeMenu, behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand())),
      Positioned(right: screenW - offset.dx, top: offset.dy,
        child: Material(color: Colors.transparent, child: Container(
          constraints: const BoxConstraints(minWidth: 160),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0,4))],
            border: Border.all(color: const Color(0xFFF0F0F0))),
          child: Column(mainAxisSize: MainAxisSize.min,
            children: items.map((item) => GestureDetector(onTap: item.onTap,
              child: Container(width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Text(item.label, style: TextStyle(fontSize: 14,
                    color: item.isDestructive ? Colors.red : Colors.black87))))).toList())))),
    ]));
    Overlay.of(btnCtx).insert(_menuOverlay!);
    setState(() => _menuOpen = true);
  }

  void _closeMenu() {
    _menuOverlay?.remove(); _menuOverlay = null;
    if (mounted) setState(() => _menuOpen = false);
  }
  @override void dispose() { _closeMenu(); super.dispose(); }

  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF0F8))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (widget.abbr.isAttached) const Text('↙ ', style: TextStyle(fontSize: 14, color: kBlueDark, fontWeight: FontWeight.w700)),
          Text(widget.abbr.displayWord, style: TextStyle(color: widget.abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 15)),
          if (widget.abbr.isFavorite) const Text(' ⭐', style: TextStyle(fontSize: 12)),
          ...widget.abbr.typeLabels.map((label) {
            final color = label == '동시' ? kPurple : label == '합성' ? kBlueSky : kBlueDark;
            final bgColor = label == '동시' ? kPurpleLight : const Color(0xFFE0F4FF);
            return Container(margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
              child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)));
          }),
        ]),
        const SizedBox(height: 4),
        SelectableText(widget.abbr.strokeDisplay, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ])),
      Builder(builder: (btnCtx) => GestureDetector(onTap: () => _openMenu(btnCtx),
        child: Container(padding: const EdgeInsets.all(6),
          child: Icon(Icons.more_horiz, color: _menuOpen ? kBlue : Colors.grey)))),
    ]));
}

// ── 문장등록 탭 ────────────────────────────────────────────────────────
class SentenceRegisterScreen extends StatefulWidget {
  const SentenceRegisterScreen({super.key});
  @override State<SentenceRegisterScreen> createState() => _SentenceRegisterScreenState();
}
class _SentenceRegisterScreenState extends State<SentenceRegisterScreen> {
  final _ctrl = TextEditingController(); final _focusNode = FocusNode();
  @override void dispose() { _ctrl.dispose(); _focusNode.dispose(); super.dispose(); }

  void _save(BuildContext context) {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('저장 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: const Text('저장할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () async {
            await Store.saveSentence(SavedSentenceModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(), text: text,
              createdAt: DateTime.now().toString().substring(0, 10)));
            _ctrl.clear(); if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('저장')),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('sentences').listenable(),
      builder: (context, box, _) {
        final sentences = Store.getSentences();
        return Scaffold(backgroundColor: Colors.white, resizeToAvoidBottomInset: true,
          body: SafeArea(child: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(20,20,20,12),
                child: Align(alignment: Alignment.centerLeft,
                    child: Text('문장 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
              TextField(controller: _ctrl, focusNode: _focusNode, maxLines: 3,
                decoration: InputDecoration(hintText: '복습할 문장을 입력하세요...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBlue)))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => _save(context),
                style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('저장하기', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
            ])),
            const SizedBox(height: 8),
            Expanded(child: sentences.isEmpty
              ? const Center(child: Text('저장된 문장이 없습니다', style: TextStyle(color: Colors.grey, fontSize: 14)))
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sentences.length,
                  itemBuilder: (ctx, i) {
                    final s = sentences[i];
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEF0F8))),
                      child: Row(children: [
                        Expanded(child: SelectableText(s.text, style: const TextStyle(fontSize: 14, height: 1.6))),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, color: Colors.grey),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (v) async {
                            if (v == 'remind') _showReminderDialog(ctx, s.text, 'sentence');
                            if (v == 'delete') {
                              final ok = await showDialog<bool>(context: ctx, builder: (c2) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('삭제 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                content: const Text('이 문장을 삭제할까요?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                                      onPressed: () => Navigator.pop(c2, true), child: const Text('삭제'))]));
                              if (ok == true) await Store.deleteSentence(s.id);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'remind', child: Text('🔔 리마인드 설정')),
                            const PopupMenuItem(value: 'delete', child: Text('🗑 삭제', style: TextStyle(color: Colors.red))),
                          ]),
                      ]));
                  })),
          ])));
      });
  }
}

// ── 리마인드 탭 ────────────────────────────────────────────────────────
class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override State<RemindersScreen> createState() => _RemindersScreenState();
}
class _RemindersScreenState extends State<RemindersScreen> {
  String _tl(String t) => t == 'word' ? '약어' : t == 'favorite' ? '즐겨찾기' : '문장';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('reminders').listenable(),
      builder: (context, box, _) {
        final reminders = Store.getReminders();
        return Scaffold(backgroundColor: Colors.white,
          body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12),
              child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('리마인드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  Text('${reminders.length}개', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                ]),
                ElevatedButton.icon(onPressed: () => _showAddReminderDialog(context),
                  icon: const Icon(Icons.add, size: 16), label: const Text('추가'),
                  style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6))),
              ])),
            Expanded(child: reminders.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  const Text('설정된 리마인드가 없습니다', style: TextStyle(color: Colors.grey, fontSize: 14)),
                  const SizedBox(height: 12),
                  OutlinedButton(onPressed: () => _showAddReminderDialog(context),
                    style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBlue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                    child: const Text('리마인드 추가하기', style: TextStyle(fontWeight: FontWeight.w700))),
                ]))
              : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: reminders.length,
                  itemBuilder: (ctx, i) {
                    final r = reminders[i];
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: r.active ? Colors.white : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(12), border: Border.all(color: const Color(0xFFEEF0F8))),
                      child: Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
                          child: Text(_tl(r.type), style: const TextStyle(fontSize: 11, color: kBlue, fontWeight: FontWeight.w700))),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SelectableText(r.target, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1),
                          Text('${r.date} · ${r.intervalDays}일 간격${r.repeat ? " · 반복" : ""}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ])),
                        Switch(value: r.active, activeColor: kBlue, onChanged: (_) async { await Store.toggleReminder(r.id); }),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                            onPressed: () async { await Store.deleteReminder(r.id); }),
                      ]));
                  })),
          ])));
      });
  }

  void _showAddReminderDialog(BuildContext context) {
    int interval = 1; bool repeat = false;
    String type = 'word'; String? selectedTarget;
    final customCtrl = TextEditingController(); bool useCustom = false;

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final abbrevs = Store.getAbbreviations(); final sentences = Store.getSentences();
      final items = type == 'word' ? abbrevs.map((a) => a.displayWord).toList() : sentences.map((s) => s.text).toList();

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('리마인드 추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _lbl('유형'),
          Row(children: [
            Expanded(child: GestureDetector(onTap: () => setS(() { type = 'word'; selectedTarget = null; }),
              child: Container(padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: type == 'word' ? kBlue : kBlueLight, borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('약어', style: TextStyle(color: type == 'word' ? Colors.white : kBlue, fontWeight: FontWeight.w700)))))),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(onTap: () => setS(() { type = 'sentence'; selectedTarget = null; }),
              child: Container(padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: type == 'sentence' ? kBlue : kBlueLight, borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('문장', style: TextStyle(color: type == 'sentence' ? Colors.white : kBlue, fontWeight: FontWeight.w700)))))),
          ]),
          const SizedBox(height: 12),
          _lbl(type == 'word' ? '약어 선택' : '문장 선택'),
          if (items.isEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Text(type == 'word' ? '등록된 약어가 없습니다' : '등록된 문장이 없습니다',
                    style: const TextStyle(color: Colors.grey, fontSize: 12)))
          else Container(height: 120,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(8)),
            child: ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
              final item = items[i]; final isSel = selectedTarget == item;
              return GestureDetector(onTap: () => setS(() { selectedTarget = item; useCustom = false; customCtrl.clear(); }),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  color: isSel ? kBlueLight : Colors.transparent,
                  child: Text(item, style: TextStyle(fontSize: 13, color: isSel ? kBlue : Colors.black87,
                      fontWeight: isSel ? FontWeight.w600 : FontWeight.w400), maxLines: 2, overflow: TextOverflow.ellipsis)));
            })),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(value: useCustom, activeColor: kBlue,
                onChanged: (v) => setS(() { useCustom = v ?? false; if (useCustom) selectedTarget = null; })),
            const Text('직접 입력', style: TextStyle(fontSize: 13)),
          ]),
          if (useCustom) TextField(controller: customCtrl, decoration: _inputDeco('내용을 입력하세요')),
          const SizedBox(height: 12),
          _lbl('간격'),
          Wrap(spacing: 8, children: [1, 3, 7].map((d) => GestureDetector(onTap: () => setS(() => interval = d),
            child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: interval == d ? kBlue : kBlueLight, borderRadius: BorderRadius.circular(20)),
              child: Text('$d일', style: TextStyle(color: interval == d ? Colors.white : kBlue, fontWeight: FontWeight.w700))))).toList()),
          const SizedBox(height: 10),
          Row(children: [
            Checkbox(value: repeat, activeColor: kBlue, onChanged: (v) => setS(() => repeat = v ?? false)),
            const Text('반복'),
          ]),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
            onPressed: () async {
              final target = useCustom ? customCtrl.text.trim() : selectedTarget;
              if (target == null || target.isEmpty) return;
              Navigator.pop(ctx);
              final dup = Store.findReminder(target);
              if (dup != null) {
                final ok = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('중복 리마인드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  content: const Text('이미 추가된 리마인드입니다.\n그래도 저장하시겠습니까?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(c2, true), child: const Text('저장'))]));
                if (ok != true) return;
              }
              final date = DateTime.now().add(Duration(days: interval));
              final ds = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
              await Store.saveReminder(ReminderModel(id: DateTime.now().millisecondsSinceEpoch.toString(),
                type: type, target: target, date: ds, intervalDays: interval, repeat: repeat));
            }, child: const Text('설정')),
        ]);
    }));
  }
}

// ── 공통 위젯 ────────────────────────────────────────────────────────────
class _AbbrTile extends StatelessWidget {
  final AbbreviationModel abbr;
  const _AbbrTile({required this.abbr});
  @override Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), border: Border.all(color: const Color(0xFFEEF0F8))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (abbr.isAttached) const Text('↙ ', style: TextStyle(fontSize: 14, color: kBlueDark, fontWeight: FontWeight.w700)),
        Text(abbr.displayWord, style: TextStyle(color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 15)),
        if (abbr.isFavorite) const Text(' ⭐', style: TextStyle(fontSize: 12)),
        ...abbr.typeLabels.map((label) {
          final color = label == '동시' ? kPurple : label == '합성' ? kBlueSky : kBlueDark;
          final bgColor = label == '동시' ? kPurpleLight : const Color(0xFFE0F4FF);
          return Container(margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)));
        }),
      ]),
      const SizedBox(height: 4),
      SelectableText(abbr.strokeDisplay, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]));
}

class _Leg extends StatelessWidget {
  final Color color; final String label;
  const _Leg({required this.color, required this.label});
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 12, height: 12, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  ]);
}

// 리마인드 설정 (기존 설정값 불러오기 + 중복 체크)
void _showReminderDialog(BuildContext context, String target, String type) {
  final existing = Store.findReminder(target);
  int interval = existing?.intervalDays ?? 1;
  bool repeat  = existing?.repeat ?? false;

  showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(existing != null ? '리마인드 수정' : '리마인드 설정',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, children: [1, 3, 7].map((d) => GestureDetector(
        onTap: () => setS(() => interval = d),
        child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(color: interval == d ? kBlue : kBlueLight, borderRadius: BorderRadius.circular(20)),
          child: Text('$d일', style: TextStyle(color: interval == d ? Colors.white : kBlue, fontWeight: FontWeight.w700))))).toList()),
      const SizedBox(height: 12),
      Row(children: [
        Checkbox(value: repeat, activeColor: kBlue, onChanged: (v) => setS(() => repeat = v ?? false)),
        const Text('반복'),
      ]),
    ]),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
        onPressed: () async {
          if (existing == null) {
            final dup = Store.findReminder(target);
            if (dup != null) {
              Navigator.pop(ctx);
              final ok = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: const Text('중복 리마인드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                content: const Text('이미 추가된 리마인드입니다.\n그래도 저장하시겠습니까?'),
                actions: [
                  TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                      onPressed: () => Navigator.pop(c2, true), child: const Text('저장'))]));
              if (ok != true) return;
            }
          }
          final date = DateTime.now().add(Duration(days: interval));
          final ds = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
          await Store.saveReminder(ReminderModel(
            id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
            type: type, target: target, date: ds, intervalDays: interval, repeat: repeat));
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('저장')),
    ])));
}

Widget _lbl(String text) => Padding(padding: const EdgeInsets.only(bottom: 6),
  child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)));

InputDecoration _inputDeco(String? hint) => InputDecoration(
  hintText: hint, isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBlue)));

extension ListExt<T> on List<T> {
  T? elementAtOrNull(int index) => (index >= 0 && index < length) ? this[index] : null;
}