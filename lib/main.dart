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

// ════════════════════════════════════════════════════════
// 색상
// ════════════════════════════════════════════════════════
const Color kBlue        = Color(0xFF1A6CF6);
const Color kBlueSky     = Color(0xFF398FCC);
const Color kBlueLight   = Color(0xFFE8F0FE);
const Color kBlueDark    = Color(0xFF0F4AB3);
const Color kPurple      = Color(0xFF6a8fa9);
const Color kPurpleLight = Color(0xFFF3EFFE);
const Color kTimerBg     = Color(0xFFBED3F7);

// ════════════════════════════════════════════════════════
// 띄어쓰기 변환 유틸
// ════════════════════════════════════════════════════════
String encodeWord(String raw) => raw.replaceAll(' ', '*');
String decodeWordForSearch(String word) => word.replaceAll('*', '');

// ════════════════════════════════════════════════════════
// 데이터 모델
// ════════════════════════════════════════════════════════
class AbbreviationModel {
  final String id;
  final String word;
  final List<String> initial;
  final List<String> medial;
  final List<String> final_;
  final bool isComposite;
  final bool isConcurrent;
  final bool isAttached;
  final bool isFavorite;

  AbbreviationModel({
    required this.id,
    required this.word,
    this.initial      = const [],
    this.medial       = const [],
    this.final_       = const [],
    this.isComposite  = false,
    this.isConcurrent = false,
    this.isAttached   = false,
    this.isFavorite   = false,
  });

  String get searchKey => decodeWordForSearch(word);
  String get displayWord => word;

  Map<String, dynamic> toMap() => {
    'id': id, 'word': word,
    'initial': initial, 'medial': medial, 'final_': final_,
    'isComposite': isComposite, 'isConcurrent': isConcurrent,
    'isAttached': isAttached, 'isFavorite': isFavorite,
  };

  factory AbbreviationModel.fromMap(Map m) => AbbreviationModel(
    id:           m['id']           as String,
    word:         m['word']         as String,
    initial:      List<String>.from(m['initial']   ?? []),
    medial:       List<String>.from(m['medial']    ?? []),
    final_:       List<String>.from(m['final_']    ?? []),
    isComposite:  m['isComposite']  as bool? ?? false,
    isConcurrent: m['isConcurrent'] as bool? ?? false,
    isAttached:   m['isAttached']   as bool? ?? false,
    isFavorite:   m['isFavorite']   as bool? ?? false,
  );

  AbbreviationModel copyWith({
    String? word, List<String>? initial, List<String>? medial,
    List<String>? final_, bool? isComposite, bool? isConcurrent,
    bool? isAttached, bool? isFavorite,
  }) => AbbreviationModel(
    id: id,
    word:         word         ?? this.word,
    initial:      initial      ?? this.initial,
    medial:       medial       ?? this.medial,
    final_:       final_       ?? this.final_,
    isComposite:  isComposite  ?? this.isComposite,
    isConcurrent: isConcurrent ?? this.isConcurrent,
    isAttached:   isAttached   ?? this.isAttached,
    isFavorite:   isFavorite   ?? this.isFavorite,
  );

  String get strokeDisplay {
    String fmtInitial(List<String> l) => l.join('+');
    String fmtMedial(List<String> l)  => l.join('+');
    String fmtFinal(List<String> l)   =>
        l.map((v) => v == 'ㅋ' ? '(ㅋ)' : v).join('+');
    final parts = <String>[];
    if (initial.isNotEmpty) parts.add(fmtInitial(initial));
    if (medial.isNotEmpty)  parts.add(fmtMedial(medial));
    if (final_.isNotEmpty)  parts.add(fmtFinal(final_));
    return parts.join(' / ');
  }

  // ★ 1번 수정: 모든 타입 레이블을 리스트로 반환 (우선순위 없이 전부 표시)
  List<String> get typeLabels {
    final labels = <String>[];
    if (isConcurrent) labels.add('동시');
    if (isComposite)  labels.add('합성');
    if (isAttached)   labels.add('붙여쓰기');
    return labels;
  }

  // 기존 호환성 유지
  String get typeLabel => typeLabels.join('/');

  Color get typeColor {
    if (isConcurrent) return kPurple;
    if (isComposite)  return kBlueSky;
    return kBlue;
  }
}

class StudyRecordModel {
  final String date;
  final int?   studyHours;
  final int?   studyMinutes;
  final int?   speechChars;
  final int?   essayChars;
  final int?   wpm;
  final String memo;

  StudyRecordModel({
    required this.date,
    this.studyHours, this.studyMinutes,
    this.speechChars, this.essayChars,
    this.wpm, this.memo = '',
  });

  bool get hasData =>
      studyHours != null || studyMinutes != null ||
      speechChars != null || essayChars != null ||
      wpm != null || memo.isNotEmpty;

  Map<String, dynamic> toMap() => {
    'date': date, 'studyHours': studyHours, 'studyMinutes': studyMinutes,
    'speechChars': speechChars, 'essayChars': essayChars, 'wpm': wpm, 'memo': memo,
  };

  factory StudyRecordModel.fromMap(Map m) => StudyRecordModel(
    date:         m['date']         as String,
    studyHours:   m['studyHours']   as int?,
    studyMinutes: m['studyMinutes'] as int?,
    speechChars:  m['speechChars']  as int?,
    essayChars:   m['essayChars']   as int?,
    wpm:          m['wpm']          as int?,
    memo:         m['memo']         as String? ?? '',
  );
}

class SavedSentenceModel {
  final String id, text, createdAt;
  SavedSentenceModel({required this.id, required this.text, required this.createdAt});
  Map<String, dynamic> toMap() => {'id': id, 'text': text, 'createdAt': createdAt};
  factory SavedSentenceModel.fromMap(Map m) => SavedSentenceModel(
    id: m['id'] as String, text: m['text'] as String,
    createdAt: m['createdAt'] as String);
}

