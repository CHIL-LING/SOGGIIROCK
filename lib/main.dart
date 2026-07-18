import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'dart:async';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('abbreviations');
  await Hive.openBox('studyRecords');
  await Hive.openBox('sentences');
  await Hive.openBox('reminders');
  await Hive.openBox('groups');
  await Hive.openBox('settings'); // 추가
  TtsController.instance._init(); // Hive 열린 후 설정 로드
  runApp(const SoggiApp());
}

const Color kBlue        = Color(0xFF1A6CF6);
const Color kBlueSky     = Color(0xFF398FCC);
const Color kBlueLight   = Color(0xFFE8F0FE);
const Color kBlueDark    = Color(0xFF0F4AB3);
const Color kPurple      = Color(0xFF6a8fa9);
const Color kPurpleLight = Color(0xFFF3EFFE);
const Color kTimerBg     = Color(0xFFBED3F7);

const List<Color> kGroupColors = [
  Color(0xFF1A6CF6), Color(0xFFE53935), Color(0xFF43A047),
  Color(0xFFFB8C00), Color(0xFF8E24AA), Color(0xFF00897B),
  Color(0xFFD81B60), Color(0xFF3949AB), Color(0xFF6D4C41),
  Color(0xFF546E7A), Color(0xFFFFB300), Color(0xFF00ACC1),
];

String encodeWord(String raw) => raw.replaceAll(' ', '*');
String decodeWordForSearch(String word) => word.replaceAll('*', '');

class GroupModel {
  final String id, name;
  final int colorValue;
  GroupModel({required this.id, required this.name, required this.colorValue});
  Color get color => Color(colorValue);
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'colorValue': colorValue};
  factory GroupModel.fromMap(Map m) => GroupModel(
    id: m['id'] as String, name: m['name'] as String, colorValue: m['colorValue'] as int);
}

class AbbreviationModel {
  final String id, word;
  final List<String> initial, medial, final_;
  final bool isComposite, isConcurrent, isAttached, isFavorite;
  final String? groupId;

  AbbreviationModel({
    required this.id, required this.word,
    this.initial = const [], this.medial = const [], this.final_ = const [],
    this.isComposite = false, this.isConcurrent = false,
    this.isAttached = false, this.isFavorite = false,
    this.groupId,
  });

  String get searchKey => decodeWordForSearch(word);
  String get displayWord => word;

  Map<String, dynamic> toMap() => {
    'id': id, 'word': word, 'initial': initial, 'medial': medial, 'final_': final_,
    'isComposite': isComposite, 'isConcurrent': isConcurrent,
    'isAttached': isAttached, 'isFavorite': isFavorite, 'groupId': groupId,
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
    groupId: m['groupId'] as String?,
  );

  AbbreviationModel copyWith({
    String? word, List<String>? initial, List<String>? medial, List<String>? final_,
    bool? isComposite, bool? isConcurrent, bool? isAttached, bool? isFavorite,
    String? groupId, bool clearGroup = false,
  }) => AbbreviationModel(
    id: id, word: word ?? this.word, initial: initial ?? this.initial,
    medial: medial ?? this.medial, final_: final_ ?? this.final_,
    isComposite: isComposite ?? this.isComposite, isConcurrent: isConcurrent ?? this.isConcurrent,
    isAttached: isAttached ?? this.isAttached, isFavorite: isFavorite ?? this.isFavorite,
    groupId: clearGroup ? null : (groupId ?? this.groupId),
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
  static Box get _gr => Hive.box('groups');

  static List<GroupModel> getGroups() =>
      _gr.values.map((e) => GroupModel.fromMap(Map.from(e as Map))).toList();
  static Future<void> saveGroup(GroupModel g) => _gr.put(g.id, g.toMap());
  static Future<void> deleteGroup(String id) => _gr.delete(id);
  static GroupModel? findGroup(String id) {
    try { return getGroups().firstWhere((g) => g.id == id); } catch (_) { return null; }
  }

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

// ── TTS 컨트롤러 ─────────────────────────────────────────────────────
class TtsController extends ChangeNotifier {
  static final TtsController _instance = TtsController._();
  static TtsController get instance => _instance;
 TtsController._() { _initBasic(); }

  void _initBasic() {
    _tts.setLanguage('ko-KR');
    _tts.setSpeechRate(speed);
    _tts.setVolume(volume);
    _tts.setPitch(pitch);
  }

  final FlutterTts _tts = FlutterTts();
  bool _playing = false;
  bool get playing => _playing;

  double speed  = 0.5;
  double volume = 1.0;
  double pitch  = 1.0;
  double pauseMs = 250;

  int _wordStart = -1, _wordEnd = -1;
  int get wordStart => _wordStart;
  int get wordEnd   => _wordEnd;

  int _playToken = 0;
  List<MapEntry<int, String>> _words = [];
  int _currentIndex = 0;
  String _fullText = '';

  // 진행률 (0.0 ~ 1.0)
  double get progress => _words.isEmpty ? 0 : _currentIndex / _words.length;
  int get currentWordIndex => _currentIndex;
  int get totalWords => _words.length;

  // 경과 시간 / CPM
  Stopwatch _stopwatch = Stopwatch();
  Duration get elapsed => _stopwatch.elapsed;
  int get charsReadSoFar {
    if (_words.isEmpty || _currentIndex == 0) return 0;
    final readCount = _currentIndex.clamp(0, _words.length);
    int total = 0;
    for (int i = 0; i < readCount; i++) {
      total += _words[i].value.length;
    }
    return total;
  }
  double get cpm {
    final mins = _stopwatch.elapsed.inMilliseconds / 60000.0;
    if (mins <= 0.0005) return 0;
    return charsReadSoFar / mins;
  }

void _init() async {
    try {
      final box = Hive.box('settings');
      speed   = (box.get('tts_speed',   defaultValue: 0.5)   as num).toDouble();
      volume  = (box.get('tts_volume',  defaultValue: 1.0)   as num).toDouble();
      pitch   = (box.get('tts_pitch',   defaultValue: 1.0)   as num).toDouble();
      pauseMs = (box.get('tts_pause',   defaultValue: 250.0) as num).toDouble();
      await _tts.setSpeechRate(speed);
      await _tts.setVolume(volume);
      await _tts.setPitch(pitch);
      notifyListeners();
    } catch (_) {}
  }
  List<MapEntry<int, String>> _splitWithOffsets(String text) {
    final result = <MapEntry<int, String>>[];
    final regex = RegExp(r'\S+');
    for (final m in regex.allMatches(text)) {
      result.add(MapEntry(m.start, m.group(0)!));
    }
    return result;
  }

  // text: 전체 문장, startIndex: 시작할 단어 인덱스 (기본 0 = 처음부터)
  Future<void> speak(String text, {int startIndex = 0}) async {
    await stop();
    final myToken = ++_playToken;
    _fullText = text;
    _words = _splitWithOffsets(text);
    if (_words.isEmpty) return;

    _currentIndex = startIndex.clamp(0, _words.length - 1);
    _playing = true;
    _stopwatch
      ..reset()
      ..start();
    notifyListeners();

    await _tts.setSpeechRate(speed);
    await _tts.setVolume(volume);
    await _tts.setPitch(pitch);

    for (int i = _currentIndex; i < _words.length; i++) {
      if (myToken != _playToken) return;

      _currentIndex = i;
      final start = _words[i].key;
      final word = _words[i].value;
      final end = start + word.length;
      _wordStart = start; _wordEnd = end; notifyListeners();

      final completer = Completer<void>();
      _tts.setCompletionHandler(() { if (!completer.isCompleted) completer.complete(); });
      _tts.setCancelHandler(() { if (!completer.isCompleted) completer.complete(); });
      _tts.setErrorHandler((_) { if (!completer.isCompleted) completer.complete(); });

      await _tts.speak(word);
      await completer.future;

      if (myToken != _playToken) return;

      if (i < _words.length - 1 && pauseMs > 0) {
        await Future.delayed(Duration(milliseconds: pauseMs.round()));
      }
    }

    if (myToken == _playToken) {
      _currentIndex = _words.length;
      _playing = false; _wordStart = -1; _wordEnd = -1;
      _stopwatch.stop();
      notifyListeners();
    }
  }

  // 특정 글자 오프셋이 속한 단어부터 재생 (텍스트 탭 시 사용)
  Future<void> seekAndPlay(int charOffset) async {
    if (_words.isEmpty) {
      // 아직 한 번도 재생 안 한 상태면 fullText 기준으로 단어 분리만 먼저 함
      _words = _splitWithOffsets(_fullText);
    }
    int idx = _words.indexWhere((w) => charOffset >= w.key && charOffset < w.key + w.value.length);
    if (idx == -1) {
      idx = _words.indexWhere((w) => w.key >= charOffset);
      if (idx == -1) idx = _words.isEmpty ? 0 : _words.length - 1;
    }
    await speak(_fullText, startIndex: idx);
  }

  // 진행률(0.0~1.0)로 이동 후 재생 (진행바 드래그용)
  Future<void> seekToProgress(double ratio) async {
    if (_fullText.isEmpty) return;
    final words = _words.isEmpty ? _splitWithOffsets(_fullText) : _words;
    if (words.isEmpty) return;
    final idx = (ratio * words.length).floor().clamp(0, words.length - 1);
    await speak(_fullText, startIndex: idx);
  }

  Future<void> stop() async {
    _playToken++;
    await _tts.stop();
    _playing = false; _wordStart = -1; _wordEnd = -1;
    _stopwatch.stop();
    notifyListeners();
  }

  // 정지하되 진행 위치는 유지 (이어듣기용 일시정지)
  Future<void> pause() async {
    _playToken++;
    await _tts.stop();
    _playing = false;
    _stopwatch.stop();
    notifyListeners();
  }

  Future<void> resume() async {
    if (_fullText.isEmpty) return;
    await speak(_fullText, startIndex: _currentIndex);
  }

  void setText(String text) {
    if (_fullText != text) {
      _fullText = text;
      _words = _splitWithOffsets(text);
      _currentIndex = 0;
      _wordStart = -1; _wordEnd = -1;
      _stopwatch.reset();
      notifyListeners();
    }
  }
// 목표 CPM(공백 제외)과 포즈 시간에 맞춰 speechRate 자동 추정
  // 보정값: rate=0.5일 때 글자당 실측 약 0.045초 (한국어 기준 경험치)
  void autoTuneSpeed({required double targetCpm, double? pauseMsOverride}) {
    if (targetCpm <= 0) return;

    // 텍스트가 아직 없으면 words 기준이 없으므로 단어수 추정 불가 → 단순 속도만 조정
    final words = _words.isEmpty ? _splitWithOffsets(_fullText) : _words;
    final totalCharsNoSpace = words.isEmpty
        ? 100 // 텍스트 없을 때 기본값으로 100자 가정
        : words.fold<int>(0, (sum, w) => sum + w.value.length);
    final pauseCount = words.length > 1 ? words.length - 1 : 0;
    final effectivePauseMs = pauseMsOverride ?? pauseMs;

    // 목표 총 시간(초)
    final targetTotalSeconds = totalCharsNoSpace / targetCpm * 60.0;
    // 포즈로 쓰이는 시간(초)
    final pauseTotalSeconds = (pauseCount * effectivePauseMs) / 1000.0;
    // 실제 발화에 써야 할 시간(초)
    final speechTimeBudget = (targetTotalSeconds - pauseTotalSeconds).clamp(0.5, double.infinity);

    // 기준: rate=0.5 → 글자당 0.045초 (실측 보정값)
    // rate와 발화시간은 반비례: rate = 0.5 * (기준시간 / 필요시간)
    const double baseRate = 0.5;
    const double baseSecPerChar = 0.045;
    final neededSecPerChar = speechTimeBudget / totalCharsNoSpace;
    double estimatedRate = baseRate * (baseSecPerChar / neededSecPerChar);

    speed = estimatedRate.clamp(0.1, 1.0);
    if (pauseMsOverride != null) pauseMs = pauseMsOverride;
    notifyListeners();
  }
  Future<void> applySettings() async {
    await _tts.setSpeechRate(speed);
    await _tts.setVolume(volume);
    await _tts.setPitch(pitch);
    // Hive에 저장
    final box = Hive.box('settings');
    await box.put('tts_speed', speed);
    await box.put('tts_volume', volume);
    await box.put('tts_pitch', pitch);
    await box.put('tts_pause', pauseMs);
  }
}
// ── TTS 컨트롤 바 ────────────────────────────────────────────────────
class TtsControlBar extends StatefulWidget {
  final String text;
  const TtsControlBar({super.key, required this.text});
  @override State<TtsControlBar> createState() => _TtsControlBarState();
}
class _TtsControlBarState extends State<TtsControlBar> {
  bool _showSettings = false;
  Timer? _uiTimer;
 final _targetCpmCtrl = TextEditingController(text: '160');
  @override
  void initState() {
    super.initState();
    TtsController.instance.setText(widget.text);
    TtsController.instance.addListener(_rebuild);
    _uiTimer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted && TtsController.instance.playing) setState(() {});
    });
  }

  @override
  void didUpdateWidget(covariant TtsControlBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) {
      TtsController.instance.setText(widget.text);
    }
  }

  @override
  void dispose() {
    TtsController.instance.removeListener(_rebuild);
    _uiTimer?.cancel();
    _targetCpmCtrl.dispose();
    super.dispose();
  }

  void _rebuild() { if (mounted) setState(() {}); }

  String _fmtTime(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final tts = TtsController.instance;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: kBlueLight,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: kBlue.withOpacity(0.2))),
        child: Column(children: [
          Row(children: [
            GestureDetector(
              onTap: () async {
                if (tts.playing) {
                  await tts.pause();
                } else if (tts.currentWordIndex > 0 && tts.currentWordIndex < tts.totalWords) {
                  await tts.resume();
                } else {
                  await tts.speak(widget.text);
                }
              },
              child: Container(
                width: 40, height: 40,
                decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(10)),
                child: Icon(
                  tts.playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                  color: Colors.white, size: 22)),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () async {
                if (tts.totalWords > 0) await tts.speak(widget.text, startIndex: 0);
              },
              child: Container(
                width: 36, height: 36,
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: kBlue.withOpacity(0.3))),
                child: const Icon(Icons.replay_rounded, color: kBlue, size: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                tts.playing ? '읽는 중 · 단어를 누르면 그 지점부터 재생' : '단어를 탭하면 거기서부터 재생돼요',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
                    color: tts.playing ? kBlue : Colors.grey),
                maxLines: 1, overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Row(children: [
                Icon(Icons.timer_outlined, size: 12, color: kBlueDark),
                const SizedBox(width: 3),
                Text(_fmtTime(tts.elapsed),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kBlueDark)),
                const SizedBox(width: 10),
                const Icon(Icons.speed_rounded, size: 12, color: kBlueDark),
                const SizedBox(width: 3),
                Text('${tts.cpm.round()} 자/분',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: kBlueDark)),
              ]),
            ])),
            GestureDetector(
              onTap: () => setState(() => _showSettings = !_showSettings),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _showSettings ? kBlue : Colors.white,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: kBlue.withOpacity(0.3))),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.tune_rounded, size: 15,
                      color: _showSettings ? Colors.white : kBlue),
                  const SizedBox(width: 4),
                  Text('설정', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: _showSettings ? Colors.white : kBlue)),
                ])),
            ),
          ]),
          const SizedBox(height: 8),
          LayoutBuilder(builder: (context, constraints) {
            final barWidth = constraints.maxWidth;
            return GestureDetector(
              onTapDown: (d) async {
                final ratio = (d.localPosition.dx / barWidth).clamp(0.0, 1.0);
                await tts.seekToProgress(ratio);
              },
              onHorizontalDragUpdate: (d) async {
                final ratio = (d.localPosition.dx / barWidth).clamp(0.0, 1.0);
                await tts.seekToProgress(ratio);
              },
              child: Container(
                height: 18,
                alignment: Alignment.center,
                child: Stack(children: [
                  Container(height: 6,
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(3))),
                  FractionallySizedBox(
                    widthFactor: tts.progress.clamp(0.0, 1.0),
                    child: Container(height: 6,
                      decoration: BoxDecoration(color: kBlue, borderRadius: BorderRadius.circular(3))),
                  ),
                ]),
              ),
            );
          }),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${tts.currentWordIndex}/${tts.totalWords} 단어',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
            Text('${(tts.progress * 100).round()}%',
                style: const TextStyle(fontSize: 10, color: Colors.grey)),
          ]),
        ])),
      if (_showSettings) ...[
        const SizedBox(height: 6),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFE0E8FF))),
          child: Column(children: [
            _SliderRow(icon: Icons.speed_rounded, label: '속도',
              value: tts.speed, min: 0.1, max: 1.0, divisions: 9,
              displayText: _speedLabel(tts.speed),
              onChanged: (v) async { tts.speed = v; await tts.applySettings(); setState(() {}); }),
            const SizedBox(height: 10),
            _SliderRow(icon: Icons.volume_up_rounded, label: '음량',
              value: tts.volume, min: 0.0, max: 1.0, divisions: 10,
              displayText: '${(tts.volume * 100).round()}%',
              onChanged: (v) async { tts.volume = v; await tts.applySettings(); setState(() {}); }),
            const SizedBox(height: 10),
            _SliderRow(icon: Icons.music_note_rounded, label: '음높이',
              value: tts.pitch, min: 0.5, max: 2.0, divisions: 15,
              displayText: tts.pitch.toStringAsFixed(1),
              onChanged: (v) async { tts.pitch = v; await tts.applySettings(); setState(() {}); }),
            const SizedBox(height: 10),
            _SliderRow(icon: Icons.space_bar_rounded, label: '포즈',
              value: tts.pauseMs, min: 0, max: 1000, divisions: 20,
              displayText: '${tts.pauseMs.round()}ms',
              onChanged: (v) { tts.pauseMs = v; setState(() {}); }),
          const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(10)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.auto_awesome_rounded, size: 14, color: kBlueDark),
                  const SizedBox(width: 4),
                  const Text('목표 타수에 맞춰 속도 자동 설정',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: kBlueDark)),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  Expanded(
                    child: TextField(
                      controller: _targetCpmCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        suffixText: '자/분',
                        suffixStyle: const TextStyle(fontSize: 11, color: Colors.grey),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        filled: true, fillColor: Colors.white,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () {
                      final target = double.tryParse(_targetCpmCtrl.text.trim());
                      if (target == null || target <= 0) return;
                      tts.autoTuneSpeed(targetCpm: target);
                      setState(() {});
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: kBlue, foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                    child: const Text('적용', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
                ]),
                const SizedBox(height: 4),
                Text('현재 포즈(${tts.pauseMs.round()}ms) 기준으로 속도를 계산해요',
                    style: const TextStyle(fontSize: 10, color: Colors.grey)),
              ]),
            ),
          ])),
      ],
    ]);
  }

  String _speedLabel(double v) {
    if (v <= 0.2) return '매우 느림';
    if (v <= 0.4) return '느림';
    if (v <= 0.6) return '보통';
    if (v <= 0.8) return '빠름';
    return '매우 빠름';
  }
}
class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label, displayText;
  final double value, min, max;
  final int divisions;
  final ValueChanged<double> onChanged;
  const _SliderRow({required this.icon, required this.label, required this.displayText,
    required this.value, required this.min, required this.max,
    required this.divisions, required this.onChanged});
  @override
  Widget build(BuildContext context) => Row(children: [
    Icon(icon, size: 16, color: kBlue),
    const SizedBox(width: 6),
    SizedBox(width: 40, child: Text(label,
        style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600))),
    Expanded(child: SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: kBlue, inactiveTrackColor: kBlueLight,
        thumbColor: kBlue, overlayColor: kBlue.withOpacity(0.12)),
      child: Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged))),
    SizedBox(width: 52, child: Text(displayText,
        style: const TextStyle(fontSize: 11, color: kBlueDark, fontWeight: FontWeight.w700),
        textAlign: TextAlign.right)),
  ]);
}