class ReminderModel {
  final String id, type, target, date;
  final int intervalDays;
  final bool repeat;
  bool active;
  ReminderModel({
    required this.id, required this.type,
    required this.target, required this.date,
    this.intervalDays = 1, this.repeat = false, this.active = true,
  });
  Map<String, dynamic> toMap() => {
    'id': id, 'type': type, 'target': target, 'date': date,
    'intervalDays': intervalDays, 'repeat': repeat, 'active': active,
  };
  factory ReminderModel.fromMap(Map m) => ReminderModel(
    id: m['id'] as String, type: m['type'] as String,
    target: m['target'] as String, date: m['date'] as String,
    intervalDays: m['intervalDays'] as int? ?? 1,
    repeat: m['repeat'] as bool? ?? false,
    active: m['active'] as bool? ?? true,
  );
}

// ════════════════════════════════════════════════════════
// 저장소
// ════════════════════════════════════════════════════════
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
    return getAbbreviations().any((a) =>
        decodeWordForSearch(a.word) == key && a.id != excludeId);
  }

  static List<StudyRecordModel> getRecords() =>
      _re.values.map((e) => StudyRecordModel.fromMap(Map.from(e as Map))).toList();
  static List<StudyRecordModel> getRecordsWithData() =>
      getRecords().where((r) => r.hasData).toList();
  static StudyRecordModel? getRecord(String date) {
    try { return getRecords().firstWhere((r) => r.date == date); }
    catch (_) { return null; }
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
}

// ════════════════════════════════════════════════════════
// 타이머
// ════════════════════════════════════════════════════════
class StudyTimer extends ChangeNotifier {
  static final StudyTimer _instance = StudyTimer._();
  static StudyTimer get instance => _instance;
  StudyTimer._();

  Timer? _timer;
  int  _seconds = 0;
  bool _running = false;

  bool   get running => _running;
  int    get hours   => _seconds ~/ 3600;
  int    get minutes => (_seconds % 3600) ~/ 60;
  String get display {
    final h = _seconds ~/ 3600;
    final m = (_seconds % 3600) ~/ 60;
    final s = _seconds % 60;
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
    final ex  = Store.getRecord(key);
    await Store.saveRecord(StudyRecordModel(
      date: key, studyHours: hours, studyMinutes: minutes,
      speechChars: ex?.speechChars, essayChars: ex?.essayChars,
      wpm: ex?.wpm, memo: ex?.memo ?? '',
    ));
  }
}

// ════════════════════════════════════════════════════════
// 문장 분석
// ════════════════════════════════════════════════════════
class _Span {
  final String text;
  final String type;
  final AbbreviationModel? abbr;
  const _Span({required this.text, required this.type, this.abbr});
}

List<_Span> analyzeText(String raw, List<AbbreviationModel> abbrevs) {
  final normalized = raw.replaceAll(' ', '*');
  List<_Span> parts = [_Span(text: normalized, type: 'normal')];
  final sorted = [...abbrevs]..sort((a, b) => b.word.length.compareTo(a.word.length));
  for (final a in sorted) {
    final next = <_Span>[];
    for (final p in parts) {
      if (p.type != 'normal') { next.add(p); continue; }
      final segs = p.text.split(a.word);
      for (int i = 0; i < segs.length; i++) {
        if (segs[i].isNotEmpty) next.add(_Span(text: segs[i], type: 'normal'));
        if (i < segs.length - 1) {
          String type = 'abbr';
          if (a.isConcurrent) type = 'concurrent';
          else if (a.isComposite) type = 'composite';
          next.add(_Span(text: a.word, type: type, abbr: a));
        }
      }
    }
    parts = next;
  }
  return parts.map((p) {
    if (p.type == 'normal') return _Span(text: p.text.replaceAll('*', ' '), type: 'normal');
    return p;
  }).toList();
}

// ════════════════════════════════════════════════════════
// 앱
// ════════════════════════════════════════════════════════
class SoggiApp extends StatelessWidget {
  const SoggiApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: '속끼록',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: kBlue), useMaterial3: true),
    home: const SplashScreen(),
  );
}

// ════════════════════════════════════════════════════════
// 로딩
// ════════════════════════════════════════════════════════
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});
  @override State<SplashScreen> createState() => _SplashScreenState();
}
class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 1800), () {
      if (mounted) Navigator.of(context).pushReplacement(
          MaterialPageRoute(builder: (_) => const MainShell()));
    });
  }
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: kBlue,
    body: Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Text('⌨️', style: TextStyle(fontSize: 52)),
      const SizedBox(height: 12),
      const Text('속끼록', style: TextStyle(
          fontSize: 26, fontWeight: FontWeight.w900,
          color: Colors.white, letterSpacing: 2)),
      const SizedBox(height: 6),
      Text('약어 학습 · 기록 · 복습',
          style: TextStyle(fontSize: 14, color: Colors.white.withOpacity(0.75))),
      const SizedBox(height: 40),
      SizedBox(width: 40, child: LinearProgressIndicator(
          backgroundColor: Colors.white.withOpacity(0.3),
          color: Colors.white,
          borderRadius: BorderRadius.circular(4))),
    ])),
  );
}

// ════════════════════════════════════════════════════════
// 메인 쉘
// ════════════════════════════════════════════════════════
class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override State<MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<MainShell> {
  int _idx = 0;
  final _screens = [
    const HomeScreen(),
    const SentenceAnalyzerScreen(),
    const SearchScreen(),
    const SentenceRegisterScreen(),
    const RemindersScreen(),
  ];
  @override
  Widget build(BuildContext context) => Scaffold(
    body: _screens[_idx],
    bottomNavigationBar: SafeArea(
      child: Container(
        decoration: const BoxDecoration(
            border: Border(top: BorderSide(color: Color(0xFFF0F0F0)))),
        child: BottomNavigationBar(
          currentIndex: _idx, onTap: (i) => setState(() => _idx = i),
          selectedItemColor: kBlue, unselectedItemColor: Colors.grey,
          showUnselectedLabels: true, type: BottomNavigationBarType.fixed,
          selectedFontSize: 10, unselectedFontSize: 10,
          selectedIconTheme: const IconThemeData(size: 24),
          unselectedIconTheme: const IconThemeData(size: 24),
          items: const [
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.home_rounded)),          label: '홈'),
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.search_rounded)),        label: '약어확인'),
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.menu_book_rounded)),     label: '약어검색'),
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.bookmark_rounded)),      label: '문장등록'),
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.notifications_rounded)), label: '리마인드'),
          ],
        ),
      ),
    ),
  );
}

// ════════════════════════════════════════════════════════
// 홈 화면
// ════════════════════════════════════════════════════════
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
    _month    = DateTime(now.year, now.month);
    _selected = _todayKey();
    StudyTimer.instance.addListener(_onTick);
  }
  @override
  void dispose() { StudyTimer.instance.removeListener(_onTick); super.dispose(); }
  void _onTick() { if (mounted) setState(() {}); }

  String _todayKey() {
    final now = DateTime.now();
    final base = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
    return '${base.year}-${base.month.toString().padLeft(2,'0')}-${base.day.toString().padLeft(2,'0')}';
  }
  String _fmt(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('studyRecords').listenable(),
      builder: (context, box, _) {
        final record       = _selected != null ? Store.getRecord(_selected!) : null;
        final hasData      = record?.hasData ?? false;
        final daysInMonth  = DateTime(_month.year, _month.month + 1, 0).day;
        final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;
        final markedDates  = Store.getRecordsWithData().map((r) => r.date).toSet();
        final timer        = StudyTimer.instance;
        final calW = (MediaQuery.of(context).size.width * 0.85).clamp(0.0, 340.0);

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(child: SingleChildScrollView(child: Column(children: [

            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 0),
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
                    child: Container(
                      width: 34, height: 34,
                      decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Icon(Icons.bar_chart_rounded, color: kBlue, size: 20)),
                    ),
                  ),
                ]),
              ]),
            ),

            const SizedBox(height: 8),

            // ★ 6번: 달력 - 작은 동그라미로 변경
            Center(
              child: SizedBox(
                width: calW,
                child: Column(children: [
                  Row(children: ['일','월','화','수','목','금','토'].map((d) => Expanded(
                    child: Center(child: Text(d, style: const TextStyle(
                        fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w600))),
                  )).toList()),
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
                      final isSel  = key == _selected;
                      return GestureDetector(
                        onTap: () => setState(() => _selected = key),
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            // 선택된 날 배경
                            if (isSel)
                              Container(
                                decoration: BoxDecoration(
                                  color: kBlue,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                              ),
                            // ★ 기록 있는 날: 숫자 크기의 흐린 동그라미
                            if (marked && !isSel)
                              Container(
                                width: 28, height: 28,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(
                                      color: kBlueSky.withOpacity(0.45),
                                      blurRadius: 8,
                                      spreadRadius: 4,
                                    ),
                                  ],
                                  color: kBlueSky.withOpacity(0.25),
                                ),
                              ),
                            Text('$day', style: TextStyle(
                              fontSize: 12,
                              fontWeight: isSel || marked ? FontWeight.w700 : FontWeight.w400,
                              color: isSel ? Colors.white : marked ? kBlueDark : Colors.black87,
                            )),
                          ],
                        ),
                      );
                    },
                  ),
                ]),
              ),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(color: kTimerBg, borderRadius: BorderRadius.circular(16)),
                child: Row(children: [
                  const Icon(Icons.timer_rounded, color: kBlueDark, size: 26),
                  const SizedBox(width: 10),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('오늘 공부 시간', style: TextStyle(fontSize: 11, color: kBlueDark)),
                    Text(timer.display, style: const TextStyle(
                        fontSize: 26, fontWeight: FontWeight.w900, color: kBlueDark, letterSpacing: 2)),
                  ])),
                  Row(children: [
                    _TimerBtn(
                      icon: timer.running ? Icons.pause_rounded : Icons.play_arrow_rounded,
                      onTap: () async {
                        if (timer.running) { timer.pause(); await timer.saveToRecord(); }
                        else { timer.start(); }
                      },
                    ),
                    const SizedBox(width: 8),
                    _TimerBtn(
                      icon: Icons.stop_rounded,
                      onTap: () async { await timer.saveToRecord(); timer.reset(); },
                    ),
                  ]),
                ]),
              ),
            ),

            const SizedBox(height: 10),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Container(
                width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(16)),
                child: hasData
                    ? _RecordCard(
                        record: record!,
                        onEdit: () => _showRecordDialog(context, existing: record),
                        onDelete: () => _confirmDeleteRecord(context, record.date),
                      )
                    : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(_selected ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ElevatedButton(
                          onPressed: () => _showRecordDialog(context),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kBlue, foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7)),
                          child: const Text('기록 추가', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                        ),
                      ]),
              ),
            ),
            const SizedBox(height: 16),
          ]))),
        );
      },
    );
  }

  void _showRecordDialog(BuildContext context, {StudyRecordModel? existing}) {
    final date    = _selected!;
    int? hours    = existing?.studyHours;
    int? minutes  = existing?.studyMinutes;
    int? speech   = existing?.speechChars;
    int? essay    = existing?.essayChars;
    final wpmCtrl  = TextEditingController(text: existing?.wpm?.toString() ?? '');
    final memoCtrl = TextEditingController(text: existing?.memo ?? '');
    final charOpts = [for (int c = 110; c <= 300; c += 10) c];
    final hourOpts = [for (int h = 0; h <= 12; h++) h];
    final minOpts  = [0,5,10,15,20,25,30,35,40,45,50,55];

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text('$date 기록', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
          children: [
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
            _lbl('연설 자수'),
            DropdownButtonFormField<int>(value: speech, hint: const Text('선택'),
                decoration: _inputDeco(null),
                items: charOpts.map((c) => DropdownMenuItem(value: c, child: Text('$c자'))).toList(),
                onChanged: (v) => setS(() => speech = v)),
            const SizedBox(height: 12),
            _lbl('논술 자수'),
            DropdownButtonFormField<int>(value: essay, hint: const Text('선택'),
                decoration: _inputDeco(null),
                items: charOpts.map((c) => DropdownMenuItem(value: c, child: Text('$c자'))).toList(),
                onChanged: (v) => setS(() => essay = v)),
            const SizedBox(height: 12),
            _lbl('타수'),
            TextField(controller: wpmCtrl, keyboardType: TextInputType.number, decoration: _inputDeco('직접 입력')),
            const SizedBox(height: 12),
            _lbl('메모 (선택)'),
            TextField(controller: memoCtrl, maxLines: 2, decoration: _inputDeco('오늘 학습 내용...')),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () async {
              final rec = StudyRecordModel(
                date: date, studyHours: hours, studyMinutes: minutes,
                speechChars: speech, essayChars: essay,
                wpm: int.tryParse(wpmCtrl.text.trim()), memo: memoCtrl.text.trim(),
              );
              if (!rec.hasData) {
                Navigator.pop(ctx);
                if (context.mounted) showDialog(context: context, builder: (c2) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('기록 없음', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  content: const Text('입력된 기록이 없습니다.\n하나 이상의 항목을 입력해 주세요.'),
                  actions: [ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                    onPressed: () => Navigator.pop(c2), child: const Text('확인'))],
                ));
                return;
              }
              await Store.saveRecord(rec);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: const Text('저장')),
        ],
      )),
    );
  }

  void _confirmDeleteRecord(BuildContext context, String date) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('기록 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('$date 의 기록을 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () async { await Store.deleteRecord(date); if (ctx.mounted) Navigator.pop(ctx); },
          child: const Text('삭제')),
      ],
    ));
  }
}