// ── 문장 분석 ─────────────────────────────────────────────────────────
class _Span {
  final String text, type;
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
          String t = 'abbr';
          if (a.isConcurrent) t = 'concurrent';
          else if (a.isComposite) t = 'composite';
          next.add(_Span(text: a.word, type: t, abbr: a));
        }
      }
    }
    parts = next;
  }
  return parts.map((p) {
    if (p.type == 'normal') return _Span(text: p.text.replaceAll('*', ' '), type: 'normal');
    return _Span(text: p.text.replaceAll('*', ' '), type: p.type, abbr: p.abbr);
  }).toList();
}

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
      const SizedBox(height: 4),
      Text('🤘기록도 ROCK이다.🤘', style: TextStyle(fontSize: 12, color: Colors.white.withOpacity(0.55))),      const SizedBox(height: 40),
      SizedBox(width: 40, child: LinearProgressIndicator(
          backgroundColor: Colors.white.withOpacity(0.3), color: Colors.white,
          borderRadius: BorderRadius.circular(4))),
    ])));
}

class MainShell extends StatefulWidget {
  const MainShell({super.key});
  @override State<MainShell> createState() => _MainShellState();
}
class _MainShellState extends State<MainShell> {
  int _idx = 0;
final _screens = const [
    HomeScreen(), SentenceAnalyzerScreen(), SearchScreen(),
    SentenceRegisterScreen(), RemindersScreen(), QuizScreen(),
  ];
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTodayReminders());
  }
void _checkTodayReminders() {
    final today = _todayStr();

    final settingsBox = Hive.box('settings');
    final dismissedKey = '_dismissed_$today';
    if (settingsBox.get(dismissedKey) == true) return;

    final reminders = Store.getReminders().where((r) => r.active && r.date == today).toList();
    if (reminders.isEmpty) return;
    final abbrevs = Store.getAbbreviations();
    for (final r in reminders) {
      if (r.repeat) {
        final next = DateTime.now().add(Duration(days: r.intervalDays));
        final ds = '${next.year}-${next.month.toString().padLeft(2,'0')}-${next.day.toString().padLeft(2,'0')}';
        Store.saveReminder(ReminderModel(id: r.id, type: r.type, target: r.target, date: ds,
          intervalDays: r.intervalDays, repeat: r.repeat, active: r.active));
      }
    }
    showDialog(context: context, barrierDismissible: true,
        builder: (_) => _TodayReminderDialog(reminders: reminders, abbrevs: abbrevs, todayKey: today));
  }
  String _todayStr() {
    final now = DateTime.now();
    final base = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
    return '${base.year}-${base.month.toString().padLeft(2,'0')}-${base.day.toString().padLeft(2,'0')}';
  }
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
          BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.quiz_rounded)), label: '테스트'),
        ]))));
}

class _TodayReminderDialog extends StatefulWidget {
  final List<ReminderModel> reminders;
  final List<AbbreviationModel> abbrevs;
  final String todayKey;
  const _TodayReminderDialog({required this.reminders, required this.abbrevs, required this.todayKey});
  @override State<_TodayReminderDialog> createState() => _TodayReminderDialogState();
}
class _TodayReminderDialogState extends State<_TodayReminderDialog> {
  final _memoCtrl = TextEditingController();
  int _selectedIdx = 0;
  @override void dispose() { _memoCtrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final sw = MediaQuery.of(context).size.width;
    final sh = MediaQuery.of(context).size.height;
    final isWide = sw > 600;
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.all(16),
      child: SizedBox(width: isWide ? sw * 0.85 : sw - 32, height: sh * 0.75,
        child: Column(children: [
          Container(padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
            decoration: BoxDecoration(color: kBlue, borderRadius: const BorderRadius.vertical(top: Radius.circular(20))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              Row(children: [
                const Icon(Icons.notifications_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text('오늘의 리마인드 (${widget.reminders.length}개)',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15))),
                IconButton(icon: const Icon(Icons.close, color: Colors.white, size: 20),
                    onPressed: () => Navigator.pop(context)),
              ]),
              TextButton.icon(
                onPressed: () {
                  Hive.box('settings').put('_dismissed_${widget.todayKey}', true);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.visibility_off_rounded, size: 14, color: Colors.white70),
                label: const Text('오늘 다시 보지 않음',
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600)),
                style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
              ),
            ])),
          Expanded(child: isWide
            ? Row(children: [
                SizedBox(width: sw * 0.38, child: _reminderList()),
                Container(width: 1, color: const Color(0xFFEEF0F8)),
                Expanded(child: _memoPanel()),
              ])
            : Column(children: [
                SizedBox(height: sh * 0.3, child: _reminderList()),
                Container(height: 1, color: const Color(0xFFEEF0F8)),
                Expanded(child: _memoPanel()),
              ])),
        ])));
  }
  Widget _reminderList() => ListView.builder(
    padding: const EdgeInsets.all(12), itemCount: widget.reminders.length,
    itemBuilder: (ctx, i) {
      final r = widget.reminders[i];
      final isSelected = i == _selectedIdx;
      final isWord = r.type == 'word';
      Widget content;
      if (isWord) {
        content = Text(r.target.replaceAll('*', ' '),
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600,
                color: isSelected ? kBlue : Colors.black87));
      } else {
        final parts = analyzeText(r.target, widget.abbrevs);
        content = Text.rich(TextSpan(children: parts.map((p) {
          Color color = Colors.black87; FontWeight fw = FontWeight.w400;
          if (p.type == 'abbr')       { color = kBlue;    fw = FontWeight.w700; }
          if (p.type == 'composite')  { color = kBlueSky; fw = FontWeight.w700; }
          if (p.type == 'concurrent') { color = kPurple;  fw = FontWeight.w700; }
          return TextSpan(text: p.text, style: TextStyle(fontSize: 13, color: color, fontWeight: fw, height: 1.6));
        }).toList()));
      }
      return GestureDetector(
        onTap: () => setState(() => _selectedIdx = i),
        child: Container(margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: isSelected ? kBlueLight : Colors.white, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isSelected ? kBlue : const Color(0xFFEEF0F8), width: isSelected ? 1.5 : 1)),
          child: Row(children: [
            Container(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(color: isWord ? kBlue.withOpacity(0.1) : kPurple.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6)),
              child: Text(isWord ? '약어' : '문장',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: isWord ? kBlue : kPurple))),
            const SizedBox(width: 8),
            Expanded(child: content),
          ])));
    });
  Widget _memoPanel() => Padding(padding: const EdgeInsets.all(12),
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('테스트 메모장', style: TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
      const SizedBox(height: 6),
      Expanded(child: TextField(controller: _memoCtrl, maxLines: null, expands: true,
        textAlignVertical: TextAlignVertical.top,
        decoration: InputDecoration(hintText: '여기에 직접 써보세요...',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBlue)),
          contentPadding: const EdgeInsets.all(12)))),
      const SizedBox(height: 8),
      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
        TextButton(onPressed: () => setState(() => _memoCtrl.clear()),
          child: const Text('지우기', style: TextStyle(color: Colors.grey, fontSize: 12))),
      ]),
    ]));
}

final _analyzerCtrl     = TextEditingController();
bool  _analyzerAnalyzed = false;
final _searchScrollCtrl = ScrollController();

Widget _actionChip(IconData icon, String label, Color color) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20),
      border: Border.all(color: color.withOpacity(0.3))),
  child: Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 13, color: color),
    const SizedBox(width: 3),
    Text(label, style: TextStyle(fontSize: 11, color: color, fontWeight: FontWeight.w600)),
  ]));

Widget _lbl(String text) => Padding(padding: const EdgeInsets.only(bottom: 6),
  child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)));

InputDecoration _inputDeco(String? hint) => InputDecoration(
  hintText: hint, isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBlue)));

extension ListExt<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
  T? elementAtOrNull(int index) => (index >= 0 && index < length) ? this[index] : null;
}

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  late DateTime _month; String? _selected;
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
              GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
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
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
              child: Container(width: double.infinity, padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(16)),
                child: hasData
                  ? _RecordCard(record: record!,
                      onEdit: () => _showRecordDialog(context, existing: record),
                      onDelete: () => _confirmDeleteRecord(context, record.date))
                  : Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                      Text(_selected ?? '', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ElevatedButton(onPressed: () => _showRecordDialog(context),
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
          TextField(controller: memoCtrl, maxLines: 10, decoration: _inputDeco('1. '),
            onChanged: (val) {
              final lines = val.split('\n');
              if (lines.length >= 2) {
                final prev = lines[lines.length - 2];
                final match = RegExp(r'^(\d+)\.\s').firstMatch(prev);
                if (match != null && lines.last.isEmpty) {
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
            }, child: const Text('저장')),
        ])));
  }

  void _confirmDeleteRecord(BuildContext context, String date) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('기록 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('$date 의 기록을 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
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
       Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            _PB(label:'타수',value:'wpm',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),const SizedBox(width:6),
            _PB(label:'연설',value:'speech',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),const SizedBox(width:6),
            _PB(label:'논술',value:'essay',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),const SizedBox(width:6),
            _PB(label:'시간',value:'time',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),
          ]),
          const SizedBox(height:8),
          Row(children: [
            _PB(label:'1주',value:'week',sel:_period,onTap:(v)=>setState(()=>_period=v)),const SizedBox(width:6),
            _PB(label:'1달',value:'month',sel:_period,onTap:(v)=>setState(()=>_period=v)),const SizedBox(width:6),
            _PB(label:'1년',value:'year',sel:_period,onTap:(v)=>setState(()=>_period=v)),
          ]),
        ]),
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

// ── 약어확인 탭 (TTS 포함) ───────────────────────────────────────────
class SentenceAnalyzerScreen extends StatefulWidget {
  const SentenceAnalyzerScreen({super.key});
  @override State<SentenceAnalyzerScreen> createState() => _SentenceAnalyzerScreenState();
}
class _SentenceAnalyzerScreenState extends State<SentenceAnalyzerScreen> {
  final _focusNode = FocusNode();
  AbbreviationModel? _selectedAbbr;
  OverlayEntry? _tooltipOverlay;
  final Set<String> _gridSelected = {};
  bool _gridSelectMode = false;

  void _toggleGridSelectMode() => setState(() { _gridSelectMode = !_gridSelectMode; _gridSelected.clear(); });
  void _toggleGridSelect(String id) => setState(() {
    if (_gridSelected.contains(id)) _gridSelected.remove(id); else _gridSelected.add(id);
  });
  void _bulkGridFav(List<AbbreviationModel> found) async {
    for (final a in found.where((a) => _gridSelected.contains(a.id)))
      await Store.saveAbbreviation(a.copyWith(isFavorite: true));
    setState(() { _gridSelected.clear(); _gridSelectMode = false; });
  }
  void _bulkGridRemind(BuildContext context, List<AbbreviationModel> found) {
    final targets = found.where((a) => _gridSelected.contains(a.id)).map((a) => a.word).toList();
    _showBulkReminderDialog(context, targets, 'word');
    setState(() { _gridSelected.clear(); _gridSelectMode = false; });
  }
  void _bulkGridCopy(List<AbbreviationModel> found) {
    final text = found.where((a) => _gridSelected.contains(a.id))
        .map((a) => a.displayWord.replaceAll('*', ' ')).join(', ');
    Clipboard.setData(ClipboardData(text: text));
    setState(() { _gridSelected.clear(); _gridSelectMode = false; });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _tooltipOverlay?.remove();
    TtsController.instance.stop();
    super.dispose();
  }

  void _showAbbrTooltip(BuildContext context, AbbreviationModel abbr, Offset position) {
    _tooltipOverlay?.remove(); _tooltipOverlay = null;
    final screenW = MediaQuery.of(context).size.width;
    final overlay = Overlay.of(context);
    final group = abbr.groupId != null ? Store.findGroup(abbr.groupId!) : null;
    _tooltipOverlay = OverlayEntry(builder: (_) => Stack(children: [
      Positioned.fill(child: GestureDetector(onTap: _closeTooltip, behavior: HitTestBehavior.translucent,
          child: const SizedBox.expand())),
      Positioned(
        left: position.dx.clamp(8.0, screenW - 208.0),
        top: (position.dy - 76).clamp(8.0, double.infinity),
        child: Material(color: Colors.transparent, child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          constraints: const BoxConstraints(maxWidth: 200),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFE0E8FF)),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.12), blurRadius: 12, offset: const Offset(0,3))]),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(abbr.displayWord.replaceAll('*', ' '), style: TextStyle(color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 13)),
              if (abbr.isFavorite) const Text(' ⭐', style: TextStyle(fontSize: 10)),
              ...abbr.typeLabels.map((l) {
                final c = l == '동시' ? kPurple : l == '합성' ? kBlueSky : kBlueDark;
                return Container(margin: const EdgeInsets.only(left: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(l, style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w700)));
              }),
              if (group != null) Container(margin: const EdgeInsets.only(left: 3),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: group.color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(group.name, style: TextStyle(fontSize: 9, color: group.color, fontWeight: FontWeight.w700))),
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
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () {
            _analyzerCtrl.clear(); _analyzerAnalyzed = false;
            TtsController.instance.stop();
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
        final plainText = parts.map((p) => p.text).join();

        return GestureDetector(
          onTap: () { _closeTooltip(); FocusScope.of(context).requestFocus(_focusNode); },
          child: Scaffold(backgroundColor: Colors.white, resizeToAvoidBottomInset: true,
            body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
                child: Row(children: [
                  const Expanded(child: Text('문장 내 약어 추출',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                  if (_analyzerCtrl.text.isNotEmpty)
                    GestureDetector(onTap: () => _confirmClear(context),
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
                    decoration: InputDecoration(hintText: '분석할 문장을 입력하세요...',
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
                      child: TtsAnalysisTextView(
                        parts: parts,
                        selectedAbbr: _selectedAbbr,
                        onAbbrTap: (abbr, pos) {
                          if (_selectedAbbr?.id == abbr.id) _closeTooltip();
                          else _showAbbrTooltip(context, abbr, pos);
                        },
                      )),
                    const SizedBox(height: 10),
                    // ── TTS 컨트롤 바 ──
                    TtsControlBar(text: plainText),
                    if (found.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text('사용된 약어 (${found.length}개)',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey)),
                        Row(children: [
                          if (_gridSelectMode) ...[
                            GestureDetector(onTap: () => _bulkGridFav(found),
                              child: _actionChip(Icons.star_rounded, '즐겨찾기', const Color(0xFFFFAA00))),
                            const SizedBox(width: 4),
                            GestureDetector(onTap: () => _bulkGridRemind(context, found),
                              child: _actionChip(Icons.notifications_rounded, '리마인드', kBlue)),
                            const SizedBox(width: 4),
                            GestureDetector(onTap: () => _bulkGridCopy(found),
                              child: _actionChip(Icons.copy, '복사', Colors.grey)),
                            const SizedBox(width: 4),
                            GestureDetector(onTap: _toggleGridSelectMode,
                              child: _actionChip(Icons.close, '취소', Colors.grey)),
                          ] else ...[
                            GestureDetector(onTap: _toggleGridSelectMode,
                              child: Container(padding: const EdgeInsets.all(6),
                                child: const Icon(Icons.checklist_rounded, size: 16, color: Colors.grey))),
                            IconButton(icon: const Icon(Icons.copy, size: 16, color: Colors.grey),
                              onPressed: () {
                                final t = found.map((a) => '${a.displayWord}: ${a.strokeDisplay}').join('\n');
                                Clipboard.setData(ClipboardData(text: t));
                                ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                    content: Text('약어 목록이 복사되었습니다'), backgroundColor: kBlue,
                                    duration: Duration(seconds: 1)));
                              }),
                          ],
                        ]),
                      ]),
                      if (_gridSelectMode)
                        Padding(padding: const EdgeInsets.only(bottom: 4),
                          child: Row(children: [
                            Text('${_gridSelected.length}개 선택됨',
                                style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.w600)),
                            const SizedBox(width: 12),
                            GestureDetector(
                              onTap: () => setState(() {
                                if (_gridSelected.length == found.length) _gridSelected.clear();
                                else _gridSelected.addAll(found.map((a) => a.id));
                              }),
                              child: Text(_gridSelected.length == found.length ? '전체 해제' : '전체 선택',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
                          ])),
                      GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6, childAspectRatio: 1.6),
                        itemCount: found.length,
                        itemBuilder: (ctx, i) {
                          final a = found[i];
                          final isSelected = _gridSelected.contains(a.id);
                          final group = a.groupId != null ? Store.findGroup(a.groupId!) : null;
                          return GestureDetector(
                            onTap: _gridSelectMode ? () => _toggleGridSelect(a.id) : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                              decoration: BoxDecoration(
                                color: isSelected ? kBlueLight : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isSelected ? kBlue : const Color(0xFFEEF0F8),
                                    width: isSelected ? 1.5 : 1)),
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                Row(children: [
                                  if (_gridSelectMode) ...[
                                    Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                        size: 12, color: isSelected ? kBlue : Colors.grey),
                                    const SizedBox(width: 3),
                                  ],
                                  Flexible(child: Text(a.displayWord.replaceAll('*', ' '),
                                      style: TextStyle(color: a.typeColor, fontWeight: FontWeight.w700, fontSize: 12),
                                      overflow: TextOverflow.ellipsis)),
                                  if (a.isFavorite) const Text('⭐', style: TextStyle(fontSize: 9)),
                                ]),
                                Wrap(spacing: 2, children: [
                                  ...a.typeLabels.map((l) {
                                    final c = l == '동시' ? kPurple : l == '합성' ? kBlueSky : kBlueDark;
                                    return Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                      decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
                                      child: Text(l, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.w700)));
                                  }),
                                  if (group != null) Container(padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                    decoration: BoxDecoration(color: group.color.withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
                                    child: Text(group.name, style: TextStyle(fontSize: 8, color: group.color, fontWeight: FontWeight.w700))),
                                ]),
                                if (a.strokeDisplay.isNotEmpty)
                                  Text(a.strokeDisplay, style: const TextStyle(fontSize: 9, color: Colors.grey),
                                      overflow: TextOverflow.ellipsis, maxLines: 1),
                              ])));
                        }),
                      const SizedBox(height: 16),
                    ],
                  ],
                ]))),
            ]))));
      });
  }
}