class _TimerBtn extends StatelessWidget {
  final IconData icon; final VoidCallback onTap;
  const _TimerBtn({required this.icon, required this.onTap});
  @override Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(width: 36, height: 36,
        decoration: BoxDecoration(color: kBlueDark.withOpacity(0.15), borderRadius: BorderRadius.circular(10)),
        child: Icon(icon, color: kBlueDark, size: 20)),
  );
}

class _RecordCard extends StatelessWidget {
  final StudyRecordModel record;
  final VoidCallback onEdit, onDelete;
  const _RecordCard({required this.record, required this.onEdit, required this.onDelete});
  String _time() {
    final h = record.studyHours ?? 0;
    final m = record.studyMinutes ?? 0;
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
    Row(mainAxisAlignment: MainAxisAlignment.spaceAround, children: [
      _SI(label: '공부시간', value: _time()),
      _Div(),
      _SI(label: '연설', value: record.speechChars != null ? '${record.speechChars}자' : '-'),
      _Div(),
      _SI(label: '논술', value: record.essayChars  != null ? '${record.essayChars}자'  : '-'),
      _Div(),
      _SI(label: '타수', value: record.wpm         != null ? '${record.wpm}타'          : '-'),
    ]),
    if (record.memo.isNotEmpty) ...[
      const SizedBox(height: 8),
      Container(
        width: double.infinity, padding: const EdgeInsets.all(8),
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
  @override Widget build(BuildContext context) =>
      Container(width: 1, height: 28, color: const Color(0xFFC8D8F8));
}

// ════════════════════════════════════════════════════════
// 그래프
// ════════════════════════════════════════════════════════
class GraphScreen extends StatefulWidget {
  const GraphScreen({super.key});
  @override State<GraphScreen> createState() => _GraphScreenState();
}
class _GraphScreenState extends State<GraphScreen> {
  String _period = 'week', _filter = 'wpm';
  List<_BD> _getData() {
    final recs = Store.getRecordsWithData();
    final now  = DateTime.now();
    double? val(StudyRecordModel r) {
      switch (_filter) {
        case 'wpm':    return r.wpm?.toDouble();
        case 'speech': return r.speechChars?.toDouble();
        case 'essay':  return r.essayChars?.toDouble();
        case 'time':   final t=(r.studyHours??0)*60+(r.studyMinutes??0); return t>0?t.toDouble():null;
        default: return null;
      }
    }
    if (_period == 'week') {
      final mon=now.subtract(Duration(days:now.weekday-1));
      final days=['월','화','수','목','금','토','일'];
      return List.generate(7,(i){
        final d=mon.add(Duration(days:i));
        final k='${d.year}-${d.month.toString().padLeft(2,'0')}-${d.day.toString().padLeft(2,'0')}';
        try{return _BD(label:days[i],value:val(recs.firstWhere((r)=>r.date==k)));}
        catch(_){return _BD(label:days[i],value:null);}
      });
    } else if (_period=='month') {
      return [[1,6],[7,12],[13,18],[19,24],[25,30],[31,31]].map((r){
        final vals=<double>[];
        for(int d=r[0];d<=r[1];d++){
          final k='${now.year}-${now.month.toString().padLeft(2,'0')}-${d.toString().padLeft(2,'0')}';
          try{final v=val(recs.firstWhere((r)=>r.date==k));if(v!=null)vals.add(v);}catch(_){}
        }
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
    final data=_getData();
    final maxVal=data.map((d)=>d.value??0).fold(0.0,(a,b)=>a>b?a:b);
    final chartMax=maxVal>0?maxVal*1.2:300.0;
    return Scaffold(
      backgroundColor: Colors.white,
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
        Expanded(child:data.every((d)=>d.value==null)
          ?const Center(child:Text('기록이 없습니다',style:TextStyle(color:Colors.grey)))
          :Row(crossAxisAlignment:CrossAxisAlignment.end,children:data.map((d){
            final ratio=d.value!=null?d.value!/chartMax:0.0;
            return Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[
              if(d.value!=null)Text(d.value!.round().toString(),style:const TextStyle(fontSize:10,color:kBlue,fontWeight:FontWeight.w700)),
              const SizedBox(height:4),
              Flexible(child:FractionallySizedBox(heightFactor:ratio>0?ratio:0.02,
                child:Container(decoration:BoxDecoration(color:d.value!=null?kBlue:Colors.grey[300],borderRadius:const BorderRadius.vertical(top:Radius.circular(4)))))),
              const SizedBox(height:6),
              Text(d.label,style:const TextStyle(fontSize:10,color:Colors.grey),textAlign:TextAlign.center),
            ])));
          }).toList())),
      ])),
    );
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

// ════════════════════════════════════════════════════════
// 문장 내 약어 추출
// ★ 5번: 탭 이동해도 텍스트 유지 (전역 컨트롤러 사용)
// ════════════════════════════════════════════════════════
final _analyzerCtrl = TextEditingController();
bool _analyzerAnalyzed = false;

class SentenceAnalyzerScreen extends StatefulWidget {
  const SentenceAnalyzerScreen({super.key});
  @override State<SentenceAnalyzerScreen> createState() => _SentenceAnalyzerScreenState();
}
class _SentenceAnalyzerScreenState extends State<SentenceAnalyzerScreen> {
  final _focusNode = FocusNode();

  @override
  void dispose() { _focusNode.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('abbreviations').listenable(),
      builder: (context, box, _) {
        final abbrevs = Store.getAbbreviations();
        final text    = _analyzerCtrl.text;
        final parts   = _analyzerAnalyzed ? analyzeText(text, abbrevs) : <_Span>[];
        final found   = _analyzerAnalyzed
            ? parts.where((p) => p.type != 'normal').map((p) => p.abbr!).toSet().toList()
            : <AbbreviationModel>[];

        return GestureDetector(
          onTap: () => FocusScope.of(context).requestFocus(_focusNode),
          child: Scaffold(
            backgroundColor: Colors.white,
            resizeToAvoidBottomInset: true,
            body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Padding(padding: EdgeInsets.fromLTRB(20,20,20,12),
                  child: Text('문장 내 약어 추출',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              Expanded(child: SingleChildScrollView(
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  TextField(
                    controller: _analyzerCtrl,
                    focusNode: _focusNode,
                    maxLines: 4,
                    onChanged: (_) => setState(() => _analyzerAnalyzed = false),
                    decoration: InputDecoration(
                      hintText: '분석할 문장을 입력하세요...',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                          borderSide: const BorderSide(color: kBlue)),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(width: double.infinity, child: ElevatedButton(
                    onPressed: () => setState(() => _analyzerAnalyzed = true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                    child: const Text('약어 분석하기',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                  )),
                  if (_analyzerAnalyzed && text.isEmpty)
                    const Padding(padding: EdgeInsets.only(top: 16),
                        child: Center(child: Text('문장을 먼저 입력해 주세요.',
                            style: TextStyle(color: Colors.grey)))),
                  if (_analyzerAnalyzed && text.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    Wrap(spacing: 12, runSpacing: 6, children: [
                      _Leg(color: kBlue,    label: '일반 약어'),
                      _Leg(color: kBlueSky, label: '합성약어'),
                      _Leg(color: kPurple,  label: '동시처리약어'),
                      const Text('⭐ 즐겨찾기', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ]),
                    const SizedBox(height: 8),
                    Container(
                      width: double.infinity, padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: const Color(0xFFF8F9FF),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: kBlueLight)),
                      child: SelectableText.rich(TextSpan(children: parts.map((p) {
                        Color color = Colors.black87; FontWeight fw = FontWeight.w400;
                        if (p.type == 'abbr')       { color = kBlue;    fw = FontWeight.w700; }
                        if (p.type == 'composite')  { color = kBlueSky; fw = FontWeight.w700; }
                        if (p.type == 'concurrent') { color = kPurple;  fw = FontWeight.w700; }
                        String display = p.text;
                        if (p.abbr != null && p.abbr!.isFavorite) display = '$display⭐';
                        return TextSpan(text: display,
                            style: TextStyle(fontSize: 16, color: color, fontWeight: fw, height: 1.8));
                      }).toList())),
                    ),
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
                                content: Text('약어 목록이 복사되었습니다'),
                                backgroundColor: kBlue,
                                duration: Duration(seconds: 1)));
                          }),
                      ]),
                      const SizedBox(height: 4),
                      ...found.map((a) => _AbbrTile(abbr: a)),
                    ],
                  ],
                ]),
              )),
            ])),
          ),
        );
      },
    );
  }
}