// ── TTS 하이라이트 분석 텍스트 뷰 (탭하면 그 위치부터 재생) ──────────
class TtsAnalysisTextView extends StatefulWidget {
  final List<_Span> parts;
  final AbbreviationModel? selectedAbbr;
  final void Function(AbbreviationModel, Offset) onAbbrTap;
  const TtsAnalysisTextView({super.key, required this.parts,
    required this.selectedAbbr, required this.onAbbrTap});
  @override State<TtsAnalysisTextView> createState() => _TtsAnalysisTextViewState();
}
class _TtsAnalysisTextViewState extends State<TtsAnalysisTextView> {
  @override void initState() { super.initState(); TtsController.instance.addListener(_rebuild); }
  @override void dispose() { TtsController.instance.removeListener(_rebuild); super.dispose(); }
  void _rebuild() { if (mounted) setState(() {}); }

  @override
  Widget build(BuildContext context) {
    final tts = TtsController.instance;
    final ws = tts.wordStart;
    final we = tts.wordEnd;
    final hasAbbr = widget.parts.any((p) => p.abbr != null);

    int offset = 0;
    final children = <InlineSpan>[];

    for (final p in widget.parts) {
      Color color = Colors.black87; FontWeight fw = FontWeight.w400;
      if (p.type == 'abbr')       { color = kBlue;    fw = FontWeight.w700; }
      if (p.type == 'composite')  { color = kBlueSky; fw = FontWeight.w700; }
      if (p.type == 'concurrent') { color = kPurple;  fw = FontWeight.w700; }

      final spanStart = offset;
      final spanEnd   = offset + p.text.length;
      final isHighlighted = tts.playing && ws >= 0 && spanStart < we && spanEnd > ws;
      final displayText   = p.text + (p.abbr?.isFavorite == true ? '⭐' : '');
      final isSelected    = widget.selectedAbbr?.id == p.abbr?.id && p.abbr != null;

      if (p.abbr != null) {
        children.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
          child: GestureDetector(
            onTapUp: (d) => widget.onAbbrTap(p.abbr!, d.globalPosition),
            onLongPress: () => TtsController.instance.seekAndPlay(spanStart),
            child: Container(
              decoration: BoxDecoration(
                color: isHighlighted ? kBlue.withOpacity(0.18)
                    : isSelected ? color.withOpacity(0.12) : null,
                borderRadius: BorderRadius.circular(3)),
              child: Text(displayText,
                  style: TextStyle(fontSize: 16, color: color, fontWeight: fw, height: 1.8,
                      decoration: isSelected ? TextDecoration.underline : null,
                      decorationColor: color))))));
      } else {
        final wordRegex = RegExp(r'\S+|\s+');
        for (final m in wordRegex.allMatches(p.text)) {
          final piece = m.group(0)!;
          final pieceStart = spanStart + m.start;
          final pieceEnd = pieceStart + piece.length;
          final pieceHighlighted = tts.playing && ws >= 0 && pieceStart < we && pieceEnd > ws;
          final isSpace = piece.trim().isEmpty;

          if (isSpace) {
            children.add(TextSpan(text: piece,
                style: TextStyle(fontSize: 16, color: color, fontWeight: fw, height: 1.8)));
          } else {
            children.add(WidgetSpan(
              alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: () => TtsController.instance.seekAndPlay(pieceStart),
                child: Container(
                  decoration: BoxDecoration(
                    color: pieceHighlighted ? kBlue.withOpacity(0.18) : null,
                    borderRadius: BorderRadius.circular(3)),
                  child: Text(piece,
                      style: TextStyle(fontSize: 16, color: color, fontWeight: fw, height: 1.8)),
                ),
              ),
            ));
          }
        }
      }
      offset = spanEnd;
    }
    return Text.rich(TextSpan(children: children));
  }
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

class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override State<SearchScreen> createState() => _SearchScreenState();
}
class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  bool _showFavOnly = false;
  String? _filterGroupId;
  final Set<String> _selected = {};
  bool _selectMode = false;

  void _toggleSelectMode() => setState(() { _selectMode = !_selectMode; _selected.clear(); });
  void _toggleSelect(String id) => setState(() {
    if (_selected.contains(id)) _selected.remove(id); else _selected.add(id);
  });

  Future<void> _bulkFav(List<AbbreviationModel> all) async {
    for (final a in all.where((a) => _selected.contains(a.id)))
      await Store.saveAbbreviation(a.copyWith(isFavorite: true));
    setState(() { _selected.clear(); _selectMode = false; });
  }

  Future<void> _bulkDelete(BuildContext context, List<AbbreviationModel> all) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('선택 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('선택한 ${_selected.length}개를 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true), child: const Text('삭제'))]));
    if (ok != true) return;
    for (final a in all.where((a) => _selected.contains(a.id)))
      await Store.deleteAbbreviation(a.id);
    setState(() { _selected.clear(); _selectMode = false; });
  }

  void _bulkRemind(BuildContext context, List<AbbreviationModel> all) {
    final targets = all.where((a) => _selected.contains(a.id)).map((a) => a.word).toList();
    _showBulkReminderDialog(context, targets, 'word');
    setState(() { _selected.clear(); _selectMode = false; });
  }

  void _bulkSetGroup(BuildContext context, List<AbbreviationModel> all) async {
    final groups = Store.getGroups();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 그룹을 만들어 주세요'), backgroundColor: kBlue, duration: Duration(seconds: 2)));
      return;
    }
    final gid = await showDialog<String?>(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('그룹 지정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ...groups.map((g) => ListTile(
          leading: CircleAvatar(backgroundColor: g.color, radius: 10),
          title: Text(g.name),
          onTap: () => Navigator.pop(ctx, g.id))),
        ListTile(
          leading: const CircleAvatar(backgroundColor: Colors.grey, radius: 10),
          title: const Text('그룹 해제'),
          onTap: () => Navigator.pop(ctx, '')),
      ])));
    if (gid == null) return;
    for (final a in all.where((a) => _selected.contains(a.id)))
      await Store.saveAbbreviation(gid.isEmpty ? a.copyWith(clearGroup: true) : a.copyWith(groupId: gid));
    setState(() { _selected.clear(); _selectMode = false; });
  }

  void _bulkEditType(BuildContext context, List<AbbreviationModel> all) {
    bool isComposite = false, isConcurrent = false, isAttached = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('분류 변경 (${_selected.length}개)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: _TypeToggleRow(
        isComposite: isComposite, isConcurrent: isConcurrent,
        isAttached: isAttached, isFavorite: false,
        onCompositeChanged: (v) => setS(() => isComposite = v),
        onConcurrentChanged: (v) => setS(() => isConcurrent = v),
        onAttachedChanged: (v) => setS(() => isAttached = v),
        onFavoriteChanged: (_) {}),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () async {
            for (final a in all.where((a) => _selected.contains(a.id)))
              await Store.saveAbbreviation(a.copyWith(
                isComposite: isComposite, isConcurrent: isConcurrent, isAttached: isAttached));
            if (ctx.mounted) Navigator.pop(ctx);
            setState(() { _selected.clear(); _selectMode = false; });
          }, child: const Text('적용')),
      ])));
  }

  void _openSelectedView(BuildContext context, List<AbbreviationModel> all) {
    final selectedItems = all.where((a) => _selected.contains(a.id)).toList();
    if (selectedItems.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택된 약어가 없습니다'), backgroundColor: kBlue, duration: Duration(seconds: 1)));
      return;
    }
    Navigator.push(context, MaterialPageRoute(builder: (_) => _SelectedAbbrView(items: selectedItems)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('abbreviations').listenable(),
      builder: (context, abBox, _) {
        return ValueListenableBuilder(valueListenable: Hive.box('groups').listenable(),
          builder: (context, grBox, _) {
            final q = _ctrl.text.trim();
            final all = Store.getAbbreviations();
            final groups = Store.getGroups();
            var results = q.isEmpty ? all : sortedSearchResults(all, q);
            if (_showFavOnly) results = results.where((a) => a.isFavorite).toList();
            if (_filterGroupId != null) results = results.where((a) => a.groupId == _filterGroupId).toList();

            return Scaffold(backgroundColor: Colors.white,
              body: SafeArea(child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12), child: Row(children: [
                  const Expanded(child: Text('약어 검색', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                  if (_selectMode) ...[
                    GestureDetector(onTap: () => _bulkFav(results),
                      child: _actionChip(Icons.star_rounded, '즐겨찾기', const Color(0xFFFFAA00))),
                    const SizedBox(width: 4),
                    GestureDetector(onTap: () => _bulkRemind(context, results),
                      child: _actionChip(Icons.notifications_rounded, '리마인드', kBlue)),
                    const SizedBox(width: 4),
                    GestureDetector(onTap: () => _bulkSetGroup(context, results),
                      child: _actionChip(Icons.label_rounded, '그룹', kBlueSky)),
                    const SizedBox(width: 4),
                    GestureDetector(onTap: () => _bulkEditType(context, results),
                      child: _actionChip(Icons.edit_rounded, '분류', kPurple)),
                    const SizedBox(width: 4),
                    GestureDetector(onTap: () => _openSelectedView(context, results),
                      child: _actionChip(Icons.visibility_rounded, '모아보기', kBlueDark)),
                    const SizedBox(width: 4),
                    GestureDetector(onTap: () => _bulkDelete(context, results),
                      child: _actionChip(Icons.delete_rounded, '삭제', Colors.red)),
                    const SizedBox(width: 4),
                    GestureDetector(onTap: _toggleSelectMode,
                      child: _actionChip(Icons.close, '취소', Colors.grey)),
                  ] else ...[
                    GestureDetector(onTap: () => setState(() { _showFavOnly = !_showFavOnly; _filterGroupId = null; }),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        margin: const EdgeInsets.only(right: 6),
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
                    if (groups.isNotEmpty)
                      GestureDetector(onTap: () => _showGroupFilter(context, groups),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          margin: const EdgeInsets.only(right: 6),
                          decoration: BoxDecoration(
                            color: kBlueLight, borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _filterGroupId != null ? (Store.findGroup(_filterGroupId!)?.color ?? kBlue) : Colors.transparent,
                              width: 1.2)),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.label_rounded, size: 16,
                                color: _filterGroupId != null ? (Store.findGroup(_filterGroupId!)?.color ?? kBlue) : Colors.grey),
                            const SizedBox(width: 4),
                            Text(_filterGroupId != null ? (Store.findGroup(_filterGroupId!)?.name ?? '그룹') : '그룹',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                                    color: _filterGroupId != null ? (Store.findGroup(_filterGroupId!)?.color ?? kBlue) : Colors.grey)),
                          ]))),
                    GestureDetector(onTap: _toggleSelectMode,
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.checklist_rounded, size: 16, color: kBlue))),
                    GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupManageScreen())),
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        margin: const EdgeInsets.only(right: 6),
                        decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.folder_rounded, size: 16, color: kBlue))),
                    ElevatedButton.icon(onPressed: () => _showAbbrEditDialog(context),
                      icon: const Icon(Icons.add, size: 16), label: const Text('추가'),
                      style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6))),
                  ],
                ])),
                if (_selectMode)
                  Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                    child: Row(children: [
                      Text('${_selected.length}개 선택됨', style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.w600)),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: () => setState(() {
                          if (_selected.length == results.length) _selected.clear();
                          else _selected.addAll(results.map((a) => a.id));
                        }),
                        child: Text(_selected.length == results.length ? '전체 해제' : '전체 선택',
                            style: const TextStyle(fontSize: 12, color: Colors.grey))),
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
                      if (!_showFavOnly && _filterGroupId == null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: () => _showAbbrEditDialog(context),
                          style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBlue),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                          child: const Text('약어 추가하기', style: TextStyle(fontWeight: FontWeight.w700))),
                      ]]))
                  : ListView.builder(
                      controller: _searchScrollCtrl,
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      itemCount: results.length,
                      itemBuilder: (context, index) {
                        final a = results[index];
                        final isSelected = _selected.contains(a.id);
                        if (_selectMode) {
                          return GestureDetector(
                            onTap: () => _toggleSelect(a.id),
                            child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                              decoration: BoxDecoration(
                                color: isSelected ? kBlueLight : Colors.white,
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(color: isSelected ? kBlue : const Color(0xFFEEF0F8),
                                    width: isSelected ? 1.5 : 1)),
                              child: Row(children: [
                                Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                    color: isSelected ? kBlue : Colors.grey, size: 20),
                                const SizedBox(width: 10),
                                Expanded(child: _AbbrContent(abbr: a, groups: groups)),
                              ])));
                        }
                        return _AbbrListTile(abbr: a, groups: groups,
                          onFav: () async => Store.saveAbbreviation(a.copyWith(isFavorite: !a.isFavorite)),
                          onEdit: () => _showAbbrEditDialog(context, existing: a),
                          onDelete: () => _confirmDelete(context, a),
                          onRemind: () => _showReminderDialog(context, a.word, 'word'));
                      })),
              ])));
          });
      });
  }

  void _showGroupFilter(BuildContext context, List<GroupModel> groups) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('그룹 필터', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(leading: const CircleAvatar(backgroundColor: Colors.grey, radius: 10),
          title: const Text('전체'),
          onTap: () { setState(() => _filterGroupId = null); Navigator.pop(ctx); }),
        ...groups.map((g) => ListTile(
          leading: CircleAvatar(backgroundColor: g.color, radius: 10),
          title: Text(g.name),
          trailing: _filterGroupId == g.id ? const Icon(Icons.check, color: kBlue) : null,
          onTap: () { setState(() => _filterGroupId = g.id); Navigator.pop(ctx); })),
      ])));
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

class _SelectedAbbrView extends StatefulWidget {
  final List<AbbreviationModel> items;
  const _SelectedAbbrView({required this.items});
  @override State<_SelectedAbbrView> createState() => _SelectedAbbrViewState();
}
class _SelectedAbbrViewState extends State<_SelectedAbbrView> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('abbreviations').listenable(),
      builder: (context, box, _) {
        final groups = Store.getGroups();
        final allNow = Store.getAbbreviations();
        final items = widget.items
            .map((old) => allNow.firstWhere((a) => a.id == old.id, orElse: () => old))
            .toList();
        return Scaffold(backgroundColor: Colors.white,
          appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: kBlue),
                onPressed: () => Navigator.pop(context)),
            title: Text('선택한 약어 (${items.length}개)', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16))),
          body: items.isEmpty
            ? const Center(child: Text('선택된 약어가 없습니다', style: TextStyle(color: Colors.grey)))
            : ListView.builder(padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                itemCount: items.length,
                itemBuilder: (ctx, i) {
                  final a = items[i];
                  return _AbbrListTile(abbr: a, groups: groups,
                    onFav: () async => Store.saveAbbreviation(a.copyWith(isFavorite: !a.isFavorite)),
                    onEdit: () => _showAbbrEditDialog(context, existing: a),
                    onDelete: () async {
                      final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        title: const Text('삭제 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                        content: Text('"${a.displayWord}" 약어를 삭제할까요?'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
                              onPressed: () => Navigator.pop(c, true), child: const Text('삭제'))]));
                      if (ok == true) await Store.deleteAbbreviation(a.id);
                    },
                    onRemind: () => _showReminderDialog(context, a.word, 'word'));
                }));
      });
  }
}

void _showAbbrEditDialog(BuildContext context, {AbbreviationModel? existing}) {
  final List<Map<String, TextEditingController>> rows = [];
  final List<Map<String, bool>> rowFlags = [];
  final List<String?> rowGroupIds = [];
  void addRow({AbbreviationModel? from}) {
    rows.add({
      'word':    TextEditingController(text: from?.word.replaceAll('*', ' ') ?? ''),
      'initial': TextEditingController(text: from?.initial.isNotEmpty == true ? from!.initial.join('+') : ''),
      'medial':  TextEditingController(text: from?.medial.isNotEmpty  == true ? from!.medial.join('+')  : ''),
      'final':   TextEditingController(text: from?.final_.isNotEmpty  == true ? from!.final_.join('+')  : ''),
    });
    rowFlags.add({
      'isComposite': from?.isComposite ?? false,
      'isConcurrent': from?.isConcurrent ?? false,
      'isAttached': from?.isAttached ?? false,
      'isFavorite': from?.isFavorite ?? false,
    });
    rowGroupIds.add(from?.groupId);
  }
  addRow(from: existing);

  showDialog(context: context, barrierColor: Colors.black.withOpacity(0.3),
    builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
      final groups = Store.getGroups();
      List<String> pf(String s) => s.split(RegExp(r'[+\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

     Future<void> saveAll() async {
        // 중복 단어 체크
        final dupWords = <String>[];
        for (int i = 0; i < rows.length; i++) {
          final raw = rows[i]['word']!.text.trim();
          if (raw.isEmpty) continue;
          final word = encodeWord(raw);
          final excludeId = (existing != null && i == 0) ? existing.id : null;
          if (Store.existsWord(word, excludeId: excludeId)) {
            dupWords.add(raw);
          }
        }

        if (dupWords.isNotEmpty) {
          final proceedAnyway = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('이미 등록된 단어', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text('다음 단어는 이미 등록되어 있어요:\n${dupWords.join(", ")}\n\n그래도 저장할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(c, true), child: const Text('그래도 저장'))]));
          if (proceedAnyway != true) return;
        }

        final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing != null ? '수정 확인' : '저장 확인',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Text(existing != null ? '수정할까요?' : '${rows.length}개를 저장할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c, true), child: const Text('저장'))]));
        if (ok != true) return;
        Navigator.pop(dCtx);
        for (int i = 0; i < rows.length; i++) {
          final raw = rows[i]['word']!.text.trim();
          if (raw.isEmpty) continue;
          final word = encodeWord(raw);
          final id = (existing != null && i == 0) ? existing.id : '${DateTime.now().millisecondsSinceEpoch}_$i';
          await Store.saveAbbreviation(AbbreviationModel(
            id: id, word: word,
            initial: pf(rows[i]['initial']!.text),
            medial: pf(rows[i]['medial']!.text),
            final_: pf(rows[i]['final']!.text),
            isComposite: rowFlags[i]['isComposite']!,
            isConcurrent: rowFlags[i]['isConcurrent']!,
            isAttached: rowFlags[i]['isAttached']!,
            isFavorite: rowFlags[i]['isFavorite']!,
            groupId: rowGroupIds[i]));
        }
      }

      void applyToAll() => setS(() {
        for (int i = 1; i < rows.length; i++) {
          rowFlags[i] = Map.from(rowFlags[0]);
          rowGroupIds[i] = rowGroupIds[0];
        }
      });

      Widget typeAndGroupSection(int i) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 8),
        _TypeToggleRow(
          isComposite: rowFlags[i]['isComposite']!, isConcurrent: rowFlags[i]['isConcurrent']!,
          isAttached: rowFlags[i]['isAttached']!, isFavorite: rowFlags[i]['isFavorite']!,
          onCompositeChanged: (v) => setS(() => rowFlags[i]['isComposite'] = v),
          onConcurrentChanged: (v) => setS(() => rowFlags[i]['isConcurrent'] = v),
          onAttachedChanged: (v) => setS(() => rowFlags[i]['isAttached'] = v),
          onFavoriteChanged: (v) => setS(() => rowFlags[i]['isFavorite'] = v)),
        if (groups.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(spacing: 6, runSpacing: 6, children: [
            GestureDetector(onTap: () => setS(() => rowGroupIds[i] = null),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: rowGroupIds[i] == null ? Colors.grey.withOpacity(0.15) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: rowGroupIds[i] == null ? Colors.grey : Colors.transparent, width: 1.5)),
                child: Text('없음', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                    color: rowGroupIds[i] == null ? Colors.grey.shade700 : Colors.grey)))),
            ...groups.map((g) => GestureDetector(onTap: () => setS(() => rowGroupIds[i] = g.id),
              child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: rowGroupIds[i] == g.id ? g.color.withOpacity(0.15) : const Color(0xFFF5F5F5),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: rowGroupIds[i] == g.id ? g.color : Colors.transparent, width: 1.5)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(backgroundColor: g.color, radius: 5),
                  const SizedBox(width: 5),
                  Text(g.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                      color: rowGroupIds[i] == g.id ? g.color : Colors.grey)),
                ])))),
          ]),
        ],
      ]);

      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(existing != null ? '약어 수정' : '약어 추가',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          if (existing == null)
            TextButton.icon(onPressed: () => setS(() => addRow()),
              icon: const Icon(Icons.add, size: 14), label: const Text('행 추가', style: TextStyle(fontSize: 12)),
              style: TextButton.styleFrom(foregroundColor: kBlue)),
        ]),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (rows.length > 1)
            Padding(padding: const EdgeInsets.only(bottom: 8),
              child: Align(alignment: Alignment.centerRight,
                child: TextButton.icon(onPressed: applyToAll,
                  icon: const Icon(Icons.copy_all_rounded, size: 14),
                  label: const Text('1번 분류/그룹을 전체에 적용', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(foregroundColor: kBlueSky)))),
          ...rows.asMap().entries.map((e) {
            final i = e.key; final row = e.value;
            return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (rows.length > 1) Row(children: [
                Text('${i + 1}번', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
                const Spacer(),
                GestureDetector(onTap: () => setS(() { rows.removeAt(i); rowFlags.removeAt(i); rowGroupIds.removeAt(i); }),
                  child: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.red)),
              ]),
              if (rows.length > 1) const SizedBox(height: 4),
              _lbl('단어'),
              TextField(controller: row['word'], decoration: _inputDeco(''), textInputAction: TextInputAction.next),
              const SizedBox(height: 4),
              Text('※ 띄어쓰기 → * 자동 변환', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('초성'), TextField(controller: row['initial'], decoration: _inputDeco(''), textInputAction: TextInputAction.next),
                ])),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('중성'), TextField(controller: row['medial'], decoration: _inputDeco(''), textInputAction: TextInputAction.next),
                ])),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('종성'),
                  TextField(controller: row['final'], decoration: _inputDeco(''),
                    textInputAction: i == rows.length - 1 ? TextInputAction.done : TextInputAction.next,
                    onSubmitted: i == rows.length - 1 ? (_) => saveAll() : null),
                ])),
              ]),
              const SizedBox(height: 4),
              Text('※ ㅋ → (ㅋ)  |  여러 값은 + 로 구분', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              _lbl(rows.length > 1 ? '${i + 1}번 분류/그룹' : '분류'),
              typeAndGroupSection(i),
              if (i < rows.length - 1) const Divider(height: 24),
            ]);
          }),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dCtx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
            onPressed: saveAll, child: const Text('저장')),
        ]);
    }));
}