// ════════════════════════════════════════════════════════
// 약어 검색
// ════════════════════════════════════════════════════════
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override State<SearchScreen> createState() => _SearchScreenState();
}
class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  bool _showFavOnly = false;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('abbreviations').listenable(),
      builder: (context, box, _) {
        final q   = _ctrl.text.trim();
        final all = Store.getAbbreviations();
        // ★ 9번: 띄어쓰기, *, 공백 제거 모두 허용
        var results = q.isEmpty ? all : all.where((a) {
          final qNorm = q.replaceAll(' ', '').replaceAll('*', '');
          final wNorm = a.searchKey.replaceAll(' ', '');
          return wNorm.contains(qNorm) || a.word.contains(q) || a.searchKey.contains(q);
        }).toList();
        if (_showFavOnly) results = results.where((a) => a.isFavorite).toList();

        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12), child: Row(children: [
              const Expanded(child: Text('약어 검색',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
              GestureDetector(
                onTap: () => setState(() => _showFavOnly = !_showFavOnly),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: _showFavOnly ? const Color(0xFFFFD700).withOpacity(0.15) : kBlueLight,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: _showFavOnly ? const Color(0xFFFFD700) : Colors.transparent,
                        width: 1.2)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.star_rounded, size: 16,
                        color: _showFavOnly ? const Color(0xFFFFD700) : Colors.grey),
                    const SizedBox(width: 4),
                    Text('즐겨찾기', style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600,
                        color: _showFavOnly ? const Color(0xFFB8860B) : Colors.grey)),
                  ]),
                ),
              ),
              ElevatedButton.icon(
                onPressed: () => _showEditDialog(context),
                icon: const Icon(Icons.add, size: 16), label: const Text('추가'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue, foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6))),
            ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
              controller: _ctrl, onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: '단어로 검색하세요...',
                prefixIcon: const Icon(Icons.search, color: Colors.grey),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: kBlue)),
              ))),
            const SizedBox(height: 8),
            Expanded(child: results.isEmpty
              ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(_showFavOnly ? '즐겨찾기한 약어가 없습니다' : '약어가 없습니다',
                      style: const TextStyle(color: Colors.grey, fontSize: 14)),
                  if (!_showFavOnly) ...[
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => _showEditDialog(context),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kBlue, side: const BorderSide(color: kBlue),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                      child: const Text('약어 추가하기',
                          style: TextStyle(fontWeight: FontWeight.w700))),
                  ]]))
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final a = results[index];
                    return _AbbrListTile(
                      abbr: a,
                      onFav: () async { await Store.saveAbbreviation(a.copyWith(isFavorite: !a.isFavorite)); },
                      onEdit: () => _showEditDialog(context, existing: a),
                      onDelete: () => _confirmDelete(context, a),
                      onRemind: () => _showReminderDialog(context, a.word, 'word'),
                    );
                  })),
          ])),
        );
      },
    );
  }

  // ★ 4번: 초중종 칸을 하나로 통합 (+ 구분자로 여러 값 입력)
  // ★ 2번: 엔터로 저장
  // ★ 3번: 팝업 뒤 스크롤 가능 (barrierColor 투명도 조정)
  void _showEditDialog(BuildContext context, {AbbreviationModel? existing}) {
    final wordCtrl    = TextEditingController(text: existing?.word.replaceAll('*', ' ') ?? '');
    // 초중종을 하나의 TextField로 통합 (+로 구분)
    final initialCtrl = TextEditingController(
        text: existing?.initial.isNotEmpty == true ? existing!.initial.join('+') : '');
    final medialCtrl  = TextEditingController(
        text: existing?.medial.isNotEmpty == true ? existing!.medial.join('+') : '');
    final finalCtrl   = TextEditingController(
        text: existing?.final_.isNotEmpty == true ? existing!.final_.join('+') : '');
    bool isComposite  = existing?.isComposite  ?? false;
    bool isConcurrent = existing?.isConcurrent ?? false;
    bool isAttached   = existing?.isAttached   ?? false;
    bool isFavorite   = existing?.isFavorite   ?? false;

    // ★ 저장 로직 함수화
    Future<void> doSaveFlow(BuildContext ctx, StateSetter setS) async {
      final rawWord = wordCtrl.text.trim();
      if (rawWord.isEmpty) return;
      final word = encodeWord(rawWord);
      // + 또는 공백으로 분리
      List<String> parseField(String s) =>
          s.split(RegExp(r'[+\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
      final init = parseField(initialCtrl.text);
      final med  = parseField(medialCtrl.text);
      final fin  = parseField(finalCtrl.text);
      final isDup = Store.existsWord(word, excludeId: existing?.id);
      Navigator.pop(ctx);
      if (isDup) {
        final confirm = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('중복 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text('이미 존재합니다. 그래도 저장할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c2, false),
                child: const Text('취소', style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c2, true), child: const Text('저장')),
          ]));
        if (confirm == true) await _doSave(existing, word, init, med, fin, isComposite, isConcurrent, isAttached, isFavorite);
      } else {
        final confirm = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('저장 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: const Text('저장할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c2, false),
                child: const Text('취소', style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c2, true), child: const Text('저장')),
          ]));
        if (confirm == true) await _doSave(existing, word, init, med, fin, isComposite, isConcurrent, isAttached, isFavorite);
      }
    }

    showDialog(
      context: context,
      // ★ 3번: 팝업 뒤 스크롤 가능하게 barrierColor 설정
      barrierColor: Colors.black.withOpacity(0.3),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(existing == null ? '약어 추가' : '약어 수정',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _lbl('단어'),
            TextField(
              controller: wordCtrl,
              decoration: _inputDeco(''),
              // ★ 2번: 마지막 필드에서 엔터 시 저장
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 4),
            Text('※ 띄어쓰기는 저장 시 * 로 자동 변환됩니다',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            // ★ 4번: 초성 - 하나의 칸, +로 구분 입력
            _lbl('초성'),
            TextField(
              controller: initialCtrl,
              decoration: _inputDeco('예: ㄱ  또는  ㄱ+ㄴ'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            _lbl('중성'),
            TextField(
              controller: medialCtrl,
              decoration: _inputDeco('예: ㅜ  또는  ㅜ+ㅣ'),
              textInputAction: TextInputAction.next,
            ),
            const SizedBox(height: 8),
            _lbl('종성'),
            TextField(
              controller: finalCtrl,
              decoration: _inputDeco('예: ㅎ  또는  ㅋ+ㅎ+ㅅ'),
              // ★ 2번: 마지막 필드에서 엔터 누르면 저장
              textInputAction: TextInputAction.done,
              onSubmitted: (_) => doSaveFlow(ctx, setS),
            ),
            const SizedBox(height: 4),
            Text('※ 종성 ㅋ → 자동으로 (ㅋ) 표시  |  여러 값은 + 로 구분',
                style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            const SizedBox(height: 12),
            Wrap(spacing: 0, runSpacing: 4, children: [
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(value: isComposite, activeColor: kBlueSky,
                    onChanged: (v) => setS(() => isComposite = v ?? false)),
                const Text('합성약어', style: TextStyle(fontSize: 13)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(value: isConcurrent, activeColor: kPurple,
                    onChanged: (v) => setS(() => isConcurrent = v ?? false)),
                const Text('동시처리', style: TextStyle(fontSize: 13)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(value: isAttached, activeColor: kBlueDark,
                    onChanged: (v) => setS(() => isAttached = v ?? false)),
                const Text('붙여쓰기', style: TextStyle(fontSize: 13)),
              ]),
              Row(mainAxisSize: MainAxisSize.min, children: [
                Checkbox(value: isFavorite, activeColor: kBlue,
                    onChanged: (v) => setS(() => isFavorite = v ?? false)),
                const Text('즐겨찾기', style: TextStyle(fontSize: 13)),
              ]),
            ]),
          ],
        )),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx),
              child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: kBlue, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: () => doSaveFlow(ctx, setS),
            child: const Text('다음')),
        ],
      )),
    );
  }

  Future<void> _doSave(AbbreviationModel? existing, String word,
      List<String> init, List<String> med, List<String> fin,
      bool isComposite, bool isConcurrent, bool isAttached, bool isFavorite) async {
    await Store.saveAbbreviation(AbbreviationModel(
      id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      word: word, initial: init, medial: med, final_: fin,
      isComposite: isComposite, isConcurrent: isConcurrent,
      isAttached: isAttached, isFavorite: isFavorite));
    // ★ 5번: 약어 등록 후 문장 분석 즉시 재적용
    if (_analyzerAnalyzed) {
      _analyzerAnalyzed = true; // 재분석 트리거
    }
  }

  void _confirmDelete(BuildContext context, AbbreviationModel a) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('삭제 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('"${a.displayWord}" 약어를 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(
            backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () async { await Store.deleteAbbreviation(a.id); if (ctx.mounted) Navigator.pop(ctx); },
            child: const Text('삭제')),
      ]));
  }
}

// ════════════════════════════════════════════════════════
// 문장 등록
// ════════════════════════════════════════════════════════
class SentenceRegisterScreen extends StatefulWidget {
  const SentenceRegisterScreen({super.key});
  @override State<SentenceRegisterScreen> createState() => _SentenceRegisterScreenState();
}
class _SentenceRegisterScreenState extends State<SentenceRegisterScreen> {
  final _ctrl      = TextEditingController();
  final _focusNode = FocusNode();
  @override void dispose() { _ctrl.dispose(); _focusNode.dispose(); super.dispose(); }

  void _save(BuildContext context) {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('저장 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: const Text('저장할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () async {
            await Store.saveSentence(SavedSentenceModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(), text: text,
              createdAt: DateTime.now().toString().substring(0, 10)));
            _ctrl.clear();
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('저장')),
      ]));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('sentences').listenable(),
      builder: (context, box, _) {
        final sentences = Store.getSentences();
        return Scaffold(
          backgroundColor: Colors.white,
          resizeToAvoidBottomInset: true,
          body: SafeArea(child: Column(children: [
            const Padding(padding: EdgeInsets.fromLTRB(20,20,20,12),
                child: Align(alignment: Alignment.centerLeft,
                    child: Text('문장 등록',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)))),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
              TextField(
                controller: _ctrl, focusNode: _focusNode, maxLines: 3,
                decoration: InputDecoration(
                  hintText: '복습할 문장을 입력하세요...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kBlue)),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: () => _save(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: kBlue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: const Text('저장하기',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700)))),
            ])),
            const SizedBox(height: 8),
            Expanded(child: sentences.isEmpty
              ? const Center(child: Text('저장된 문장이 없습니다',
                  style: TextStyle(color: Colors.grey, fontSize: 14)))
              : ListView.builder(
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: sentences.length,
                  itemBuilder: (ctx, i) {
                    final s = sentences[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEEF0F8))),
                      child: Row(children: [
                        Expanded(child: SelectableText(s.text,
                            style: const TextStyle(fontSize: 14, height: 1.6))),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, color: Colors.grey),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (v) async {
                            if (v == 'remind') _showReminderDialog(ctx, s.text, 'sentence');
                            if (v == 'delete') {
                              final ok = await showDialog<bool>(context: ctx, builder: (c2) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('삭제 확인',
                                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                content: const Text('이 문장을 삭제할까요?'),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c2, false),
                                      child: const Text('취소', style: TextStyle(color: Colors.grey))),
                                  ElevatedButton(style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.red, foregroundColor: Colors.white),
                                      onPressed: () => Navigator.pop(c2, true),
                                      child: const Text('삭제')),
                                ]));
                              if (ok == true) await Store.deleteSentence(s.id);
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(value: 'remind', child: Text('🔔 리마인드 설정')),
                            const PopupMenuItem(value: 'delete',
                                child: Text('🗑 삭제', style: TextStyle(color: Colors.red))),
                          ]),
                      ]));
                  })),
          ])),
        );
      });
  }
}