class GroupManageScreen extends StatefulWidget {
  const GroupManageScreen({super.key});
  @override State<GroupManageScreen> createState() => _GroupManageScreenState();
}
class _GroupManageScreenState extends State<GroupManageScreen> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('groups').listenable(),
      builder: (context, box, _) {
        final groups = Store.getGroups();
        return Scaffold(backgroundColor: Colors.white,
          appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
            leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: kBlue),
                onPressed: () => Navigator.pop(context)),
            title: const Text('그룹 관리', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18)),
            actions: [TextButton.icon(
              onPressed: () => _showGroupEditDialog(context),
              icon: const Icon(Icons.add, size: 16, color: kBlue),
              label: const Text('그룹 추가', style: TextStyle(color: kBlue, fontWeight: FontWeight.w600)))]),
          body: groups.isEmpty
            ? const Center(child: Text('그룹이 없습니다', style: TextStyle(color: Colors.grey)))
            : ListView.builder(padding: const EdgeInsets.all(16), itemCount: groups.length,
                itemBuilder: (ctx, i) {
                  final g = groups[i];
                  final count = Store.getAbbreviations().where((a) => a.groupId == g.id).length;
                  return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEEF0F8))),
                    child: Row(children: [
                      CircleAvatar(backgroundColor: g.color, radius: 14,
                        child: Text(g.name.isNotEmpty ? g.name[0] : '?',
                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12))),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(g.name, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
                        Text('약어 $count개', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ])),
                      IconButton(icon: const Icon(Icons.edit_rounded, size: 18, color: Colors.grey),
                          onPressed: () => _showGroupEditDialog(context, existing: g)),
                      IconButton(icon: const Icon(Icons.delete_outline_rounded, size: 18, color: Colors.red),
                          onPressed: () => _confirmDeleteGroup(context, g)),
                    ]));
                }));
      });
  }

  void _showGroupEditDialog(BuildContext context, {GroupModel? existing}) {
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    Color selectedColor = existing != null ? existing.color : kGroupColors[0];
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(existing == null ? '그룹 추가' : '그룹 수정',
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lbl('그룹 이름'),
        TextField(controller: nameCtrl, decoration: _inputDeco('그룹 이름 입력')),
        const SizedBox(height: 14),
        _lbl('색상'),
        Wrap(spacing: 8, runSpacing: 8, children: kGroupColors.map((c) => GestureDetector(
          onTap: () => setS(() => selectedColor = c),
          child: Container(width: 32, height: 32,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle,
              border: Border.all(color: selectedColor.value == c.value ? Colors.black : Colors.transparent, width: 2.5)),
            child: selectedColor.value == c.value ? const Icon(Icons.check, color: Colors.white, size: 16) : null))).toList()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            await Store.saveGroup(GroupModel(
              id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
              name: name, colorValue: selectedColor.value));
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('저장')),
      ])));
  }

  void _confirmDeleteGroup(BuildContext context, GroupModel g) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('그룹 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('"${g.name}" 그룹을 삭제할까요?\n약어의 그룹 지정은 해제됩니다.'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () async {
            await Store.deleteGroup(g.id);
            for (final a in Store.getAbbreviations().where((a) => a.groupId == g.id))
              await Store.saveAbbreviation(a.copyWith(clearGroup: true));
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('삭제')),
      ]));
  }
}

class _AbbrContent extends StatelessWidget {
  final AbbreviationModel abbr;
  final List<GroupModel> groups;
  const _AbbrContent({required this.abbr, required this.groups});
  @override
  Widget build(BuildContext context) {
    final group = abbr.groupId != null ? groups.where((g) => g.id == abbr.groupId).firstOrNull : null;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
        if (group != null) Container(margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: group.color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: Text(group.name, style: TextStyle(fontSize: 10, color: group.color, fontWeight: FontWeight.w700))),
      ]),
      const SizedBox(height: 4),
      SelectableText(abbr.strokeDisplay, style: const TextStyle(fontSize: 12, color: Colors.grey)),
    ]);
  }
}

class _AbbrListTile extends StatefulWidget {
  final AbbreviationModel abbr;
  final List<GroupModel> groups;
  final VoidCallback? onFav, onEdit, onDelete, onRemind;
  const _AbbrListTile({required this.abbr, required this.groups, this.onFav, this.onEdit, this.onDelete, this.onRemind});
  @override State<_AbbrListTile> createState() => _AbbrListTileState();
}
class _AbbrListTileState extends State<_AbbrListTile> {
  @override
  Widget build(BuildContext context) => Container(
    margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEF0F8))),
    child: Row(children: [
      Expanded(child: _AbbrContent(abbr: widget.abbr, groups: widget.groups)),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, color: Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (_) => [
          PopupMenuItem(child: Text(widget.abbr.isFavorite ? '⭐ 즐겨찾기 해제' : '☆ 즐겨찾기 추가'),
              onTap: () => widget.onFav?.call()),
          if (widget.onEdit != null)
            PopupMenuItem(child: const Text('✏️ 수정'), onTap: () => widget.onEdit?.call()),
          if (widget.onRemind != null)
            PopupMenuItem(child: const Text('🔔 리마인드 설정'), onTap: () => widget.onRemind?.call()),
          if (widget.onDelete != null)
            PopupMenuItem(child: const Text('🗑 삭제', style: TextStyle(color: Colors.red)),
                onTap: () => widget.onDelete?.call()),
        ]),
    ]));
}

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

class SentenceRegisterScreen extends StatefulWidget {
  const SentenceRegisterScreen({super.key});
  @override State<SentenceRegisterScreen> createState() => _SentenceRegisterScreenState();
}
class _SentenceRegisterScreenState extends State<SentenceRegisterScreen> {
  final _ctrl = TextEditingController(); final _focusNode = FocusNode();
  final Set<String> _selected = {};
  bool _selectMode = false;
  @override void dispose() { _ctrl.dispose(); _focusNode.dispose(); super.dispose(); }

  void _toggleSelectMode() => setState(() { _selectMode = !_selectMode; _selected.clear(); });
  void _toggleSelect(String id) => setState(() {
    if (_selected.contains(id)) _selected.remove(id); else _selected.add(id);
  });

  Future<void> _bulkDelete(BuildContext context, List<SavedSentenceModel> all) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('선택 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('선택한 ${_selected.length}개를 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true), child: const Text('삭제'))]));
    if (ok != true) return;
    for (final s in all.where((s) => _selected.contains(s.id)))
      await Store.deleteSentence(s.id);
    setState(() { _selected.clear(); _selectMode = false; });
  }

  void _bulkRemind(BuildContext context, List<SavedSentenceModel> all) {
    final targets = all.where((s) => _selected.contains(s.id)).map((s) => s.text).toList();
    _showBulkReminderDialog(context, targets, 'sentence');
    setState(() { _selected.clear(); _selectMode = false; });
  }

  void _editSelected(BuildContext context, List<SavedSentenceModel> all) {
    if (_selected.length != 1) return;
    final s = all.firstWhere((s) => _selected.contains(s.id));
    final ctrl = TextEditingController(text: s.text);
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('문장 수정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: TextField(controller: ctrl, maxLines: 4, decoration: _inputDeco('')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () async {
            final text = ctrl.text.trim();
            if (text.isEmpty) return;
            await Store.saveSentence(SavedSentenceModel(id: s.id, text: text, createdAt: s.createdAt));
            if (ctx.mounted) Navigator.pop(ctx);
            setState(() { _selected.clear(); _selectMode = false; });
          }, child: const Text('저장')),
      ]));
  }

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
            Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12),
              child: Row(children: [
                const Expanded(child: Text('문장 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900))),
                if (_selectMode) ...[
                  if (_selected.length == 1) ...[
                    GestureDetector(onTap: () => _editSelected(context, sentences),
                      child: _actionChip(Icons.edit_rounded, '수정', kBlueSky)),
                    const SizedBox(width: 4),
                  ],
                  GestureDetector(onTap: () => _bulkRemind(context, sentences),
                    child: _actionChip(Icons.notifications_rounded, '리마인드', kBlue)),
                  const SizedBox(width: 4),
                  GestureDetector(onTap: () => _bulkDelete(context, sentences),
                    child: _actionChip(Icons.delete_rounded, '삭제', Colors.red)),
                  const SizedBox(width: 4),
                  GestureDetector(onTap: _toggleSelectMode,
                    child: _actionChip(Icons.close, '취소', Colors.grey)),
                ] else
                  GestureDetector(onTap: _toggleSelectMode,
                    child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(20)),
                      child: const Icon(Icons.checklist_rounded, size: 16, color: kBlue))),
              ])),
            if (_selectMode)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  Text('${_selected.length}개 선택됨', style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => setState(() {
                      if (_selected.length == sentences.length) _selected.clear();
                      else _selected.addAll(sentences.map((s) => s.id));
                    }),
                    child: Text(_selected.length == sentences.length ? '전체 해제' : '전체 선택',
                        style: const TextStyle(fontSize: 12, color: Colors.grey))),
                ])),
            Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: Column(children: [
              TextField(controller: _ctrl, focusNode: _focusNode, maxLines: 3,
                decoration: InputDecoration(hintText: '복습할 문장을 입력하세요...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBlue)))),
              const SizedBox(height: 8),
              SizedBox(width: double.infinity, child: ElevatedButton(onPressed: () => _save(context),
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
                    final isSelected = _selected.contains(s.id);
                    if (_selectMode) {
                      return GestureDetector(onTap: () => _toggleSelect(s.id),
                        child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? kBlueLight : Colors.white, borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? kBlue : const Color(0xFFEEF0F8), width: isSelected ? 1.5 : 1)),
                          child: Row(children: [
                            Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? kBlue : Colors.grey, size: 20),
                            const SizedBox(width: 10),
                            Expanded(child: Text(s.text, style: const TextStyle(fontSize: 14, height: 1.6))),
                          ])));
                    }
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEF0F8))),
                      child: Row(children: [
                        Expanded(child: SelectableText(s.text, style: const TextStyle(fontSize: 14, height: 1.6))),
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.more_horiz, color: Colors.grey),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          onSelected: (v) async {
                            if (v == 'edit') {
                              final ctrl2 = TextEditingController(text: s.text);
                              showDialog(context: ctx, builder: (c2) => AlertDialog(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                title: const Text('문장 수정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                                content: TextField(controller: ctrl2, maxLines: 4, decoration: _inputDeco('')),
                                actions: [
                                  TextButton(onPressed: () => Navigator.pop(c2), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                                  ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                                    onPressed: () async {
                                      final t = ctrl2.text.trim(); if (t.isEmpty) return;
                                      await Store.saveSentence(SavedSentenceModel(id: s.id, text: t, createdAt: s.createdAt));
                                      if (c2.mounted) Navigator.pop(c2);
                                    }, child: const Text('저장')),
                                ]));
                            }
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
                            const PopupMenuItem(value: 'edit', child: Text('✏️ 수정')),
                            const PopupMenuItem(value: 'remind', child: Text('🔔 리마인드 설정')),
                            const PopupMenuItem(value: 'delete', child: Text('🗑 삭제', style: TextStyle(color: Colors.red))),
                          ]),
                      ]));
                  })),
          ])));
      });
  }
}

class RemindersScreen extends StatefulWidget {
  const RemindersScreen({super.key});
  @override State<RemindersScreen> createState() => _RemindersScreenState();
}
class _RemindersScreenState extends State<RemindersScreen> {
  String _tl(String t) => t == 'word' ? '약어' : t == 'favorite' ? '즐겨찾기' : '문장';
  final Set<String> _selected = {};
  bool _selectMode = false;

  void _toggleSelectMode() => setState(() { _selectMode = !_selectMode; _selected.clear(); });
  void _toggleSelect(String id) => setState(() {
    if (_selected.contains(id)) _selected.remove(id); else _selected.add(id);
  });