// ════════════════════════════════════════════════════════
// 리마인드
// ════════════════════════════════════════════════════════
class RemindersScreen extends StatelessWidget {
  const RemindersScreen({super.key});
  String _tl(String t) => t == 'word' ? '약어' : t == 'favorite' ? '즐겨찾기' : '문장';
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: Hive.box('reminders').listenable(),
      builder: (context, box, _) {
        final reminders = Store.getReminders();
        return Scaffold(
          backgroundColor: Colors.white,
          body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('리마인드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
              Text('${reminders.length}개', style: const TextStyle(fontSize: 13, color: Colors.grey)),
            ])),
            Expanded(child: reminders.isEmpty
              ? const Center(child: Text('설정된 리마인드가 없습니다',
                  style: TextStyle(color: Colors.grey, fontSize: 14)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: reminders.length,
                  itemBuilder: (ctx, i) {
                    final r = reminders[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: r.active ? Colors.white : const Color(0xFFF8F8F8),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEEF0F8))),
                      child: Row(children: [
                        Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
                          child: Text(_tl(r.type), style: const TextStyle(
                              fontSize: 11, color: kBlue, fontWeight: FontWeight.w700))),
                        const SizedBox(width: 10),
                        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          SelectableText(r.target, style: const TextStyle(
                              fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1),
                          Text('${r.date} · ${r.intervalDays}일 간격${r.repeat ? " · 반복" : ""}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                        ])),
                        Switch(value: r.active, activeColor: kBlue,
                            onChanged: (_) async { await Store.toggleReminder(r.id); }),
                        IconButton(icon: const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
                            onPressed: () async { await Store.deleteReminder(r.id); }),
                      ]));
                  })),
          ])),
        );
      });
  }
}

// ════════════════════════════════════════════════════════
// 공통 위젯 - ★ 1번: 타입 레이블 모두 표시
// ════════════════════════════════════════════════════════
class _AbbrTile extends StatelessWidget {
  final AbbreviationModel abbr;
  const _AbbrTile({required this.abbr});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFEEF0F8))),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (abbr.isAttached) const Text('↙ ',
            style: TextStyle(fontSize: 14, color: kBlueDark, fontWeight: FontWeight.w700)),
        Text(abbr.displayWord, style: TextStyle(
            color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 15)),
        if (abbr.isFavorite) const Text(' ⭐', style: TextStyle(fontSize: 12)),
        // ★ 모든 타입 레이블 표시
        ...abbr.typeLabels.map((label) {
          final color = label == '동시' ? kPurple : label == '합성' ? kBlueSky : kBlueDark;
          final bgColor = label == '동시' ? kPurpleLight : const Color(0xFFE0F4FF);
          return Container(
            margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)));
        }),
      ]),
      const SizedBox(height: 4),
      SelectableText(abbr.strokeDisplay,
          style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]),
  );
}

class _AbbrListTile extends StatelessWidget {
  final AbbreviationModel abbr;
  final VoidCallback? onFav, onEdit, onDelete, onRemind;
  const _AbbrListTile({required this.abbr, this.onFav, this.onEdit, this.onDelete, this.onRemind});
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF0F8))),
    child: Row(children: [
      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (abbr.isAttached) const Text('↙ ',
              style: TextStyle(fontSize: 14, color: kBlueDark, fontWeight: FontWeight.w700)),
          Text(abbr.displayWord, style: TextStyle(
              color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 15)),
          if (abbr.isFavorite) const Text(' ⭐', style: TextStyle(fontSize: 12)),
          // ★ 모든 타입 레이블 표시
          ...abbr.typeLabels.map((label) {
            final color = label == '동시' ? kPurple : label == '합성' ? kBlueSky : kBlueDark;
            final bgColor = label == '동시' ? kPurpleLight : const Color(0xFFE0F4FF);
            return Container(
              margin: const EdgeInsets.only(left: 4),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
              child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)));
          }),
        ]),
        const SizedBox(height: 4),
        SelectableText(abbr.strokeDisplay,
            style: const TextStyle(fontSize: 12, color: Colors.grey)),
      ])),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, color: Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        onSelected: (v) {
          if (v == 'fav'    && onFav    != null) onFav!();
          if (v == 'edit'   && onEdit   != null) onEdit!();
          if (v == 'delete' && onDelete != null) onDelete!();
          if (v == 'remind' && onRemind != null) onRemind!();
        },
        itemBuilder: (_) => [
          PopupMenuItem(value: 'fav',
              child: Text(abbr.isFavorite ? '⭐ 즐겨찾기 해제' : '☆ 즐겨찾기 추가')),
          if (onEdit   != null) const PopupMenuItem(value: 'edit',   child: Text('✏️ 수정')),
          if (onRemind != null) const PopupMenuItem(value: 'remind', child: Text('🔔 리마인드 설정')),
          if (onDelete != null) const PopupMenuItem(value: 'delete',
              child: Text('🗑 삭제', style: TextStyle(color: Colors.red))),
        ]),
    ]),
  );
}

class _Leg extends StatelessWidget {
  final Color color; final String label;
  const _Leg({required this.color, required this.label});
  @override Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 12, height: 12,
        decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 11, color: Colors.grey)),
  ]);
}

void _showReminderDialog(BuildContext context, String target, String type) {
  int interval = 1; bool repeat = false;
  showDialog(context: context, builder: (ctx) => StatefulBuilder(
    builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('리마인드 설정', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        Wrap(spacing: 8, children: [1, 3, 7].map((d) => GestureDetector(
          onTap: () => setS(() => interval = d),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
                color: interval == d ? kBlue : kBlueLight,
                borderRadius: BorderRadius.circular(20)),
            child: Text('$d일', style: TextStyle(
                color: interval == d ? Colors.white : kBlue,
                fontWeight: FontWeight.w700))),
        )).toList()),
        const SizedBox(height: 12),
        Row(children: [
          Checkbox(value: repeat, activeColor: kBlue,
              onChanged: (v) => setS(() => repeat = v ?? false)),
          const Text('반복'),
        ]),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () async {
            final date = DateTime.now().add(Duration(days: interval));
            final ds = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
            await Store.saveReminder(ReminderModel(
              id: DateTime.now().millisecondsSinceEpoch.toString(),
              type: type, target: target, date: ds,
              intervalDays: interval, repeat: repeat));
            if (ctx.mounted) Navigator.pop(ctx);
          },
          child: const Text('설정')),
      ])));
}

Widget _lbl(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 6),
  child: Text(text, style: const TextStyle(
      fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)));

InputDecoration _inputDeco(String? hint) => InputDecoration(
  hintText: hint, isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8),
      borderSide: const BorderSide(color: kBlue)));

extension ListExt<T> on List<T> {
  T? elementAtOrNull(int index) => (index >= 0 && index < length) ? this[index] : null;
}