  Future<void> _bulkDelete(BuildContext context, List<ReminderModel> all) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('선택 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('선택한 ${_selected.length}개를 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true), child: const Text('삭제'))]));
    if (ok != true) return;
    for (final r in all.where((r) => _selected.contains(r.id)))
      await Store.deleteReminder(r.id);
    setState(() { _selected.clear(); _selectMode = false; });
  }

  void _editSelected(BuildContext context, List<ReminderModel> all) {
    if (_selected.length != 1) return;
    final r = all.firstWhere((r) => _selected.contains(r.id));
    final targetCtrl = TextEditingController(text: r.target.replaceAll('*', ' '));
    int interval = r.intervalDays;
    bool repeat = r.repeat;
    DateTime date = DateTime.tryParse(r.date) ?? DateTime.now();

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('리마인드 수정', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lbl(r.type == 'word' ? '약어' : '문장'),
        TextField(controller: targetCtrl, maxLines: r.type == 'sentence' ? 3 : 1, decoration: _inputDeco('')),
        const SizedBox(height: 12),
        _lbl('날짜'),
        GestureDetector(
          onTap: () async {
            final picked = await showDatePicker(
              context: context, initialDate: date,
              firstDate: DateTime.now().subtract(const Duration(days: 365)),
              lastDate: DateTime.now().add(const Duration(days: 365 * 2)));
            if (picked != null) setS(() => date = picked);
          },
          child: Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(8)),
            child: Row(children: [
              const Icon(Icons.calendar_today_rounded, size: 16, color: kBlue),
              const SizedBox(width: 8),
              Text('${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}',
                  style: const TextStyle(fontSize: 14)),
            ]))),
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
            final target = targetCtrl.text.trim();
            if (target.isEmpty) return;
            final ds = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
            await Store.saveReminder(ReminderModel(
              id: r.id, type: r.type,
              target: r.type == 'word' ? encodeWord(target) : target,
              date: ds, intervalDays: interval, repeat: repeat, active: r.active));
            if (ctx.mounted) Navigator.pop(ctx);
            setState(() { _selected.clear(); _selectMode = false; });
          }, child: const Text('저장')),
      ])));
  }

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
                Row(children: [
                  if (_selectMode) ...[
                    if (_selected.length == 1) ...[
                      GestureDetector(onTap: () => _editSelected(context, reminders),
                        child: _actionChip(Icons.edit_rounded, '수정', kBlueSky)),
                      const SizedBox(width: 6),
                    ],
                    GestureDetector(onTap: () => _bulkDelete(context, reminders),
                      child: _actionChip(Icons.delete_rounded, '삭제', Colors.red)),
                    const SizedBox(width: 6),
                    GestureDetector(onTap: _toggleSelectMode,
                      child: _actionChip(Icons.close, '취소', Colors.grey)),
                  ] else ...[
                    GestureDetector(onTap: _toggleSelectMode,
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(20)),
                        child: const Icon(Icons.checklist_rounded, size: 16, color: kBlue))),
                    ElevatedButton.icon(onPressed: () => _showAddReminderDialog(context),
                      icon: const Icon(Icons.add, size: 16), label: const Text('추가'),
                      style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6))),
                  ],
                ]),
              ])),
            if (_selectMode)
              Padding(padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(children: [
                  Text('${_selected.length}개 선택됨', style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.w600)),
                  const SizedBox(width: 12),
                  GestureDetector(
                    onTap: () => setState(() {
                      if (_selected.length == reminders.length) _selected.clear();
                      else _selected.addAll(reminders.map((r) => r.id));
                    }),
                    child: Text(_selected.length == reminders.length ? '전체 해제' : '전체 선택',
                        style: const TextStyle(fontSize: 12, color: Colors.grey))),
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
                    final isSelected = _selected.contains(r.id);
                    if (_selectMode) {
                      return GestureDetector(onTap: () => _toggleSelect(r.id),
                        child: Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: isSelected ? kBlueLight : (r.active ? Colors.white : const Color(0xFFF8F8F8)),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: isSelected ? kBlue : const Color(0xFFEEF0F8), width: isSelected ? 1.5 : 1)),
                          child: Row(children: [
                            Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                color: isSelected ? kBlue : Colors.grey, size: 20),
                            const SizedBox(width: 10),
                            Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
                              child: Text(_tl(r.type), style: const TextStyle(fontSize: 11, color: kBlue, fontWeight: FontWeight.w700))),
                            const SizedBox(width: 8),
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(r.target.replaceAll('*', ' '), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                              Text('${r.date} · ${r.intervalDays}일 간격${r.repeat ? " · 반복" : ""}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            ])),
                          ])));
                    }
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
                          SelectableText(r.target.replaceAll('*', ' '), style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600), maxLines: 1),
                          Text('${r.date} · ${r.intervalDays}일 간격${r.repeat ? " · 반복" : ""}', style: const TextStyle(fontSize: 11, color: Colors.grey)),
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

void _showReminderDialog(BuildContext context, String target, String type) {
  final existing = Store.findReminder(target);
  int interval = existing?.intervalDays ?? 1;
  bool repeat = existing?.repeat ?? false;
  showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(existing != null ? '리마인드 수정' : '리마인드 설정',
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, children: [1, 3, 7].map((d) => GestureDetector(onTap: () => setS(() => interval = d),
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
          final date = DateTime.now().add(Duration(days: interval));
          final ds = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
          await Store.saveReminder(ReminderModel(
            id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
            type: type, target: target, date: ds, intervalDays: interval, repeat: repeat));
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('저장')),
    ])));
}

void _showBulkReminderDialog(BuildContext context, List<String> targets, String type) {
  int interval = 1; bool repeat = false;
  showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text('리마인드 설정 (${targets.length}개)', style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    content: Column(mainAxisSize: MainAxisSize.min, children: [
      Wrap(spacing: 8, children: [1, 3, 7].map((d) => GestureDetector(onTap: () => setS(() => interval = d),
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
          final date = DateTime.now().add(Duration(days: interval));
          final ds = '${date.year}-${date.month.toString().padLeft(2,'0')}-${date.day.toString().padLeft(2,'0')}';
          for (final t in targets)
            await Store.saveReminder(ReminderModel(
              id: '${DateTime.now().millisecondsSinceEpoch}_${t.hashCode}',
              type: type, target: t, date: ds, intervalDays: interval, repeat: repeat));
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: const Text('설정')),
    ])));
}

// ── 퀴즈 화면 ────────────────────────────────────────────────────────
class QuizScreen extends StatefulWidget {
  const QuizScreen({super.key});
  @override State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // 설정
  String _mode = 'abbr'; // 'abbr' or 'sentence'
  String? _filterGroupId;
  int _quizCount = 10;
  
  // 퀴즈 진행
  List<dynamic> _questions = [];
  int _currentIdx = 0;
  bool _started = false;
  bool _finished = false;
  
  // 채점
  final _answerCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = []; // {question, userAnswer, correct, wrong}
  Map<String, int> _wrongCounts = {}; // 많이 틀린 순
  
  // TTS
  bool _ttsPlayed = false;
  final _inputFocusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();

  @override
  void dispose() {
    _answerCtrl.dispose();
    _inputFocusNode.dispose();
    _keyboardFocusNode.dispose();
    TtsController.instance.stop();
    super.dispose();
  }

  List<dynamic> _buildQuestions() {
    final abbrevs = Store.getAbbreviations();
    final sentences = Store.getSentences();
    List<dynamic> pool = [];
    if (_mode == 'abbr' || _mode == 'both') {
      var filtered = abbrevs;
      if (_filterGroupId != null) {
        filtered = abbrevs.where((a) => a.groupId == _filterGroupId).toList();
      }
      pool.addAll(filtered);
    }
    if (_mode == 'sentence' || _mode == 'both') {
      pool.addAll(sentences);
    }
    pool.shuffle();
    final count = _quizCount.clamp(1, pool.length);
    return pool.take(count).toList();
  }

  void _start() {
    final qs = _buildQuestions();
    if (qs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('문제가 없어요. 약어나 문장을 먼저 등록해주세요.'),
            backgroundColor: kBlue));
      return;
    }
    setState(() {
      _questions = qs;
      _currentIdx = 0;
      _results = [];
      _wrongCounts = {};
      _started = true;
      _finished = false;
      _ttsPlayed = false;
      _answerCtrl.clear();
    });
    _playCurrentTts();
  }

  void _playCurrentTts() async {
    if (_currentIdx >= _questions.length) return;
    final q = _questions[_currentIdx];
    final text = q is AbbreviationModel
        ? q.displayWord.replaceAll('*', ' ')
        : (q as SavedSentenceModel).text;
    await TtsController.instance.speak(text);
    setState(() => _ttsPlayed = true);
  }

// 을/를, 와/과, 으로/므로 쌍 정규화 + 마침표 제거
  String _normalizeJosa(String word) {
    String w = word.replaceAll('.', '').replaceAll('。', '');
    if (w.endsWith('를') || w.endsWith('을'))
      return w.substring(0, w.length - 1) + '을';
    if (w.endsWith('와') || w.endsWith('과'))
      return w.substring(0, w.length - 1) + '과';
    if (w.endsWith('므로') || w.endsWith('으로'))
      return w.substring(0, w.length - 2) + '으로';
    return w;
  }
  
  // diff 알고리즘: 빠진/틀린 단어만 찾기 (순서 밀림 방지)
  List<String> _findWrong(List<String> answer, List<String> correct) {
    final normAnswer = answer.map(_normalizeJosa).toList();
    final normCorrect = correct.map(_normalizeJosa).toList();
    final n = normCorrect.length, m = normAnswer.length;
    final dp = List.generate(n + 1, (_) => List.filled(m + 1, 0));
    for (int i = 1; i <= n; i++) {
      for (int j = 1; j <= m; j++) {
        if (normCorrect[i-1] == normAnswer[j-1]) dp[i][j] = dp[i-1][j-1] + 1;
        else dp[i][j] = dp[i-1][j] > dp[i][j-1] ? dp[i-1][j] : dp[i][j-1];
      }
    }
    final matched = <int>{};
    int i = n, j = m;
    while (i > 0 && j > 0) {
      if (normCorrect[i-1] == normAnswer[j-1]) { matched.add(i-1); i--; j--; }
      else if (dp[i-1][j] > dp[i][j-1]) i--;
      else j--;
    }
    final wrong = <String>[];
    for (int k = 0; k < correct.length; k++) {
      if (!matched.contains(k)) wrong.add(correct[k]);
    }
    return wrong;
  }

  void _submit() {
    if (_currentIdx >= _questions.length) return;
    final q = _questions[_currentIdx];
    final correctText = q is AbbreviationModel
        ? q.displayWord.replaceAll('*', ' ')
        : (q as SavedSentenceModel).text;
    final userText = _answerCtrl.text.trim();

    final correctWords = correctText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final userWords = userText.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).toList();
    final wrongWords = _findWrong(userWords, correctWords);

    _results.add({
      'question': correctText,
      'userAnswer': userText,
      'correct': wrongWords.isEmpty,
      'wrong': wrongWords,
      'item': q,
    });

    for (final w in wrongWords) {
      _wrongCounts[w] = (_wrongCounts[w] ?? 0) + 1;
    }

    if (_currentIdx < _questions.length - 1) {
      setState(() {
        _currentIdx++;
        _ttsPlayed = false;
        _answerCtrl.clear();
      });
      _playCurrentTts();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _inputFocusNode.requestFocus();
      });
    } else {
      TtsController.instance.stop();
      setState(() => _finished = true);
    }
  }

  void _retryWrong() {
    final wrongItems = _results.where((r) => !(r['correct'] as bool)).map((r) => r['item']).toList();
    if (wrongItems.isEmpty) return;
    setState(() {
      _questions = wrongItems..shuffle();
      _currentIdx = 0;
      _results = [];
      _wrongCounts = {};
      _finished = false;
      _ttsPlayed = false;
      _answerCtrl.clear();
    });
    _playCurrentTts();
  }

  void _retryAll() {
    setState(() {
      _started = false;
      _finished = false;
      _results = [];
      _wrongCounts = {};
      _answerCtrl.clear();
    });
  }

  Future<void> _saveWrongAsGroup(List<dynamic> wrongItems) async {
    if (wrongItems.isEmpty) return;
    final nameCtrl = TextEditingController(text: '오답노트 ${DateTime.now().month}/${DateTime.now().day}');
    Color selectedColor = kGroupColors[0];
    await showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('오답 그룹 저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        _lbl('그룹 이름'),
        TextField(controller: nameCtrl, decoration: _inputDeco('')),
        const SizedBox(height: 12),
        _lbl('색상'),
        Wrap(spacing: 8, runSpacing: 8, children: kGroupColors.map((c) => GestureDetector(
          onTap: () => setS(() => selectedColor = c),
          child: Container(width: 28, height: 28,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle,
              border: Border.all(color: selectedColor.value == c.value ? Colors.black : Colors.transparent, width: 2)),
            child: selectedColor.value == c.value ? const Icon(Icons.check, color: Colors.white, size: 14) : null))).toList()),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () async {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            final gid = DateTime.now().millisecondsSinceEpoch.toString();
            await Store.saveGroup(GroupModel(id: gid, name: name, colorValue: selectedColor.value));
            for (final item in wrongItems) {
              if (item is AbbreviationModel) {
                await Store.saveAbbreviation(item.copyWith(groupId: gid));
              }
            }
            if (ctx.mounted) Navigator.pop(ctx);
            if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('$name 그룹에 저장했어요'), backgroundColor: kBlue,
                  duration: const Duration(seconds: 2)));
          },
          child: const Text('저장')),
      ])));
  }

  void _copyForAI(List<dynamic> wrongItems) {
    final words = wrongItems
        .whereType<AbbreviationModel>()
        .map((a) => a.displayWord.replaceAll('*', ' '))
        .join(', ');
    final prompt = '다음 약어들을 모두 포함한 자연스러운 한국어 문장을 만들어줘: $words';
    Clipboard.setData(ClipboardData(text: prompt));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('AI 문장 생성 프롬프트가 복사됐어요'), backgroundColor: kBlue,
          duration: Duration(seconds: 2)));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('abbreviations').listenable(),
      builder: (context, _, __) => ValueListenableBuilder(
        valueListenable: Hive.box('sentences').listenable(),
        builder: (context, __, ___) {
          if (!_started) return _buildSetup();
          if (_finished) return _buildResult();
          return _buildQuiz();
        }));
  }

  // ── 설정 화면 ──
Widget _buildSetup() {
    final groups = Store.getGroups();
    return Scaffold(backgroundColor: Colors.white,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('테스트 설정', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 24),

        // TTS 속도
// 문제 수 + TTS 속도
        Row(children: [
          _lbl('문제 수'),
          const Spacer(),
          _lbl('TTS 속도'),
        ]),
        Row(children: [
          // 문제 수 버튼
          GestureDetector(
            onTap: () => setState(() => _quizCount = (_quizCount - 1).clamp(1, 9999)),
            child: Container(width: 36, height: 36,
              decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.remove_rounded, color: kBlue, size: 20))),
          const SizedBox(width: 8),
          SizedBox(width: 60, child: TextField(
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.w900, color: kBlueDark, fontSize: 16),
            decoration: InputDecoration(
              isDense: true,
              hintText: '$_quizCount',
              hintStyle: const TextStyle(fontWeight: FontWeight.w900, color: kBlueDark, fontSize: 16),
              contentPadding: const EdgeInsets.symmetric(vertical: 8),
              filled: true, fillColor: kBlueLight,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none)),
            onSubmitted: (v) {
              final n = int.tryParse(v);
              if (n != null && n > 0) setState(() => _quizCount = n);
            })),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => setState(() => _quizCount = (_quizCount + 1).clamp(1, 9999)),
            child: Container(width: 36, height: 36,
              decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.add_rounded, color: kBlue, size: 20))),
          const Spacer(),
          // TTS 속도 버튼
          GestureDetector(
            onTap: () async {
              final speeds = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];
              final cur = TtsController.instance.speed;
              final idx = speeds.indexWhere((s) => s >= cur);
              if (idx > 0) {
                TtsController.instance.speed = speeds[idx - 1];
                await TtsController.instance.applySettings();
                setState(() {});
              }
            },
            child: Container(width: 36, height: 36,
              decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.remove_rounded, color: kBlue, size: 20))),
          const SizedBox(width: 8),
          Container(
            width: 70, padding: const EdgeInsets.symmetric(vertical: 8),
            decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
            child: Text(() {
              final v = TtsController.instance.speed;
              if (v <= 0.2) return '매우 느림';
              if (v <= 0.4) return '느림';
              if (v <= 0.6) return '보통';
              if (v <= 0.8) return '빠름';
              return '매우 빠름';
            }(), textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: kBlueDark, fontWeight: FontWeight.w700))),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () async {
              final speeds = [0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0];
              final cur = TtsController.instance.speed;
              final idx = speeds.lastIndexWhere((s) => s <= cur);
              if (idx < speeds.length - 1) {
                TtsController.instance.speed = speeds[idx + 1];
                await TtsController.instance.applySettings();
                setState(() {});
              }
            },
            child: Container(width: 36, height: 36,
              decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.add_rounded, color: kBlue, size: 20))),
        ]),
        const SizedBox(height: 32),
        // 모드 선택
        _lbl('테스트 유형'),
        Row(children: [
          _ModeChip(label: '약어', value: 'abbr', selected: _mode, onTap: (v) => setState(() { _mode = v; _filterGroupId = null; })),
          const SizedBox(width: 8),
          _ModeChip(label: '문장', value: 'sentence', selected: _mode, onTap: (v) => setState(() { _mode = v; _filterGroupId = null; })),
          const SizedBox(width: 8),
          _ModeChip(label: '둘 다', value: 'both', selected: _mode, onTap: (v) => setState(() { _mode = v; _filterGroupId = null; })),
        ]),
        const SizedBox(height: 20),

        // 그룹 필터
        if (_mode == 'abbr' && groups.isNotEmpty) ...[
          _lbl('그룹 필터'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            GestureDetector(
              onTap: () => setState(() => _filterGroupId = null),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _filterGroupId == null ? kBlue : kBlueLight,
                  borderRadius: BorderRadius.circular(20)),
                child: Text('전체', style: TextStyle(
                    color: _filterGroupId == null ? Colors.white : kBlue,
                    fontWeight: FontWeight.w700, fontSize: 12)))),
            ...groups.map((g) => GestureDetector(
              onTap: () => setState(() => _filterGroupId = g.id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _filterGroupId == g.id ? g.color : kBlueLight,
                  borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  CircleAvatar(backgroundColor: _filterGroupId == g.id ? Colors.white : g.color, radius: 5),
                  const SizedBox(width: 5),
                  Text(g.name, style: TextStyle(
                      color: _filterGroupId == g.id ? Colors.white : g.color,
                      fontWeight: FontWeight.w700, fontSize: 12)),
                ])))),
          ]),
          const SizedBox(height: 20),
        ],


        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _start,
          style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('테스트 시작', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))),
      ]))));
  }

  // ── 퀴즈 진행 화면 ──
Widget _buildQuiz() {
    final tts = TtsController.instance;
    final progress = (_currentIdx + 1) / _questions.length;
    return Scaffold(backgroundColor: Colors.white,
      body: SafeArea(child: KeyboardListener(
        focusNode: _keyboardFocusNode,
        autofocus: true,
        onKeyEvent: (event) {
          if (event is KeyDownEvent && (
              event.logicalKey == LogicalKeyboardKey.shift ||
              event.logicalKey == LogicalKeyboardKey.shiftLeft ||
              event.logicalKey == LogicalKeyboardKey.shiftRight)) {
            _playCurrentTts();
          }
        },
        child: Column(children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 16, 20, 0), child: Column(children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              Text('${_currentIdx + 1} / ${_questions.length}',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: kBlueDark)),
              TextButton(onPressed: () => setState(() { _started = false; TtsController.instance.stop(); }),
                child: const Text('그만하기', style: TextStyle(color: Colors.grey, fontSize: 12))),
            ]),
            const SizedBox(height: 6),
            LinearProgressIndicator(value: progress, backgroundColor: kBlueLight, color: kBlue,
                borderRadius: BorderRadius.circular(4), minHeight: 6),
          ])),
          Expanded(child: SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const SizedBox(height: 16),
              Center(child: GestureDetector(
                onTap: _playCurrentTts,
                child: Container(
                  width: 80, height: 80,
                  decoration: BoxDecoration(
                    color: tts.playing ? kBlue : kBlueLight,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: kBlue.withOpacity(0.2), blurRadius: 12, spreadRadius: 2)]),
                  child: Icon(tts.playing ? Icons.volume_up_rounded : Icons.play_circle_rounded,
                      color: tts.playing ? Colors.white : kBlue, size: 36)))),
              const SizedBox(height: 6),
              Center(child: Text(
                tts.playing ? '읽는 중... (Shift로 다시 듣기)' : (_ttsPlayed ? '다시 듣기 (Shift)' : '눌러서 듣기'),
                style: TextStyle(fontSize: 12, color: tts.playing ? kBlue : Colors.grey))),
              const SizedBox(height: 16),
              // 속도 조절
              Row(children: [
                GestureDetector(
                  onTap: () async {
                    TtsController.instance.speed = (TtsController.instance.speed - 0.1).clamp(0.1, 1.0);
                    await TtsController.instance.applySettings();
                    setState(() {});
                    _inputFocusNode.requestFocus();
                  },
                  child: Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.remove_rounded, color: kBlue, size: 20))),
                const SizedBox(width: 8),
                Container(
                  width: 70, padding: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
                  child: Text(() {
                    final v = TtsController.instance.speed;
                    if (v <= 0.2) return '매우 느림';
                    if (v <= 0.4) return '느림';
                    if (v <= 0.6) return '보통';
                    if (v <= 0.8) return '빠름';
                    return '매우 빠름';
                  }(), textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 12, color: kBlueDark, fontWeight: FontWeight.w700))),
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () async {
                    TtsController.instance.speed = (TtsController.instance.speed + 0.1).clamp(0.1, 1.0);
                    await TtsController.instance.applySettings();
                    setState(() {});
                    _inputFocusNode.requestFocus();
                  },
                  child: Container(width: 36, height: 36,
                    decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
                    child: const Icon(Icons.add_rounded, color: kBlue, size: 20))),
                const SizedBox(width: 8),
                const Text('속도', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 20),
              _lbl('들은 내용을 입력하세요'),
              TextField(
                controller: _answerCtrl,
                focusNode: _inputFocusNode,
                maxLines: 1,
                autofocus: true,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _submit(),
                decoration: InputDecoration(
                  hintText: '답변 후 엔터...',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: kBlue))),
              ),
              const SizedBox(height: 16),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: _submit,
                style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(_currentIdx < _questions.length - 1 ? '제출 → 다음' : '제출 → 결과 보기',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)))),
            ]))),
        ]))));
  }
  
  Widget _buildResult() {
    final total = _results.length;
    final correct = _results.where((r) => r['correct'] as bool).length;
    final wrongResults = _results.where((r) => !(r['correct'] as bool)).toList();
    final wrongItems = wrongResults.map((r) => r['item']).toList();
    final wrongAbbrItems = wrongItems.whereType<AbbreviationModel>().toList();

    // 많이 틀린 단어 순 정렬
    final sortedWrong = _wrongCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Scaffold(backgroundColor: Colors.white,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('결과', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),

        // 점수 카드
        Container(
          width: double.infinity, padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(16)),
          child: Column(children: [
            Text('$correct / $total',
                style: const TextStyle(fontSize: 40, fontWeight: FontWeight.w900, color: kBlueDark)),
            Text('${(correct / total * 100).round()}점',
                style: const TextStyle(fontSize: 18, color: kBlue, fontWeight: FontWeight.w700)),
          ])),
        const SizedBox(height: 20),

        // 다시 시작 버튼
        Row(children: [
          Expanded(child: OutlinedButton.icon(
            onPressed: wrongResults.isEmpty ? null : _retryWrong,
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('틀린 것만 다시'),
            style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBlue),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12)))),
          const SizedBox(width: 10),
          Expanded(child: ElevatedButton.icon(
            onPressed: _retryAll,
            icon: const Icon(Icons.casino_rounded, size: 16),
            label: const Text('처음부터 다시'),
            style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                padding: const EdgeInsets.symmetric(vertical: 12)))),
        ]),
        const SizedBox(height: 20),

        // 오답 목록
        if (wrongResults.isNotEmpty) ...[
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('틀린 문제 (${wrongResults.length}개)',
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey)),
            Row(children: [
              if (wrongAbbrItems.isNotEmpty) ...[
                GestureDetector(
                  onTap: () => _copyForAI(wrongAbbrItems),
                  child: _actionChip(Icons.content_copy_rounded, 'AI 복사', kBlueSky)),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: () => _saveWrongAsGroup(wrongAbbrItems),
                  child: _actionChip(Icons.folder_rounded, '그룹 저장', kBlue)),
              ],
            ]),
          ]),
          const SizedBox(height: 8),
          ...wrongResults.map((r) {
            final wrongWords = (r['wrong'] as List<String>);
            return Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE0E0))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.close_rounded, color: Colors.red, size: 14),
                  const SizedBox(width: 4),
                  Expanded(child: Text(r['question'] as String,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                ]),
                const SizedBox(height: 4),
                Text('내 답: ${r['userAnswer']}',
                    style: const TextStyle(fontSize: 12, color: Colors.grey)),
                if (wrongWords.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Wrap(spacing: 4, children: wrongWords.map((w) => Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(4)),
                    child: Text(w, style: const TextStyle(fontSize: 11, color: Colors.red, fontWeight: FontWeight.w700)))).toList()),
                ],
              ]));
          }),
          const SizedBox(height: 20),
        ],

        // 많이 틀린 단어 순위
        if (sortedWrong.isNotEmpty) ...[
          const Text('많이 틀린 단어',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Colors.grey)),
          const SizedBox(height: 8),
          ...sortedWrong.take(10).map((e) => Container(
            margin: const EdgeInsets.only(bottom: 6), padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: const Color(0xFFFFF8F0), borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFFFE0B0))),
            child: Row(children: [
              Expanded(child: Text(e.key,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
              Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(color: const Color(0xFFFF9800), borderRadius: BorderRadius.circular(10)),
                child: Text('${e.value}회',
                    style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w700))),
            ]))),
        ],
      ]))));
  }
}

class _ModeChip extends StatelessWidget {
  final String label, value, selected;
  final void Function(String) onTap;
  const _ModeChip({required this.label, required this.value, required this.selected, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final isSel = value == selected;
    return GestureDetector(
      onTap: () => onTap(value),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: isSel ? kBlue : kBlueLight,
          borderRadius: BorderRadius.circular(20)),
        child: Text(label, style: TextStyle(
            color: isSel ? Colors.white : kBlue,
            fontWeight: FontWeight.w700, fontSize: 13))));
  }
}