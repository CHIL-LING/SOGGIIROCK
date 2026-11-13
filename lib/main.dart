import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:flutter/scheduler.dart';
import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Hive.initFlutter();
  await Hive.openBox('abbreviations');
  await Hive.openBox('studyRecords');
  await Hive.openBox('sentences');
  await Hive.openBox('reminders');
  await Hive.openBox('groups');
  await Hive.openBox('settings'); // 추가
  await Hive.openBox('quizWrongLog'); // 테스트 오답 기록(역대 통계용)
  await Hive.openBox('typingSessions'); // 순공시간(타이핑) 세션 기록
  TtsController.instance._init(); // Hive 열린 후 설정 로드
  await TypingTracker.instance.init(); // 지난 실행에서 저장 못 한 세션 복구
  await TypingTracker.sprint.init();   // 스프린트 세션도 복구
  runApp(const SoggiApp());
}

const Color kBlue        = Color(0xFF1A6CF6);
const Color kBlueSky     = Color(0xFF398FCC);
const Color kBlueLight   = Color(0xFFE8F0FE);
const Color kBlueDark    = Color(0xFF0F4AB3);
const Color kPurple      = Color(0xFF6a8fa9);
const Color kPurpleLight = Color(0xFFF3EFFE);
const Color kTimerBg     = Color(0xFFBED3F7);

// 리마인드 → 테스트 이동 시 새 화면을 덮지 않고 하단 바가 있는 테스트 탭으로 전환하기 위한 알림자
final ValueNotifier<int?> kTabRequest = ValueNotifier<int?>(null);
final ValueNotifier<List<AbbreviationModel>?> kQuizPreset = ValueNotifier<List<AbbreviationModel>?>(null);

const List<Color> kGroupColors = [
  Color(0xFF1A6CF6), Color(0xFFE53935), Color(0xFF43A047),
  Color(0xFFFB8C00), Color(0xFF8E24AA), Color(0xFF00897B),
  Color(0xFFD81B60), Color(0xFF3949AB), Color(0xFF6D4C41),
  Color(0xFF546E7A), Color(0xFFFFB300), Color(0xFF00ACC1),
];

String encodeWord(String raw) => raw.replaceAll(' ', '*');
String decodeWordForSearch(String word) => word.replaceAll('*', '');

// 즐겨찾기는 "분류"가 아니라 그룹으로 취급한다. 저장되지 않는 가상(고정) 그룹.
const String kFavGroupId = '__favorite__';
final GroupModel kFavGroup = GroupModel(id: kFavGroupId, name: '⭐ 즐겨찾기', colorValue: 0xFFFFAA00, order: -1);

// ═══════════════════════════════════════════════════════════════════
// 공용 헬퍼 / 공용 위젯
// ═══════════════════════════════════════════════════════════════════

// 날짜를 'YYYY-MM-DD' 문자열로
String _ymd(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

// TTS 속도 라벨 (단계 조절 UI와 TTS 컨트롤바가 같이 사용)
String ttsSpeedLabel(double v) {
  if (v <= 0.2) return '매우 느림';
  if (v <= 0.4) return '느림';
  if (v <= 0.6) return '보통';
  if (v <= 0.8) return '빠름';
  return '매우 빠름';
}

// TTS 속도 - / 라벨 / + 조절 (0.1 단위, 0.1~1.0)
class _TtsSpeedStepper extends StatelessWidget {
  final VoidCallback? onChanged; // 속도가 바뀐 뒤 호출 (화면 갱신 등)
  const _TtsSpeedStepper({this.onChanged});

  Future<void> _step(bool up) async {
    final cur = TtsController.instance.speed;
    final next = up
        ? ((cur * 10 + 1e-6).floor() + 1) / 10
        : ((cur * 10 - 1e-6).ceil() - 1) / 10;
    TtsController.instance.speed = next.clamp(0.1, 1.0).toDouble();
    await TtsController.instance.applySettings();
    onChanged?.call();
  }

  Widget _btn(IconData icon, bool up) => GestureDetector(
    onTap: () => _step(up),
    child: Container(width: 36, height: 36,
      decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
      child: Icon(icon, color: kBlue, size: 20)));

  @override
  Widget build(BuildContext context) => Row(mainAxisSize: MainAxisSize.min, children: [
    _btn(Icons.remove_rounded, false),
    const SizedBox(width: 8),
    Container(
      width: 70, padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
      child: Text(ttsSpeedLabel(TtsController.instance.speed), textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 12, color: kBlueDark, fontWeight: FontWeight.w700))),
    const SizedBox(width: 8),
    _btn(Icons.add_rounded, true),
  ]);
}

// 선택 모드 공통 동작 (약어 검색 / 문장 등록 / 리마인드 화면에서 같이 사용)
mixin _SelectionMixin<T extends StatefulWidget> on State<T> {
  final Set<String> _selected = {};
  bool _selectMode = false;

  void _toggleSelectMode() => setState(() { _selectMode = !_selectMode; _selected.clear(); });
  void _toggleSelect(String id) => setState(() {
    if (_selected.contains(id)) _selected.remove(id); else _selected.add(id);
  });
  void _exitSelectMode() => setState(() { _selected.clear(); _selectMode = false; });

  // 선택 삭제 확인 팝업 (삭제를 누르면 true)
  Future<bool> _confirmBulkDelete(BuildContext context) async {
    final ok = await showDialog<bool>(context: context, builder: (c) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('선택 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('선택한 ${_selected.length}개를 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(c, true), child: const Text('삭제'))]));
    return ok == true;
  }
}

final _analyzerCtrl     = TextEditingController();
bool  _analyzerAnalyzed = false;
bool  _analyzerPadOn = false; // 약어확인 화면의 연습장(좌우 분할) 켜짐 여부
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

// 헤더 상단 필터/정렬용 통일된 라벨 칩 (활성화 여부에 따라 색이 강조됨)
Widget _toolChip(IconData icon, String label, {bool active = false, Color color = kBlue}) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
  decoration: BoxDecoration(
    color: active ? color.withOpacity(0.12) : kBlueLight,
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: active ? color : Colors.transparent, width: 1.2)),
  child: Row(mainAxisSize: MainAxisSize.min, children: [
    Icon(icon, size: 15, color: active ? color : Colors.grey.shade600),
    const SizedBox(width: 4),
    Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: active ? color : Colors.grey.shade600)),
  ]));

// 헤더 상단 아이콘 전용 원형 버튼 (선택모드 토글, 그룹관리 이동 등 라벨 없는 내비게이션용)
Widget _iconToolBtn(IconData icon, {Color color = kBlue}) => Container(
  padding: const EdgeInsets.all(8),
  decoration: const BoxDecoration(color: kBlueLight, shape: BoxShape.circle),
  child: Icon(icon, size: 16, color: color));

Widget _lbl(String text) => Padding(padding: const EdgeInsets.only(bottom: 6),
  child: Text(text, style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w600)));

InputDecoration _inputDeco(String? hint) => InputDecoration(
  hintText: hint, isDense: true,
  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: const BorderSide(color: kBlue)));

// 확인 다이얼로그에서 엔터(Enter)로 바로 확정할 수 있게 해주는 래퍼
// - 포커스 위치와 상관없이 "지금 맨 위에 떠 있는 창"에서만 Enter를 받는다.
// - 여러 줄 입력칸(메모 등)에 커서가 있으면 Enter는 줄바꿈으로 남겨 두고, Ctrl+Enter로 확정한다.
// - 같은 Enter가 두 번 처리되지 않게 짧은 시간 안의 중복 입력은 무시한다.
DateTime _enterConfirmLast = DateTime.fromMillisecondsSinceEpoch(0);

class _EnterToConfirm extends StatefulWidget {
  final Widget child;
  final VoidCallback onConfirm;
  const _EnterToConfirm({required this.child, required this.onConfirm});
  @override State<_EnterToConfirm> createState() => _EnterToConfirmState();
}
class _EnterToConfirmState extends State<_EnterToConfirm> {
  @override void initState() { super.initState(); HardwareKeyboard.instance.addHandler(_onKey); }
  @override void dispose() { HardwareKeyboard.instance.removeHandler(_onKey); super.dispose(); }

  bool _focusInMultiline() {
    final fctx = FocusManager.instance.primaryFocus?.context;
    if (fctx == null) return false;
    final editable = fctx.findAncestorWidgetOfExactType<EditableText>();
    if (editable == null || editable.maxLines == 1) return false;
    // 이 창 안에 있는 여러 줄 입력칸일 때만 해당 (뒤쪽 화면의 입력칸은 무시)
    bool inside = false;
    final me = context as Element;
    fctx.visitAncestorElements((e) {
      if (identical(e, me)) { inside = true; return false; }
      return true;
    });
    return inside;
  }

  bool _onKey(KeyEvent event) {
    if (!mounted || event is! KeyDownEvent) return false;
    final k = event.logicalKey;
    if (k != LogicalKeyboardKey.enter && k != LogicalKeyboardKey.numpadEnter) return false;
    final route = ModalRoute.of(context);
    if (route == null || !route.isCurrent) return false;
    if (_focusInMultiline() && !HardwareKeyboard.instance.isControlPressed) return false;
    final now = DateTime.now();
    if (now.difference(_enterConfirmLast).inMilliseconds < 350) return true;
    _enterConfirmLast = now;
    widget.onConfirm();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

class GroupModel {
  final String id, name;
  final int colorValue;
  final int order;
  GroupModel({required this.id, required this.name, required this.colorValue, this.order = 0});
  Color get color => Color(colorValue);
  Map<String, dynamic> toMap() => {'id': id, 'name': name, 'colorValue': colorValue, 'order': order};
  factory GroupModel.fromMap(Map m) => GroupModel(
    id: m['id'] as String, name: m['name'] as String, colorValue: m['colorValue'] as int,
    order: m['order'] as int? ?? 0);
}

class AbbreviationModel {
  final String id, word;
  final List<String> initial, medial, final_;
  final bool isComposite, isConcurrent, isAttached;
  final List<String> groupIds;
  AbbreviationModel({
    required this.id, required this.word,
    this.initial = const [], this.medial = const [], this.final_ = const [],
    this.isComposite = false, this.isConcurrent = false,
    this.isAttached = false,
    this.groupIds = const [],
  });

  // 즐겨찾기 = "__favorite__" 가상 그룹에 속해 있는지 여부 (그룹 기반)
  bool get isFavorite => groupIds.contains(kFavGroupId);

  // 퀴즈에서 읽어 주고 정답으로 쓰는 문구 (* 는 띄어쓰기)
  String get quizText => word.replaceAll('*', ' ');
  String get searchKey => decodeWordForSearch(word);
  String get displayWord => word;

Map<String, dynamic> toMap() => {
    'id': id, 'word': word, 'initial': initial, 'medial': medial, 'final_': final_,
    'isComposite': isComposite, 'isConcurrent': isConcurrent,
    'isAttached': isAttached, 'groupIds': groupIds,
  };
  factory AbbreviationModel.fromMap(Map m) {
    final gids = m['groupIds'] != null
        ? List<String>.from(m['groupIds'])
        : (m['groupId'] != null ? [m['groupId'] as String] : <String>[]);
    // 이전 버전 호환: 예전에 isFavorite 불리언으로 저장된 데이터는 즐겨찾기 그룹으로 자동 편입
    if ((m['isFavorite'] as bool? ?? false) && !gids.contains(kFavGroupId)) {
      gids.add(kFavGroupId);
    }
    return AbbreviationModel(
      id: m['id'] as String, word: m['word'] as String,
      initial: List<String>.from(m['initial'] ?? []),
      medial: List<String>.from(m['medial'] ?? []),
      final_: List<String>.from(m['final_'] ?? []),
      isComposite: m['isComposite'] as bool? ?? false,
      isConcurrent: m['isConcurrent'] as bool? ?? false,
      isAttached: m['isAttached'] as bool? ?? false,
      groupIds: gids,
    );
  }
  AbbreviationModel copyWith({
    String? word, List<String>? initial, List<String>? medial, List<String>? final_,
    bool? isComposite, bool? isConcurrent, bool? isAttached, bool? isFavorite,
    List<String>? groupIds,
  }) {
    final newGroupIds = List<String>.from(groupIds ?? this.groupIds);
    if (isFavorite != null) {
      if (isFavorite) {
        if (!newGroupIds.contains(kFavGroupId)) newGroupIds.add(kFavGroupId);
      } else {
        newGroupIds.remove(kFavGroupId);
      }
    }
    return AbbreviationModel(
      id: id, word: word ?? this.word, initial: initial ?? this.initial,
      medial: medial ?? this.medial, final_: final_ ?? this.final_,
      isComposite: isComposite ?? this.isComposite, isConcurrent: isConcurrent ?? this.isConcurrent,
      isAttached: isAttached ?? this.isAttached,
      groupIds: newGroupIds,
    );
  }

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
  static Box get _qw => Hive.box('quizWrongLog');

  // 실제로 Hive에 저장된 그룹만 (그룹 관리 화면에서 사용, 즐겨찾기 가상그룹 제외)
  // order값이 같은 게 있으면(구버전 데이터, 전부 0 등) 원래 저장 순서를 유지하도록 안정 정렬
  static List<GroupModel> getRealGroups() {
    final list = _gr.values.map((e) => GroupModel.fromMap(Map.from(e as Map))).toList();
    final indexed = list.asMap().entries.toList()
      ..sort((e1, e2) {
        final c = e1.value.order.compareTo(e2.value.order);
        return c != 0 ? c : e1.key.compareTo(e2.key);
      });
    return indexed.map((e) => e.value).toList();
  }
  // 즐겨찾기 가상그룹을 맨 앞에 포함한 전체 그룹 목록 (선택/필터/표시용)
  static List<GroupModel> getGroups() => [kFavGroup, ...getRealGroups()];
  static Future<void> saveGroup(GroupModel g) => _gr.put(g.id, g.toMap());
  static Future<void> deleteGroup(String id) => _gr.delete(id);
  static GroupModel? findGroup(String id) {
    if (id == kFavGroupId) return kFavGroup;
    try { return getRealGroups().firstWhere((g) => g.id == id); } catch (_) { return null; }
  }
  static int nextGroupOrder() {
    final list = getRealGroups();
    return list.isEmpty ? 0 : list.map((g) => g.order).reduce((a, b) => a > b ? a : b) + 1;
  }
  // 순서 목록 전체를 0,1,2... 순번으로 다시 저장 (기존 order값 중복 여부와 상관없이 항상 확실하게 순번을 재배정)
  static Future<void> _reassignOrders(List<GroupModel> orderedList) async {
    for (int i = 0; i < orderedList.length; i++) {
      final g = orderedList[i];
      if (g.order != i) {
        await saveGroup(GroupModel(id: g.id, name: g.name, colorValue: g.colorValue, order: i));
      }
    }
  }
  static Future<void> moveGroupUp(String id) async {
    final list = getRealGroups();
    final idx = list.indexWhere((g) => g.id == id);
    if (idx <= 0) return;
    final newList = List<GroupModel>.from(list);
    final tmp = newList[idx];
    newList[idx] = newList[idx - 1];
    newList[idx - 1] = tmp;
    await _reassignOrders(newList);
  }
  static Future<void> moveGroupDown(String id) async {
    final list = getRealGroups();
    final idx = list.indexWhere((g) => g.id == id);
    if (idx == -1 || idx >= list.length - 1) return;
    final newList = List<GroupModel>.from(list);
    final tmp = newList[idx];
    newList[idx] = newList[idx + 1];
    newList[idx + 1] = tmp;
    await _reassignOrders(newList);
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

  // ── 테스트 기록 (연속 정답 · 마지막 테스트 · TTS 오류 · 오답 로그) ─────────────
  // 연속 정답 추적: 특정 약어를 연속으로 맞춘 횟수 저장/조회/초기화
  static Future<void> logQuizCorrect(String text) async {
    final box = Hive.box('settings');
    final key = '_streak_${text.hashCode}';
    final cur = box.get(key, defaultValue: 0) as int;
    await box.put(key, cur + 1);
  }
  static int getStreak(String text) {
    return Hive.box('settings').get('_streak_${text.hashCode}', defaultValue: 0) as int;
  }
  static Future<void> resetStreak(String text) async {
    await Hive.box('settings').put('_streak_${text.hashCode}', 0);
  }

  // 약어별 마지막 테스트 시각 기록 (묵은 약어 선택용)
  static Future<void> logQuizSeen(String text) =>
      Hive.box('settings').put('_lastseen_${text.hashCode}', DateTime.now().millisecondsSinceEpoch);
  static DateTime? getLastSeen(String text) {
    final v = Hive.box('settings').get('_lastseen_${text.hashCode}');
    return v is int ? DateTime.fromMillisecondsSinceEpoch(v) : null;
  }

  // TTS 오류(소리가 이상하게 들리는) 약어 목록: 이후 테스트에서 자동으로 텍스트를 보여줌
  static const String _ttsErrKey = '_tts_error_list';
  static List<String> getTtsErrors() =>
      List<String>.from(Hive.box('settings').get(_ttsErrKey, defaultValue: <String>[]) as List);
  static bool isTtsError(String text) => getTtsErrors().contains(text);
  static Future<void> addTtsError(String text) async {
    final list = getTtsErrors();
    if (list.contains(text)) return;
    list.add(text);
    await Hive.box('settings').put(_ttsErrKey, list);
  }
  static Future<void> removeTtsError(String text) async {
    final list = getTtsErrors()..remove(text);
    await Hive.box('settings').put(_ttsErrKey, list);
  }

  // 오늘 테스트 정답률 기록
  static Future<void> logTodayQuizResult(int correct, int total) async {
    final box = Hive.box('settings');
    final today = DateTime.now();
    final key = '_quiz_result_${today.year}_${today.month}_${today.day}';
    await box.put(key, {'correct': correct, 'total': total, 'ts': today.toIso8601String()});
  }
  static Map<String, dynamic>? getTodayQuizResult() {
    final today = DateTime.now();
    final key = '_quiz_result_${today.year}_${today.month}_${today.day}';
    final v = Hive.box('settings').get(key);
    return v != null ? Map<String, dynamic>.from(v as Map) : null;
  }
  // 테스트에서 틀렸을 때 항목 전체 텍스트를 기록 (역대 오답 통계용)
  static Future<void> logQuizWrong(String text) =>
      _qw.add({'text': text, 'ts': DateTime.now().toIso8601String()});
  // 최근 N일간 틀린 횟수를 항목(전체 텍스트) 단위로 집계
  static Map<String, int> getRecentWrongCounts({int days = 7}) {
    final cutoff = DateTime.now().subtract(Duration(days: days));
    final counts = <String, int>{};
    for (final e in _qw.values) {
      final m = Map.from(e as Map);
      final ts = DateTime.tryParse(m['ts'] as String? ?? '');
      if (ts == null || ts.isBefore(cutoff)) continue;
      final text = m['text'] as String;
      counts[text] = (counts[text] ?? 0) + 1;
    }
    return counts;
  }

  // ── 취약점 분석 ──────────────────────────────────────────────────────────
  // 최근 오답에서 초/중/종성별 취약 패턴 분석
  static Map<String, Map<String, int>> analyzeWeakPoints({int days = 30}) {
    final wrongCounts = getRecentWrongCounts(days: days);
    final result = <String, Map<String, int>>{'cho': {}, 'jung': {}, 'jong': {}};
    for (final entry in wrongCounts.entries) {
      final decomp = _decomposeSoggi(entry.key);
      final weight = entry.value;
      for (final c in decomp['cho']!) { result['cho']![c] = (result['cho']![c] ?? 0) + weight; }
      for (final j in decomp['jung']!) { result['jung']![j] = (result['jung']![j] ?? 0) + weight; }
      for (final j in decomp['jong']!) { result['jong']![j] = (result['jong']![j] ?? 0) + weight; }
    }
    return result;
  }

  // 취약한 초/중/종성을 포함하는 약어 추천
  static List<AbbreviationModel> recommendByWeakPoints(Map<String, Map<String, int>> weakPoints, {int limit = 10}) {
    final abbrevs = getAbbreviations();
    final scored = <MapEntry<AbbreviationModel, int>>[];
    for (final a in abbrevs) {
      final decomp = _decomposeSoggi(a.word);
      int score = 0;
      for (final c in decomp['cho']!) { score += weakPoints['cho']![c] ?? 0; }
      for (final j in decomp['jung']!) { score += weakPoints['jung']![j] ?? 0; }
      for (final j in decomp['jong']!) { score += weakPoints['jong']![j] ?? 0; }
      if (score > 0) scored.add(MapEntry(a, score));
    }
    scored.sort((a, b) => b.value.compareTo(a.value));
    return scored.take(limit).map((e) => e.key).toList();
  }

  // ── CSV 내보내기/가져오기 ─────────────────────────────────────────────────
  static String exportCsv() {
    final abbrevs = getAbbreviations();
    final buf = StringBuffer();
    buf.writeln('word,initial,medial,final_,isComposite,isConcurrent,isAttached,groupIds');
    for (final a in abbrevs) {
      buf.writeln([
        _csvEsc(a.word),
        _csvEsc(a.initial.join('|')),
        _csvEsc(a.medial.join('|')),
        _csvEsc(a.final_.join('|')),
        a.isComposite ? '1' : '0',
        a.isConcurrent ? '1' : '0',
        a.isAttached ? '1' : '0',
        _csvEsc(a.groupIds.join('|')),
      ].join(','));
    }
    return buf.toString();
  }

  static String _csvEsc(String s) {
    if (s.contains(',') || s.contains('"') || s.contains('\n')) {
      return '"${s.replaceAll('"', '""')}"';
    }
    return s;
  }

  static Future<List<AbbreviationModel>> importCsv(String csv) async {
    final lines = csv.split('\n').map((l) => l.trim()).where((l) => l.isNotEmpty).toList();
    if (lines.length < 2) return [];
    final result = <AbbreviationModel>[];
    for (int i = 1; i < lines.length; i++) {
      try {
        final cols = _parseCsvLine(lines[i]);
        if (cols.length < 8) continue;
        result.add(AbbreviationModel(
          id: DateTime.now().millisecondsSinceEpoch.toString() + '_$i',
          word: cols[0],
          initial: cols[1].isEmpty ? [] : cols[1].split('|'),
          medial: cols[2].isEmpty ? [] : cols[2].split('|'),
          final_: cols[3].isEmpty ? [] : cols[3].split('|'),
          isComposite: cols[4] == '1',
          isConcurrent: cols[5] == '1',
          isAttached: cols[6] == '1',
          groupIds: cols[7].isEmpty ? [] : cols[7].split('|'),
        ));
      } catch (_) {}
    }
    return result;
  }

  static List<String> _parseCsvLine(String line) {
    final result = <String>[];
    bool inQuote = false;
    final buf = StringBuffer();
    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        if (inQuote && i + 1 < line.length && line[i + 1] == '"') { buf.write('"'); i++; }
        else inQuote = !inQuote;
      } else if (ch == ',' && !inQuote) { result.add(buf.toString()); buf.clear(); }
      else buf.write(ch);
    }
    result.add(buf.toString());
    return result;
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
    return _ymd(base);
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

// ── 순공시간(순수 타이핑 시간) ───────────────────────────────────────────────
// 연습장에서 타이핑한 시간만 측정한다. 키를 누르고 있던 시간을 합산하는 방식이 아니라,
// 연속해서 타이핑한 경과 시간을 잰다: 키 입력 사이 간격이 kTypingIdleMs 이하면 그 간격 전체를 더하고,
// 그보다 길면 쉬는 시간으로 보고 제외한다.
const int kTypingIdleMs = 5000;
const String kTypingOpenKey = '__open__';

const String kSrcPad = 'pad';       // 연습장
const String kSrcSprint = 'sprint'; // 스프린트
String typingSourceLabel(String src) => src == kSrcSprint ? '스프린트' : '연습장';

class TypingSession {
  final String id, date, source;
  final int startMs, endMs, activeMs, chars;
  const TypingSession({required this.id, required this.date, required this.startMs,
    required this.endMs, required this.activeMs, required this.chars, this.source = kSrcPad});
  Map<String, dynamic> toMap() => {'id': id, 'date': date, 'startMs': startMs,
    'endMs': endMs, 'activeMs': activeMs, 'chars': chars, 'source': source};
  factory TypingSession.fromMap(Map m) => TypingSession(
    id: m['id'] as String, date: m['date'] as String,
    startMs: (m['startMs'] as num).toInt(), endMs: (m['endMs'] as num).toInt(),
    activeMs: (m['activeMs'] as num).toInt(), chars: ((m['chars'] as num?) ?? 0).toInt(),
    source: (m['source'] as String?) ?? kSrcPad);
}

// 새벽 5시 이전은 전날로 취급 (기존 공부 기록과 같은 기준)
String _dateKeyFromMs(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final base = d.hour < 5 ? d.subtract(const Duration(days: 1)) : d;
  return _ymd(base);
}

// 00:12 (1시간 이상이면 01:02:03) — 초 미만 단위는 표시하지 않음
String formatTypingClock(int ms) {
  final totalSec = ms ~/ 1000;
  final sec = totalSec % 60;
  final min = (totalSec ~/ 60) % 60;
  final h = totalSec ~/ 3600;
  final core = '${min.toString().padLeft(2,'0')}:${sec.toString().padLeft(2,'0')}';
  return h > 0 ? '${h.toString().padLeft(2,'0')}:$core' : core;
}

// 1시간 02분 03초 (초 미만 단위는 표시하지 않음)
String formatTypingLong(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final sec = (ms % 60000) ~/ 1000;
  if (h > 0) return '$h시간 ${m.toString().padLeft(2,'0')}분 ${sec.toString().padLeft(2,'0')}초';
  if (m > 0) return '$m분 $sec초';
  return '$sec초';
}

// 합계용 요약: 2시간 10분 / 3분 12초 / 8초
String formatTypingTotal(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  final s = (ms % 60000) ~/ 1000;
  if (h > 0) return '$h시간 $m분';
  if (m > 0) return '$m분 $s초';
  return '$s초';
}

class TypingStore {
  static List<TypingSession> all() {
    final b = Hive.box('typingSessions');
    final out = <TypingSession>[];
    for (final k in b.keys) {
      if (k is String && k.startsWith('__open')) continue;
      final v = b.get(k);
      if (v is Map) {
        try { out.add(TypingSession.fromMap(Map.from(v))); } catch (_) {}
      }
    }
    out.sort((a, b) => a.startMs.compareTo(b.startMs));
    return out;
  }
  static List<TypingSession> forDate(String date) => all().where((s) => s.date == date).toList();
  static Set<String> dates() => all().map((s) => s.date).toSet();
  static Future<void> delete(String id) => Hive.box('typingSessions').delete(id);
}

class TypingTracker extends ChangeNotifier with WidgetsBindingObserver {
  // 연습장용(instance)과 스프린트용(sprint)을 따로 잰다. 둘 다 같은 순공시간 기록(typingSessions)에 쌓이고
  // 기록마다 어디서 쌓았는지(source)가 붙는다.
  static final TypingTracker instance = TypingTracker._(kSrcPad, kTypingOpenKey, 'ts_');
  static final TypingTracker sprint = TypingTracker._(kSrcSprint, '__open_sprint__', 'sp_');
  final String source, openKey, idPrefix;
  TypingTracker._(this.source, this.openKey, this.idPrefix);

  Box get _box => Hive.box('typingSessions');
  bool _active = false;
  int _startMs = 0, _lastKeyMs = 0, _activeMs = 0, _chars = 0, _prevLen = 0, _lastCheckpointMs = 0;
  Timer? _ticker;

  bool get active => _active;
  int get activeMs => _activeMs;
  int get chars => _chars;
  int get startMs => _startMs;
  bool get isTypingNow => _active && DateTime.now().millisecondsSinceEpoch - _lastKeyMs < 2000;

  Future<void> init() async {
    WidgetsBinding.instance.addObserver(this);
    // 앱이 갑자기 꺼져서 정상 종료되지 못한 세션이 있으면 마지막 기록 시점까지 저장
    final open = _box.get(openKey);
    if (open is Map) {
      try {
        final m = Map<String, dynamic>.from(open);
        final ms = (m['activeMs'] as num).toInt();
        final start = (m['startMs'] as num).toInt();
        if (ms > 0) {
          final sess = TypingSession(id: m['id'] as String, date: _dateKeyFromMs(start), startMs: start,
              endMs: (m['lastKeyMs'] as num).toInt(), activeMs: ms, chars: ((m['chars'] as num?) ?? 0).toInt(),
              source: source);
          await _box.put(sess.id, sess.toMap());
        }
      } catch (_) {}
      await _box.delete(openKey);
    }
  }

  // 연습장 글자 수를 직접 바꿨을 때(불러오기/지우기) 입력으로 세지 않도록 기준 길이를 맞춤
  void syncLength(int len) => _prevLen = len;

  // 연습장에서 글자가 바뀔 때마다 호출
  void onTextChanged(String text) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!_active) {
      _active = true;
      _startMs = now; _lastKeyMs = now; _activeMs = 0; _chars = 0; _lastCheckpointMs = 0;
      _ticker?.cancel();
      _ticker = Timer.periodic(const Duration(milliseconds: 500), (_) => notifyListeners());
    } else {
      final gap = now - _lastKeyMs;
      if (gap <= kTypingIdleMs) _activeMs += gap;
      _lastKeyMs = now;
    }
    final delta = text.length - _prevLen;
    _prevLen = text.length;
    if (delta > 0) _chars += delta;
    if (now - _lastCheckpointMs > 3000) _writeCheckpoint();
    notifyListeners();
  }

  // 진행 중인 세션을 임시 저장 (앱이 꺼져도 다음 실행 때 복구)
  void _writeCheckpoint() {
    if (!_active) return;
    _lastCheckpointMs = DateTime.now().millisecondsSinceEpoch;
    _box.put(openKey, {'id': '$idPrefix$_startMs', 'startMs': _startMs,
      'lastKeyMs': _lastKeyMs, 'activeMs': _activeMs, 'chars': _chars});
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _writeCheckpoint();
  }

  // 종료 → 세션 저장
  Future<TypingSession?> finish() async {
    if (!_active) return null;
    final sess = TypingSession(id: '$idPrefix$_startMs', date: _dateKeyFromMs(_startMs), startMs: _startMs,
        endMs: _lastKeyMs, activeMs: _activeMs, chars: _chars, source: source);
    _active = false;
    _ticker?.cancel(); _ticker = null;
    TypingSession? saved;
    if (sess.activeMs > 0) {
      await _box.put(sess.id, sess.toMap());
      saved = sess;
    }
    await _box.delete(openKey);
    _activeMs = 0; _chars = 0;
    notifyListeners();
    return saved;
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
              displayText: ttsSpeedLabel(tts.speed),
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
  final s = raw.replaceAll(' ', '*');
  final n = s.length;
  final words = abbrevs.where((a) => a.word.isNotEmpty).toList();
  // dp[i] = s[i..] 에서 얻을 수 있는 최선의 조합
  // 1순위: 약어가 덮는 글자 수가 많을수록, 2순위(덮는 글자 수가 같으면): 약어 조각 수가 적을수록(= 긴 약어 우선)
  final cnt = List<int>.filled(n + 1, 0);
  final cov = List<int>.filled(n + 1, 0);
  final pick = List<AbbreviationModel?>.filled(n + 1, null);
  for (int i = n - 1; i >= 0; i--) {
    cnt[i] = cnt[i + 1]; cov[i] = cov[i + 1]; pick[i] = null;
    for (final a in words) {
      final w = a.word;
      if (!s.startsWith(w, i)) continue;
      final j = i + w.length;
      final c = cnt[j] + 1, v = cov[j] + w.length;
      if (v > cov[i] || (v == cov[i] && c < cnt[i])) {
        cnt[i] = c; cov[i] = v; pick[i] = a;
      }
    }
  }
  final parts = <_Span>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isNotEmpty) {
      parts.add(_Span(text: buf.toString().replaceAll('*', ' '), type: 'normal'));
      buf.clear();
    }
  }
  int i = 0;
  while (i < n) {
    final a = pick[i];
    if (a == null) { buf.write(s[i]); i++; continue; }
    flush();
    String t = 'abbr';
    if (a.isConcurrent) t = 'concurrent';
    else if (a.isComposite) t = 'composite';
    parts.add(_Span(text: a.word.replaceAll('*', ' '), type: t, abbr: a));
    i += a.word.length;
  }
  flush();
  return parts;
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

// 약어 목록 정렬: alpha=가나다순, saved=저장 순서(기본, 원래 순서 유지), group=그룹순, type=분류순
List<AbbreviationModel> sortAbbreviations(List<AbbreviationModel> list, String mode, List<GroupModel> groups) {
  final result = List<AbbreviationModel>.from(list);
  switch (mode) {
    case 'alpha':
      result.sort((a, b) => a.searchKey.compareTo(b.searchKey));
      break;
    case 'group':
      int rank(AbbreviationModel a) {
        for (int i = 0; i < groups.length; i++) {
          if (a.groupIds.contains(groups[i].id)) return i;
        }
        return 999999;
      }
      result.sort((a, b) => rank(a).compareTo(rank(b)));
      break;
    case 'type':
      int rank(AbbreviationModel a) {
        if (a.isConcurrent) return 0;
        if (a.isComposite) return 1;
        if (a.isAttached) return 2;
        return 3;
      }
      result.sort((a, b) => rank(a).compareTo(rank(b)));
      break;
    case 'saved':
    default:
      break;
  }
  return result;
}
const Map<String, String> kSortModeLabels = {
  'saved': '저장 순서순', 'alpha': '가나다순', 'group': '그룹순', 'type': '분류순',
};

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
class _MainShellState extends State<MainShell> with SingleTickerProviderStateMixin {
  int _idx = 0;
  bool _hasReminder = false;
  late AnimationController _blinkCtrl;
  late Animation<double> _blinkAnim;

  final _screens = const [
    HomeScreen(), SentenceAnalyzerScreen(), SearchScreen(),
    SentenceRegisterScreen(), RemindersScreen(), QuizScreen(),
  ];
  @override
  void initState() {
    super.initState();
    _blinkCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))
      ..repeat(reverse: true);
    _blinkAnim = Tween<double>(begin: 0.4, end: 1.0).animate(_blinkCtrl);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkTodayReminders());
    kTabRequest.addListener(_onTabRequest);
  }

  void _onTabRequest() {
    final v = kTabRequest.value;
    if (v == null) return;
    kTabRequest.value = null;
    if (mounted) setState(() => _idx = v);
  }

  @override
  void dispose() {
    kTabRequest.removeListener(_onTabRequest);
    _blinkCtrl.dispose();
    super.dispose();
  }
void _checkTodayReminders() {
    final today = _todayStr();
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final settingsBox = Hive.box('settings');
    final dismissedKey = '_dismissed_$today';

    // 2,3번 조건: 오늘보다 이전 날짜인 리마인드는 자동으로 다음 주기로 넘기기
    for (final r in Store.getReminders()) {
      if (!r.active) continue;
      final d = DateTime.tryParse(r.date);
      if (d == null) continue;
      if (d.isBefore(todayDate)) {
        // 다음 주기로 넘기기
        var next = d;
        while (!next.isAfter(todayDate.subtract(const Duration(days: 1)))) {
          next = next.add(Duration(days: r.intervalDays));
        }
        final ds = _ymd(next);
        Store.saveReminder(ReminderModel(id: r.id, type: r.type, target: r.target,
            date: ds, intervalDays: r.intervalDays, repeat: r.repeat, active: r.active));
      }
    }

    // 오늘 "다시 보지 않음"을 이미 눌렀으면 팝업 없음
    if (settingsBox.get(dismissedKey) == true) return;

    // 오늘 날짜인 리마인드만 팝업
    final reminders = Store.getReminders().where((r) => r.active && r.date == today).toList();
    if (reminders.isEmpty) return;
    final abbrevs = Store.getAbbreviations();

    showDialog(context: context, barrierDismissible: true,
        builder: (_) => _TodayReminderDialog(reminders: reminders, abbrevs: abbrevs, todayKey: today))
      .then((_) {
        if (!mounted) return;
        final dismissed = settingsBox.get(dismissedKey) == true;
        setState(() => _hasReminder = !dismissed);
      });
  }
  String _todayStr() {
    final now = DateTime.now();
    final base = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
    return _ymd(base);
  }
  @override
  Widget build(BuildContext context) {
    final today = _todayStr();
    final reminders = Store.getReminders().where((r) => r.active && r.date == today).toList();
    final abbrevs = Store.getAbbreviations();
    return Scaffold(
      body: Stack(children: [
        IndexedStack(index: _idx, children: _screens),
        if (_hasReminder)
          Positioned(top: 48, left: 16,
            child: GestureDetector(
              onTap: () {
                showDialog(context: context, barrierDismissible: true,
                    builder: (_) => _TodayReminderDialog(
                        reminders: reminders, abbrevs: abbrevs, todayKey: today))
                  .then((_) {
                    if (!mounted) return;
                    final dismissed = Hive.box('settings').get('_dismissed_$today') == true;
                    setState(() => _hasReminder = !dismissed);
                  });
              },
              child: FadeTransition(opacity: _blinkAnim,
                child: Container(width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: kBlue, shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: kBlue.withOpacity(0.4), blurRadius: 8, spreadRadius: 2)]),
                  child: const Icon(Icons.notifications_rounded, color: Colors.white, size: 22))))),
      ]),
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
            BottomNavigationBarItem(icon: Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.quiz_rounded)), label: '공부방'),
          ]))));
  }
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
                  for (final r in widget.reminders) {
                    final next = DateTime.now().add(Duration(days: r.intervalDays));
                    final ds = _ymd(next);
                    Store.saveReminder(ReminderModel(id: r.id, type: r.type, target: r.target, date: ds,
                      intervalDays: r.intervalDays, repeat: r.repeat, active: r.active));
                  }
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

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override State<HomeScreen> createState() => _HomeScreenState();
}
class _HomeScreenState extends State<HomeScreen> {
  late DateTime _month; String? _selected;
  final _typingL = Hive.box('typingSessions').listenable(); // 순공시간 저장 시 달력 점 갱신용
  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _month = DateTime(now.year, now.month);
    _selected = _todayKey();
    StudyTimer.instance.addListener(_onTick);
    _typingL.addListener(_onTick);
  }
  @override void dispose() {
    StudyTimer.instance.removeListener(_onTick);
    _typingL.removeListener(_onTick);
    super.dispose();
  }
  void _onTick() { if (mounted) setState(() {}); }
  String _todayKey() {
    final now = DateTime.now();
    final base = now.hour < 5 ? now.subtract(const Duration(days: 1)) : now;
    return _ymd(base);
  }
  String _fmt(DateTime d) => _ymd(d);

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('studyRecords').listenable(),
      builder: (context, box, _) {
        final record = _selected != null ? Store.getRecord(_selected!) : null;
        final hasData = record?.hasData ?? false;
        final daysInMonth = DateTime(_month.year, _month.month + 1, 0).day;
        final firstWeekday = DateTime(_month.year, _month.month, 1).weekday % 7;
        final markedDates = Store.getRecordsWithData().map((r) => r.date).toSet();
        final typingDates = TypingStore.dates();
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
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const WeakPointScreen())),
                    child: Container(width: 34, height: 34,
                      decoration: BoxDecoration(color: const Color(0xFFF3E8FD), borderRadius: BorderRadius.circular(10)),
                      child: const Center(child: Icon(Icons.analytics_rounded, color: Color(0xFF7B5EA7), size: 20)))),
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
                      if (typingDates.contains(key))
                        Positioned(bottom: 2, child: Container(width: 4, height: 4,
                          decoration: BoxDecoration(color: isSel ? Colors.white : kPurple, shape: BoxShape.circle))),
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
            _TypingTimeCard(dateKey: _selected ?? _todayKey(), todayKey: _todayKey()),
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
            const SizedBox(height: 10),
            // 오늘 테스트 정답률 카드
            Builder(builder: (_) {
              final result = Store.getTodayQuizResult();
              if (result == null) return const SizedBox();
              final correct = result['correct'] as int;
              final total = result['total'] as int;
              final pct = total == 0 ? 0 : (correct * 100 / total).round();
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: pct >= 80 ? const Color(0xFFE8F5E9) : pct >= 60 ? const Color(0xFFFFF8E1) : const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(16)),
                  child: Row(children: [
                    Icon(pct >= 80 ? Icons.emoji_events_rounded : pct >= 60 ? Icons.trending_up_rounded : Icons.refresh_rounded,
                        color: pct >= 80 ? Colors.green : pct >= 60 ? Colors.orange : Colors.red, size: 28),
                    const SizedBox(width: 12),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('오늘 테스트', style: TextStyle(fontSize: 11, color: Colors.grey)),
                      Text('$pct% 정답  ($correct/$total)',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900,
                              color: pct >= 80 ? Colors.green.shade700 : pct >= 60 ? Colors.orange.shade700 : Colors.red.shade700)),
                    ]),
                  ])));
            }),
            const SizedBox(height: 10),
            // 이번 주 많이 틀린 TOP5
            Builder(builder: (_) {
              final wrong = Store.getRecentWrongCounts(days: 7).entries.toList()
                ..sort((a, b) => b.value.compareTo(a.value));
              final top5 = wrong.take(5).toList();
              if (top5.isEmpty) return const SizedBox();
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFFFF3F3), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('이번 주 많이 틀린 약어 TOP5', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.red)),
                    const SizedBox(height: 8),
                    ...top5.asMap().entries.map((e) => Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(children: [
                        Container(width: 20, height: 20, decoration: BoxDecoration(color: Colors.red, borderRadius: BorderRadius.circular(6)),
                          child: Center(child: Text('${e.key+1}', style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700)))),
                        const SizedBox(width: 8),
                        Expanded(child: Text(e.value.key, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600))),
                        Text('${e.value.value}번', style: const TextStyle(fontSize: 12, color: Colors.red)),
                      ]))),
                  ])));
            }),
            const SizedBox(height: 10),
            // 연속 정답 10회 이상 약어 (완전히 익힌 것)
            Builder(builder: (_) {
              final abbrevs = Store.getAbbreviations();
              final mastered = abbrevs.where((a) => Store.getStreak(a.displayWord.replaceAll('*',' ')) >= 10).toList();
              if (mastered.isEmpty) return const SizedBox();
              return Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(width: double.infinity, padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: const Color(0xFFE8F5E9), borderRadius: BorderRadius.circular(16)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.verified_rounded, color: Colors.green, size: 16),
                      const SizedBox(width: 6),
                      Text('완전히 익힌 약어 ${mastered.length}개', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green)),
                    ]),
                    const SizedBox(height: 6),
                    Wrap(spacing: 6, runSpacing: 4, children: mastered.take(10).map((a) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(color: Colors.green.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
                      child: Text(a.displayWord.replaceAll('*',' '), style: const TextStyle(fontSize: 12, color: Colors.green, fontWeight: FontWeight.w600)))).toList()),
                    if (mastered.length > 10) Padding(padding: const EdgeInsets.only(top: 4),
                      child: Text('+${mastered.length - 10}개 더', style: const TextStyle(fontSize: 11, color: Colors.grey))),
                  ])));
            }),
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
    bool busy = false; // Enter/버튼 중복 저장 방지
    showDialog(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
      Future<void> doSave() async {
        if (busy) return;
        busy = true;
        try {
          final rec = StudyRecordModel(date: date, studyHours: hours, studyMinutes: minutes,
            speechChars: speech, essayChars: essay,
            wpm: int.tryParse(wpmCtrl.text.trim()), memo: memoCtrl.text.trim());
          if (!rec.hasData) {
            Navigator.pop(ctx);
            if (context.mounted) showDialog(context: context, builder: (c2) => _EnterToConfirm(
              onConfirm: () => Navigator.pop(c2),
              child: AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('기록 없음', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
              content: const Text('하나 이상의 항목을 입력해 주세요.'),
              actions: [ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c2), child: const Text('확인'))])));
            return;
          }
          await Store.saveRecord(rec);
          if (ctx.mounted) Navigator.pop(ctx);
        } finally { busy = false; }
      }
      return _EnterToConfirm(onConfirm: doSave, child: AlertDialog(
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
            onPressed: doSave, child: const Text('저장')),
        ]));
      }));
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

// ── 순공시간 카드 (선택한 날짜의 타이핑 순공시간 + 세션 기록) ──────────────────
class _TypingTimeCard extends StatefulWidget {
  final String dateKey, todayKey;
  const _TypingTimeCard({required this.dateKey, required this.todayKey});
  @override State<_TypingTimeCard> createState() => _TypingTimeCardState();
}
class _TypingTimeCardState extends State<_TypingTimeCard> {
  bool _open = false;
  String _hm(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    return '${d.hour.toString().padLeft(2,'0')}:${d.minute.toString().padLeft(2,'0')}';
  }
  void _confirmDelete(BuildContext context, TypingSession s) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('순공시간 기록 삭제', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Text('${_hm(s.startMs)} ~ ${_hm(s.endMs)} (${formatTypingLong(s.activeMs)}) 기록을 삭제할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
          onPressed: () async { await TypingStore.delete(s.id); if (ctx.mounted) Navigator.pop(ctx); },
          child: const Text('삭제')),
      ]));
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([TypingTracker.instance, TypingTracker.sprint, Hive.box('typingSessions').listenable()]),
    builder: (context, _) {
      final sessions = TypingStore.forDate(widget.dateKey);
      // 진행 중인 세션(연습장, 스프린트)
      final lives = <TypingTracker>[
        for (final t in [TypingTracker.instance, TypingTracker.sprint])
          if (t.active && _dateKeyFromMs(t.startMs) == widget.dateKey) t,
      ];
      final total = sessions.fold<int>(0, (a, s) => a + s.activeMs) + lives.fold<int>(0, (a, t) => a + t.activeMs);
      final count = sessions.length + lives.length;
      final isToday = widget.dateKey == widget.todayKey;
      const textColor = Color(0xFF3E566B);
      return Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Container(width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(color: kPurpleLight, borderRadius: BorderRadius.circular(16)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Icon(Icons.keyboard_rounded, color: kPurple, size: 26),
              const SizedBox(width: 10),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(isToday ? '순공시간 (오늘)' : '순공시간 (${widget.dateKey})',
                    style: const TextStyle(fontSize: 11, color: textColor)),
                Text(formatTypingClock(total),
                    style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w900, color: textColor, letterSpacing: 1)),
              ])),
              if (count > 0)
                GestureDetector(
                  onTap: () => setState(() => _open = !_open),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('기록 $count개', style: const TextStyle(fontSize: 12, color: textColor, fontWeight: FontWeight.w600)),
                    Icon(_open ? Icons.expand_less_rounded : Icons.expand_more_rounded, size: 18, color: textColor),
                  ])),
            ]),
            if (_open && count > 0) ...[
              const SizedBox(height: 8),
              for (final tr in lives)
                Padding(padding: const EdgeInsets.only(bottom: 6),
                  child: Text('진행 중  ${_hm(tr.startMs)} ~  ·  ${formatTypingLong(tr.activeMs)}  ·  ${tr.chars}자  (${typingSourceLabel(tr.source)})  (종료하면 저장돼요)',
                      style: const TextStyle(fontSize: 12, color: kBlueDark, fontWeight: FontWeight.w600))),
              ...sessions.reversed.map((s) => Padding(padding: const EdgeInsets.only(bottom: 6),
                child: Row(children: [
                  Expanded(child: SelectionArea(child: Text('${_hm(s.startMs)} ~ ${_hm(s.endMs)}  ·  ${formatTypingLong(s.activeMs)}  ·  ${s.chars}자  (${typingSourceLabel(s.source)})',
                      style: const TextStyle(fontSize: 12, color: textColor)))),
                  GestureDetector(onTap: () => _confirmDelete(context, s),
                    child: const Padding(padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.delete_outline_rounded, size: 16, color: Colors.grey))),
                ]))),
            ],
          ])));
    });
}

// ── 연습장 (여기서 타이핑한 시간만 순공시간으로 기록) ───────────────────────────
// 공부방 탭과 약어확인 화면(좌우 분할)에서 같은 글·같은 순공시간을 공유한다.
// 약어 분석 글과 같은 글자 크기/줄 간격을 쓴다.
const double kReadFontSize = 16;
const double kReadLineHeight = 1.8;

TextEditingController? _practicePadCtrl;
TextEditingController get practicePadCtrl => _practicePadCtrl ??=
    TextEditingController(text: (Hive.box('settings').get('practice_pad') as String?) ?? '');

// 연습장 상태 표시 (연습장 글씨 · 타이핑 중/대기 · 오늘 순공 · 입력 계수)
// 약어 확인 화면에서는 연습장 위쪽 줄(연습장 끄기 버튼 왼쪽)에, 공부방에서는 연습장 안쪽 위에 쓴다.
class _PadStatusInfo {
  final bool active, typingNow;
  final String status, summary;
  const _PadStatusInfo(this.active, this.typingNow, this.status, this.summary);
  factory _PadStatusInfo.now() {
    final tr = TypingTracker.instance;
    final typingNow = tr.isTypingNow;
    final status = !tr.active ? '세션 없음' : typingNow ? '● 타이핑 중' : '⏸ 대기 중';
    // 홈의 '순공시간 (오늘)'과 같은 값: 저장된 오늘 기록 + 진행 중인 세션
    final todayKey = _dateKeyFromMs(DateTime.now().millisecondsSinceEpoch);
    final liveToday = tr.active && _dateKeyFromMs(tr.startMs) == todayKey;
    final sp = TypingTracker.sprint;
    final spLiveToday = sp.active && _dateKeyFromMs(sp.startMs) == todayKey;
    final todayTotal = TypingStore.forDate(todayKey).fold<int>(0, (a, s) => a + s.activeMs)
        + (liveToday ? tr.activeMs : 0) + (spLiveToday ? sp.activeMs : 0);
    final summary = tr.active
        ? '오늘 순공 ${formatTypingClock(todayTotal)}  ·  이번 ${formatTypingClock(tr.activeMs)}  ·  입력 ${tr.chars}자'
        : '오늘 순공 ${formatTypingClock(todayTotal)}';
    return _PadStatusInfo(tr.active, typingNow, status, summary);
  }
}

Widget _padStatusChip(_PadStatusInfo i) => Container(
  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
  decoration: BoxDecoration(color: i.typingNow ? kBlue.withOpacity(0.12) : const Color(0xFFF0F0F5),
      borderRadius: BorderRadius.circular(10)),
  child: Text(i.status, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700,
      color: i.typingNow ? kBlue : Colors.grey)));

// 약어 확인 화면용: 한 줄(좁으면 줄바꿈)로 이어서 보여주는 연습장 상태
class _PadStatusWrap extends StatelessWidget {
  const _PadStatusWrap();
  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: Listenable.merge([TypingTracker.instance, Hive.box('typingSessions').listenable()]),
    builder: (context, _) {
      final i = _PadStatusInfo.now();
      return Wrap(spacing: 8, runSpacing: 4, crossAxisAlignment: WrapCrossAlignment.center, children: [
        const Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(Icons.edit_note_rounded, color: kBlue, size: 18),
          SizedBox(width: 4),
          Text('연습장', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w800)),
        ]),
        _padStatusChip(i),
        Text(i.summary, style: const TextStyle(fontSize: 12, color: kBlueDark, fontWeight: FontWeight.w600)),
      ]);
    });
}

class _PracticePad extends StatefulWidget {
  final EdgeInsets margin;
  // true면 연습장 글씨·상태·입력 계수를 연습장 안쪽 위에 보여줌 (공부방).
  // false면 약어 확인 화면처럼 바깥 윗줄에서 보여주므로 여기서는 생략.
  final bool showHeader;
  // true면 약어 확인 결과 글상자와 같은 모양(배경·테두리·안쪽 여백·글자 시작 위치)으로 그림.
  final bool matchResultBox;
  const _PracticePad({this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.showHeader = true, this.matchResultBox = false});
  @override State<_PracticePad> createState() => _PracticePadState();
}
class _PracticePadState extends State<_PracticePad> {
  TextEditingController get _ctrl => practicePadCtrl;
  @override
  void initState() {
    super.initState();
    TypingTracker.instance.syncLength(_ctrl.text.length);
  }

  Future<void> _finish() async {
    final sess = await TypingTracker.instance.finish();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(sess == null ? '저장할 순공시간이 없어요' : '순공시간 ${formatTypingLong(sess.activeMs)} 저장됨'),
      backgroundColor: kBlue, duration: const Duration(seconds: 2)));
  }

  Widget _bottomButtons() => Row(children: [
    TextButton(
      onPressed: () {
        setState(() => _ctrl.clear());
        TypingTracker.instance.syncLength(0);
        Hive.box('settings').put('practice_pad', '');
      },
      child: const Text('지우기', style: TextStyle(color: Colors.grey, fontSize: 12))),
    const Spacer(),
    AnimatedBuilder(animation: TypingTracker.instance, builder: (context, _) => ElevatedButton.icon(
      onPressed: TypingTracker.instance.active ? _finish : null,
      icon: const Icon(Icons.stop_rounded, size: 16),
      label: const Text('종료·저장', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
      style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10))))),
  ]);

  void _onChanged(String v) {
    TypingTracker.instance.onTextChanged(v);
    Hive.box('settings').put('practice_pad', v);
  }

  @override
  Widget build(BuildContext context) {
    // 바깥 화면의 탭(입력창으로 포커스 이동)이 연습장 입력을 방해하지 않게 막음
    if (widget.matchResultBox) {
      // 약어 확인 결과 글상자와 같은 모양 · 같은 글자 시작 위치
      return GestureDetector(
        behavior: HitTestBehavior.opaque, onTap: () {},
        child: Padding(padding: widget.margin,
          child: Column(children: [
            Expanded(child: Container(width: double.infinity, padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(color: const Color(0xFFF8F9FF),
                  borderRadius: BorderRadius.circular(12), border: Border.all(color: kBlueLight)),
              child: TextField(controller: _ctrl, expands: true, minLines: null, maxLines: null,
                textAlignVertical: TextAlignVertical.top,
                style: const TextStyle(fontSize: kReadFontSize, height: kReadLineHeight, color: Colors.black87),
                onChanged: _onChanged,
                decoration: const InputDecoration(
                  hintText: '여기에 타이핑하면 순공시간이 기록돼요...',
                  border: InputBorder.none, enabledBorder: InputBorder.none, focusedBorder: InputBorder.none,
                  // 오른쪽 여백: 스크롤바가 글자에 붙지 않게
                  isCollapsed: true, contentPadding: EdgeInsets.only(right: 14))))),
            const SizedBox(height: 6),
            _bottomButtons(),
          ])));
    }
    return GestureDetector(
      behavior: HitTestBehavior.opaque, onTap: () {},
      child: Padding(padding: widget.margin,
        child: Container(width: double.infinity, padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFEEF0F8))),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (widget.showHeader) ...[
              AnimatedBuilder(
                animation: Listenable.merge([TypingTracker.instance, Hive.box('typingSessions').listenable()]),
                builder: (context, _) {
                  final i = _PadStatusInfo.now();
                  return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      const Icon(Icons.edit_note_rounded, color: kBlue, size: 20),
                      const SizedBox(width: 6),
                      const Text('연습장', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      _padStatusChip(i),
                    ]),
                    Padding(padding: const EdgeInsets.only(top: 6),
                      child: Text(i.summary,
                        style: const TextStyle(fontSize: 12, color: kBlueDark, fontWeight: FontWeight.w600))),
                  ]);
                }),
              const SizedBox(height: 8),
            ],
            Expanded(child: TextField(controller: _ctrl, expands: true, minLines: null, maxLines: null,
              textAlignVertical: TextAlignVertical.top,
              style: const TextStyle(fontSize: kReadFontSize, height: kReadLineHeight, color: Colors.black87),
              onChanged: _onChanged,
              decoration: InputDecoration(hintText: '여기에 타이핑하면 순공시간이 기록돼요...',
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: kBlue)),
                contentPadding: const EdgeInsets.all(12)))),
            const SizedBox(height: 6),
            _bottomButtons(),
          ]))));
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
      SelectionArea(child: Text(record.date, style: const TextStyle(fontSize: 12, color: Colors.grey))),
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
    SelectionArea(child: Text(value, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: kBlueDark))),
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
  // 순공시간(분): 1주 = 요일별 합계, 1달 = 6일 단위 합계, 1년 = 월별 합계
  List<_BD> _typingData() {
    final sessions = TypingStore.all(); final now = DateTime.now();
    double minutesWhere(bool Function(TypingSession) test) =>
        sessions.where(test).fold<int>(0, (a, s) => a + s.activeMs) / 60000.0;
    String key(DateTime d) => _ymd(d);
    if (_period == 'week') {
      final mon = now.subtract(Duration(days: now.weekday - 1)); const days = ['월','화','수','목','금','토','일'];
      return List.generate(7, (i) {
        final k = key(mon.add(Duration(days: i)));
        final v = minutesWhere((s) => s.date == k);
        return _BD(label: days[i], value: v > 0 ? v : null);
      });
    } else if (_period == 'month') {
      return [[1,6],[7,12],[13,18],[19,24],[25,31]].map((r) {
        final v = minutesWhere((s) {
          final p = s.date.split('-');
          final d = int.parse(p[2]);
          return int.parse(p[0]) == now.year && int.parse(p[1]) == now.month && d >= r[0] && d <= r[1];
        });
        return _BD(label: '${r[0]}~${r[1]}일', value: v > 0 ? v : null);
      }).toList();
    }
    return List.generate(12, (i) {
      final v = minutesWhere((s) {
        final p = s.date.split('-');
        return int.parse(p[0]) == now.year && int.parse(p[1]) == i + 1;
      });
      return _BD(label: '${i + 1}월', value: v > 0 ? v : null);
    });
  }
  List<_BD> _getData() {
    if (_filter == 'typing') return _typingData();
    final recs = Store.getRecordsWithData(); final now = DateTime.now();
    double? val(StudyRecordModel r) { switch (_filter) {
      case 'wpm': return r.wpm?.toDouble(); case 'speech': return r.speechChars?.toDouble();
      case 'essay': return r.essayChars?.toDouble();
      case 'time': final t=(r.studyHours??0)*60+(r.studyMinutes??0); return t>0?t.toDouble():null;
      default: return null; } }
    if (_period == 'week') {
      final mon=now.subtract(Duration(days:now.weekday-1)); final days=['월','화','수','목','금','토','일'];
      return List.generate(7,(i){ final d=mon.add(Duration(days:i));
        final k=_ymd(d);
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
            _PB(label:'시간',value:'time',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),const SizedBox(width:6),
            _PB(label:'순공',value:'typing',sel:_filter,onTap:(v)=>setState(()=>_filter=v)),
          ]),
          const SizedBox(height:8),
          Row(children: [
            _PB(label:'1주',value:'week',sel:_period,onTap:(v)=>setState(()=>_period=v)),const SizedBox(width:6),
            _PB(label:'1달',value:'month',sel:_period,onTap:(v)=>setState(()=>_period=v)),const SizedBox(width:6),
            _PB(label:'1년',value:'year',sel:_period,onTap:(v)=>setState(()=>_period=v)),
          ]),
        ]),
        if (_filter == 'typing') Padding(padding: const EdgeInsets.only(top: 12),
          child: Align(alignment: Alignment.centerLeft,
            child: Text('이 기간 총 순공시간  ${formatTypingTotal((data.fold<double>(0, (a, d) => a + (d.value ?? 0)) * 60000).round())}   (막대 단위: 분)',
                style: const TextStyle(fontSize: 12, color: kBlueDark, fontWeight: FontWeight.w700)))),
        const SizedBox(height:24),
        Expanded(child:data.every((d)=>d.value==null)?const Center(child:Text('기록이 없습니다',style:TextStyle(color:Colors.grey))):Row(crossAxisAlignment:CrossAxisAlignment.end,children:data.map((d){
          final ratio=d.value!=null?d.value!/chartMax:0.0;
          return Expanded(child:Padding(padding:const EdgeInsets.symmetric(horizontal:3),child:Column(mainAxisAlignment:MainAxisAlignment.end,children:[
            if(d.value!=null)Text(_filter=='typing'?d.value!.toStringAsFixed(1):d.value!.round().toString(),style:const TextStyle(fontSize:10,color:kBlue,fontWeight:FontWeight.w700)),
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
  final _foundSearchCtrl = TextEditingController();
  String _foundQuery = '';
  bool _foundExpanded = false;

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
        .map((a) => a.quizText).join(', ');
    Clipboard.setData(ClipboardData(text: text));
    setState(() { _gridSelected.clear(); _gridSelectMode = false; });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _foundSearchCtrl.dispose();
    _tooltipOverlay?.remove();
    TtsController.instance.stop();
    super.dispose();
  }

  void _showAbbrTooltip(BuildContext context, AbbreviationModel abbr, Offset position) {
    _tooltipOverlay?.remove(); _tooltipOverlay = null;
    final screenW = MediaQuery.of(context).size.width;
    final overlay = Overlay.of(context);
    final abbrGroups = abbr.groupIds.map((id) => Store.findGroup(id)).whereType<GroupModel>().toList();
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
              if (abbr.isAttached) const Padding(padding: EdgeInsets.only(right: 3),
                child: Icon(Icons.south_west_rounded, size: 13, color: kBlueDark)),
              Text(abbr.quizText, style: TextStyle(color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 13)),
              ...abbr.typeLabels.map((l) {
                final c = l == '동시' ? kPurple : l == '합성' ? kBlueSky : kBlueDark;
                return Container(margin: const EdgeInsets.only(left: 3),
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(4)),
                  child: Text(l, style: TextStyle(fontSize: 9, color: c, fontWeight: FontWeight.w700)));
              }),
              ...abbrGroups.map((group) => Container(margin: const EdgeInsets.only(left: 3),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                decoration: BoxDecoration(color: group.color.withOpacity(0.15), borderRadius: BorderRadius.circular(4)),
                child: Text(group.name, style: TextStyle(fontSize: 9, color: group.color, fontWeight: FontWeight.w700)))),
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

  // 연습장 켜기/끄기 버튼 (분류 안내 줄 오른쪽)
  Widget _padToggleButton() => GestureDetector(
    onTap: () => setState(() => _analyzerPadOn = !_analyzerPadOn),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: _analyzerPadOn ? kBlue : kBlueLight, borderRadius: BorderRadius.circular(20)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(Icons.edit_note_rounded, size: 14, color: _analyzerPadOn ? Colors.white : kBlue),
        const SizedBox(width: 4),
        Text(_analyzerPadOn ? '연습장 끄기' : '연습장 켜기',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700,
                color: _analyzerPadOn ? Colors.white : kBlue)),
      ])));

  void _confirmClear(BuildContext context) {
    showDialog(context: context, builder: (ctx) {
      void doClear() {
        _analyzerCtrl.clear(); _analyzerAnalyzed = false;
        TtsController.instance.stop();
        Navigator.pop(ctx); setState(() {});
      }
      return _EnterToConfirm(onConfirm: doClear, child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('모두 지우기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: const Text('입력한 문장을 모두 지울까요?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: Colors.red, foregroundColor: Colors.white),
            onPressed: doClear,
            child: const Text('지우기')),
        ]));
    });
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
        final fq = _foundQuery.trim().toLowerCase();
        final shown = fq.isEmpty ? found : found.where((a) {
          final hay = [a.quizText, a.strokeDisplay,
            ...a.groupIds.map((id) => Store.findGroup(id)?.name ?? '')].join(' ').toLowerCase();
          return hay.contains(fq);
        }).toList();
        const int kFoundCollapsed = 6; // 3칸 x 2줄
        final visibleCount = (_foundExpanded || shown.length <= kFoundCollapsed) ? shown.length : kFoundCollapsed;

        final bool showResult = _analyzerAnalyzed && text.isNotEmpty;
        final bool splitOn = _analyzerPadOn && showResult; // 연습장 켜짐: 좌우 분할

        // 위쪽(입력/분석 버튼/분류 안내), 아래쪽(분석 글·TTS·사용된 약어)을 나눠 담아 두고,
        // 분할 모드에서는 아래쪽만 왼쪽 칸에서 따로 스크롤되게 배치한다.
        final headWidgets = <Widget>[
                  Focus(onKeyEvent: (node, event) {
                    if (event is KeyDownEvent &&
                        (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
                        HardwareKeyboard.instance.isControlPressed) {
                      setState(() => _analyzerAnalyzed = true);
                      return KeyEventResult.handled;
                    }
                    return KeyEventResult.ignored;
                  },
                  child: TextField(controller: _analyzerCtrl, focusNode: _focusNode,
                    minLines: _analyzerAnalyzed ? 3 : 10, maxLines: _analyzerAnalyzed ? 3 : 10,
                    onChanged: (_) => setState(() {
                      _analyzerAnalyzed = false;
                      _foundQuery = ''; _foundSearchCtrl.clear(); _foundExpanded = false;
                    }),
                    decoration: InputDecoration(hintText: '분석할 문장을 입력하세요... (Ctrl+Enter로 분석)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBlue))))),
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
        ];
        final legendWrap = Wrap(spacing: 12, runSpacing: 6, children: [
          _Leg(color: kBlue, label: '일반 약어'),
          _Leg(color: kBlueSky, label: '합성약어'),
          _Leg(color: kPurple, label: '동시처리약어'),
          const Text('⭐ 즐겨찾기', style: TextStyle(fontSize: 11, color: Colors.grey)),
        ]);
        // 분류 안내 줄: 연습장이 꺼져 있으면 [안내 ... 연습장 켜기]
        final legendWidgets = showResult ? <Widget>[
                    const SizedBox(height: 16),
                    Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                      Expanded(child: legendWrap),
                      const SizedBox(width: 8),
                      _padToggleButton(),
                    ]),
                    const SizedBox(height: 8),
        ] : <Widget>[];
        // 연습장이 켜져 있으면 좌우 칸에 맞춰 나눠서
        // 왼쪽: 분류 안내 / 오른쪽: [연습장 글씨 · 상태 · 입력 계수 ... 연습장 끄기]
        // (오른쪽 줄이 연습장 입력 공간 바로 위에 오도록)
        final splitLegendRow = Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(16, 14, 8, 8), child: legendWrap)),
          const SizedBox(width: 1),
          Expanded(child: Padding(padding: const EdgeInsets.fromLTRB(8, 14, 16, 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              const Expanded(child: _PadStatusWrap()),
              const SizedBox(width: 8),
              _padToggleButton(),
            ]))),
        ]);
        final bodyWidgets = showResult ? <Widget>[
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
                      SizedBox(height: 38, child: TextField(
                        controller: _foundSearchCtrl,
                        onChanged: (v) => setState(() => _foundQuery = v),
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          isDense: true,
                          hintText: '사용된 약어 검색 (약어·운지·그룹)',
                          hintStyle: const TextStyle(fontSize: 12, color: Colors.grey),
                          prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
                          prefixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                          suffixIcon: _foundQuery.isEmpty ? null : GestureDetector(
                            onTap: () => setState(() { _foundQuery = ''; _foundSearchCtrl.clear(); }),
                            child: const Icon(Icons.close, size: 16, color: Colors.grey)),
                          suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                          contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                              borderSide: const BorderSide(color: kBlue))))),
                      const SizedBox(height: 10),
                      Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                        Text(fq.isEmpty ? '사용된 약어 (${found.length}개)' : '사용된 약어 (${shown.length}/${found.length}개)',
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
                                final t = shown.map((a) => '${a.displayWord}: ${a.strokeDisplay}').join('\n');
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
                                final allSel = shown.isNotEmpty && shown.every((a) => _gridSelected.contains(a.id));
                                if (allSel) _gridSelected.removeAll(shown.map((a) => a.id));
                                else _gridSelected.addAll(shown.map((a) => a.id));
                              }),
                              child: Text((shown.isNotEmpty && shown.every((a) => _gridSelected.contains(a.id))) ? '전체 해제' : '전체 선택',
                                  style: const TextStyle(fontSize: 12, color: Colors.grey))),
                          ])),
                      if (shown.isEmpty)
                        const Padding(padding: EdgeInsets.symmetric(vertical: 12),
                          child: Center(child: Text('검색 결과가 없습니다',
                              style: TextStyle(fontSize: 12, color: Colors.grey)))),
                      GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3, crossAxisSpacing: 6, mainAxisSpacing: 6, mainAxisExtent: 40),
                        itemCount: visibleCount,
                        itemBuilder: (ctx, i) {
                          final a = shown[i];
                          final isSelected = _gridSelected.contains(a.id);
                          final aGroups = a.groupIds.map((id) => Store.findGroup(id)).whereType<GroupModel>().toList();
                          return GestureDetector(
                            onTap: _gridSelectMode ? () => _toggleGridSelect(a.id) : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected ? kBlueLight : Colors.white,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: isSelected ? kBlue : const Color(0xFFEEF0F8),
                                    width: isSelected ? 1.5 : 1)),
                              child: LayoutBuilder(builder: (ctx2, cons) => Column(
                                crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.center, children: [
                                Row(children: [
                                  if (_gridSelectMode) ...[
                                    Icon(isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                                        size: 12, color: isSelected ? kBlue : Colors.grey),
                                    const SizedBox(width: 3),
                                  ],
                                  if (a.isAttached) const Padding(padding: EdgeInsets.only(right: 2),
                                    child: Icon(Icons.south_west_rounded, size: 11, color: kBlueDark)),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(maxWidth: cons.maxWidth * 0.6),
                                    child: Text(a.quizText,
                                        style: TextStyle(color: a.typeColor, fontWeight: FontWeight.w700, fontSize: 12),
                                        overflow: TextOverflow.ellipsis, maxLines: 1)),
                                  const SizedBox(width: 4),
                                  Expanded(child: ClipRect(child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal, physics: const NeverScrollableScrollPhysics(),
                                    child: Row(children: [
                                      ...a.typeLabels.map((l) {
                                        final c = l == '동시' ? kPurple : l == '합성' ? kBlueSky : kBlueDark;
                                        return Container(margin: const EdgeInsets.only(right: 2),
                                          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                          decoration: BoxDecoration(color: c.withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
                                          child: Text(l, style: TextStyle(fontSize: 8, color: c, fontWeight: FontWeight.w700)));
                                      }),
                                      ...aGroups.map((group) => Container(margin: const EdgeInsets.only(right: 2),
                                        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                                        decoration: BoxDecoration(color: group.color.withOpacity(0.1), borderRadius: BorderRadius.circular(3)),
                                        child: Text(group.name, style: TextStyle(fontSize: 8, color: group.color, fontWeight: FontWeight.w700)))),
                                    ])))),
                                ]),
                                if (a.strokeDisplay.isNotEmpty)
                                  Text(a.strokeDisplay, style: const TextStyle(fontSize: 9, color: Colors.grey),
                                      overflow: TextOverflow.ellipsis, maxLines: 1),
                              ]))));
                        }),
                      if (shown.length > kFoundCollapsed)
                        GestureDetector(
                          onTap: () => setState(() => _foundExpanded = !_foundExpanded),
                          child: Container(
                            width: double.infinity,
                            margin: const EdgeInsets.only(top: 8),
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            decoration: BoxDecoration(color: const Color(0xFFF8F9FF),
                                borderRadius: BorderRadius.circular(8), border: Border.all(color: const Color(0xFFEEF0F8))),
                            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Text(_foundExpanded ? '접기' : '더보기 (+${shown.length - kFoundCollapsed}개)',
                                  style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.w600)),
                              Icon(_foundExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                                  size: 16, color: kBlue),
                            ]))),
                      const SizedBox(height: 16),
                    ],
        ] : <Widget>[];

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
              Expanded(child: splitOn
                ? Column(children: [
                    Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        ...headWidgets,
                      ])),
                    splitLegendRow,
                    Expanded(child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      // 왼쪽: 약어 확인 중인 글 (자체 스크롤)
                      Expanded(child: SingleChildScrollView(
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                        padding: const EdgeInsets.fromLTRB(16, 0, 22, 0), // 오른쪽 여백: 스크롤바가 글자에 붙지 않게
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: bodyWidgets))),
                      Container(width: 1, color: const Color(0xFFEEF0F8)),
                      // 오른쪽: 연습장 (왼쪽과 따로 스크롤 · 결과 글상자와 같은 크기/글자 시작 위치)
                      const Expanded(child: _PracticePad(
                        margin: EdgeInsets.fromLTRB(8, 0, 16, 12),
                        showHeader: false, matchResultBox: true)),
                    ])),
                  ])
                : SingleChildScrollView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      ...headWidgets,
                      if (showResult) ...legendWidgets,
                      if (showResult) ...bodyWidgets,
                    ]))),
            ]))));
      });
  }
}

// ── TTS 하이라이트 분석 텍스트 뷰 (더블클릭하면 그 위치부터 재생) ──────────
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
            onDoubleTap: () => TtsController.instance.seekAndPlay(spanStart),
            child: Container(
              decoration: BoxDecoration(
                color: isHighlighted ? kBlue.withOpacity(0.18)
                    : isSelected ? color.withOpacity(0.12) : null,
                borderRadius: BorderRadius.circular(3)),
              child: Text(displayText,
                  style: TextStyle(fontSize: kReadFontSize, color: color, fontWeight: fw, height: kReadLineHeight,
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
                style: TextStyle(fontSize: kReadFontSize, color: color, fontWeight: fw, height: kReadLineHeight)));
          } else {
            children.add(WidgetSpan(
              alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onDoubleTap: () => TtsController.instance.seekAndPlay(pieceStart),
                child: Container(
                  decoration: BoxDecoration(
                    color: pieceHighlighted ? kBlue.withOpacity(0.18) : null,
                    borderRadius: BorderRadius.circular(3)),
                  child: Text(piece,
                      style: TextStyle(fontSize: kReadFontSize, color: color, fontWeight: fw, height: kReadLineHeight)),
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
class _SearchScreenState extends State<SearchScreen> with _SelectionMixin<SearchScreen> {
  final _ctrl = TextEditingController();
  String? _filterGroupId;
  String _sortMode = Hive.box('settings').get('abbr_sort_mode', defaultValue: 'saved') as String;

  void _setSortMode(String mode) {
    setState(() => _sortMode = mode);
    Hive.box('settings').put('abbr_sort_mode', mode);
  }

  Future<void> _bulkFav(List<AbbreviationModel> all) async {
    for (final a in all.where((a) => _selected.contains(a.id)))
      await Store.saveAbbreviation(a.copyWith(isFavorite: true));
    _exitSelectMode();
  }

  Future<void> _bulkDelete(BuildContext context, List<AbbreviationModel> all) async {
    if (!await _confirmBulkDelete(context)) return;
    for (final a in all.where((a) => _selected.contains(a.id)))
      await Store.deleteAbbreviation(a.id);
    _exitSelectMode();
  }

  void _bulkRemind(BuildContext context, List<AbbreviationModel> all) {
    final targets = all.where((a) => _selected.contains(a.id)).map((a) => a.word).toList();
    _showBulkReminderDialog(context, targets, 'word');
    _exitSelectMode();
  }

  void _bulkSetGroup(BuildContext context, List<AbbreviationModel> all) async {
    final groups = Store.getGroups();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 그룹을 만들어 주세요'), backgroundColor: kBlue, duration: Duration(seconds: 2)));
      return;
    }
    final selected = all.where((a) => _selected.contains(a.id)).toList();

    // 각 그룹의 초기 상태 계산: all=☑, some=➖, none=☐
    // 0 = none, 1 = some, 2 = all
    Map<String, int> groupState = {};
    for (final g in groups) {
      final count = selected.where((a) => a.groupIds.contains(g.id)).length;
      groupState[g.id] = count == 0 ? 0 : (count == selected.length ? 2 : 1);
    }
    // 편집 중인 상태 (null=변경없음, true=추가, false=해제)
    Map<String, bool?> changes = {};
    bool asking = false; // 변경사항 확인 창이 두 번 뜨는 것 방지

    final apply = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) {
        void doSave() async {
          if (asking) return;
          final hasChange = changes.values.any((v) => v != null);
          if (!hasChange) { Navigator.pop(ctx, false); return; }
          asking = true;
          final ok = await showDialog<bool>(context: ctx, builder: (c2) => _EnterToConfirm(
            onConfirm: () => Navigator.pop(c2, true),
            child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('변경사항 저장', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: const Text('그룹 설정을 변경할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c2, true), child: const Text('저장')),
            ])));
          asking = false;
          if (ctx.mounted) Navigator.pop(ctx, ok == true);
        }
        return _EnterToConfirm(
          onConfirm: doSave,
          child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: Text('그룹 추가/해제 (${selected.length}개 약어)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
              ...groups.map((g) {
                final cur = changes[g.id];
                // 현재 표시 상태 결정
                int displayState;
                if (cur == true) displayState = 2;
                else if (cur == false) displayState = 0;
                else displayState = groupState[g.id]!;

                return ListTile(
                  leading: CircleAvatar(backgroundColor: g.color, radius: 12,
                    child: Text(g.name[0], style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w700))),
                  title: Text(g.name),
                  trailing: GestureDetector(
                    onTap: () => setS(() {
                      if (displayState == 2) changes[g.id] = false;      // ☑ → ☐
                      else if (displayState == 1) changes[g.id] = true;  // ➖ → ☑
                      else changes[g.id] = true;                          // ☐ → ☑
                    }),
                    child: Container(width: 28, height: 28,
                      decoration: BoxDecoration(
                        color: displayState == 2 ? g.color : displayState == 1 ? g.color.withOpacity(0.3) : Colors.transparent,
                        border: Border.all(color: displayState == 0 ? Colors.grey.shade400 : g.color, width: 2),
                        borderRadius: BorderRadius.circular(6)),
                      child: Center(child: displayState == 2
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : displayState == 1
                          ? Icon(Icons.remove, color: g.color, size: 16)
                          : null))));
              }),
            ])),
            actions: [
              TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: doSave, child: const Text('저장')),
            ]));
      }));
    if (apply != true) return;
    for (final a in selected) {
      var newIds = List<String>.from(a.groupIds);
      for (final entry in changes.entries) {
        if (entry.value == true && !newIds.contains(entry.key)) newIds.add(entry.key);
        if (entry.value == false) newIds.remove(entry.key);
      }
      await Store.saveAbbreviation(a.copyWith(groupIds: newIds));
    }
    _exitSelectMode();
  }

  void _bulkEditType(BuildContext context, List<AbbreviationModel> all) {
    bool isComposite = false, isConcurrent = false, isAttached = false;
    bool applying = false;
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> doApply() async {
        if (applying) return;
        applying = true;
        for (final a in all.where((a) => _selected.contains(a.id)))
          await Store.saveAbbreviation(a.copyWith(
            isComposite: isComposite, isConcurrent: isConcurrent, isAttached: isAttached));
        if (ctx.mounted) Navigator.pop(ctx);
        _exitSelectMode();
      }
      return _EnterToConfirm(onConfirm: doApply, child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text('분류 변경 (${_selected.length}개)', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: _TypeToggleRow(
        isComposite: isComposite, isConcurrent: isConcurrent,
        isAttached: isAttached,
        onCompositeChanged: (v) => setS(() => isComposite = v),
        onConcurrentChanged: (v) => setS(() => isConcurrent = v),
        onAttachedChanged: (v) => setS(() => isAttached = v)),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: doApply, child: const Text('적용')),
      ]));
    }));
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
            var results = q.isEmpty ? sortAbbreviations(all, _sortMode, groups) : sortedSearchResults(all, q);
            if (_filterGroupId != null) results = results.where((a) => a.groupIds.contains(_filterGroupId)).toList();

            return Scaffold(backgroundColor: Colors.white,
              body: SafeArea(child: Column(children: [
                Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    const Text('약어 검색', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    if (!_selectMode)
                      Row(children: [
                        GestureDetector(onTap: _toggleSelectMode,
                          child: Padding(padding: const EdgeInsets.only(right: 8), child: _iconToolBtn(Icons.checklist_rounded))),
                        GestureDetector(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const GroupManageScreen())),
                          child: Padding(padding: const EdgeInsets.only(right: 8), child: _iconToolBtn(Icons.folder_rounded))),
                        GestureDetector(onTap: () => _showCsvDialog(context),
                          child: Padding(padding: const EdgeInsets.only(right: 8), child: _iconToolBtn(Icons.import_export_rounded))),
                        ElevatedButton.icon(onPressed: () => _showAbbrEditDialog(context),
                          icon: const Icon(Icons.add, size: 16), label: const Text('추가'),
                          style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6))),
                      ]),
                  ]),
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  if (_selectMode) ...[
                    GestureDetector(onTap: () => _bulkFav(results),
                      child: _actionChip(Icons.star_rounded, '즐겨찾기', const Color(0xFFFFAA00))),
                    GestureDetector(onTap: () => _bulkRemind(context, results),
                      child: _actionChip(Icons.notifications_rounded, '리마인드', kBlue)),
                    GestureDetector(onTap: () => _bulkSetGroup(context, results),
                      child: _actionChip(Icons.label_rounded, '그룹', kBlueSky)),
                    GestureDetector(onTap: () => _bulkEditType(context, results),
                      child: _actionChip(Icons.edit_rounded, '분류', kPurple)),
                    GestureDetector(onTap: () => _openSelectedView(context, results),
                      child: _actionChip(Icons.visibility_rounded, '모아보기', kBlueDark)),
                    GestureDetector(onTap: () => _bulkDelete(context, results),
                      child: _actionChip(Icons.delete_rounded, '삭제', Colors.red)),
                    GestureDetector(onTap: _toggleSelectMode,
                      child: _actionChip(Icons.close, '취소', Colors.grey)),
                  ] else ...[
                    if (groups.isNotEmpty)
                      GestureDetector(onTap: () => _showGroupFilter(context, groups),
                        child: _toolChip(Icons.label_rounded,
                          _filterGroupId != null ? (Store.findGroup(_filterGroupId!)?.name ?? '그룹') : '그룹',
                          active: _filterGroupId != null,
                          color: _filterGroupId != null ? (Store.findGroup(_filterGroupId!)?.color ?? kBlue) : kBlue)),
                    PopupMenuButton<String>(
                      tooltip: '정렬',
                      onSelected: _setSortMode,
                      itemBuilder: (_) => kSortModeLabels.entries
                          .map((e) => PopupMenuItem(value: e.key, child: Text(e.value)))
                          .toList(),
                      child: _toolChip(Icons.sort_rounded, kSortModeLabels[_sortMode] ?? '정렬',
                          active: _sortMode != 'saved')),
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
                          if (_selected.length == results.length) _selected.clear();
                          else _selected.addAll(results.map((a) => a.id));
                        }),
                        child: Text(_selected.length == results.length ? '전체 해제' : '전체 선택',
                            style: const TextStyle(fontSize: 12, color: Colors.grey))),
                    ])),
                Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: TextField(
                  controller: _ctrl, onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(hintText: '약어로 검색하세요...',
                    prefixIcon: const Icon(Icons.search, color: Colors.grey),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBlue))))),
                const SizedBox(height: 8),
                Expanded(child: results.isEmpty
                  ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      Text(_filterGroupId == kFavGroupId ? '즐겨찾기한 약어가 없습니다' : '약어가 없습니다',
                          style: const TextStyle(color: Colors.grey, fontSize: 14)),
                      if (_filterGroupId == null) ...[
                        const SizedBox(height: 12),
                        OutlinedButton(onPressed: () => _showAbbrEditDialog(context),
                          style: OutlinedButton.styleFrom(foregroundColor: kBlue, side: const BorderSide(color: kBlue),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20))),
                          child: const Text('약어 추가하기', style: TextStyle(fontWeight: FontWeight.w700))),
                      ]]))
                  : LayoutBuilder(builder: (context, cons) {
                      // 화면 너비에 따라 1줄 ~ 3줄(열)로 나눠서 보여줌 (큰 화면의 빈 공간을 줄임)
                      final int cols = cons.maxWidth < 720 ? 1 : (cons.maxWidth < 1100 ? 2 : 3);
                      final int rowCount = (results.length + cols - 1) ~/ cols;
                      Widget buildTile(AbbreviationModel a) {
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
                      }
                      return ListView.builder(
                        controller: _searchScrollCtrl,
                        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.manual,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: rowCount,
                        itemBuilder: (context, r) {
                          final start = r * cols;
                          return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            for (int c = 0; c < cols; c++) ...[
                              if (c > 0) const SizedBox(width: 8),
                              Expanded(child: start + c < results.length
                                  ? buildTile(results[start + c])
                                  : const SizedBox.shrink()),
                            ],
                          ]);
                        });
                    })),
              ])));
          });
      });
  }

  void _showCsvDialog(BuildContext context) {
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('CSV 백업/가져오기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('약어 데이터를 CSV 형식으로 내보내거나 가져올 수 있어요.',
            style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 16),
        SizedBox(width: double.infinity, child: ElevatedButton.icon(
          icon: const Icon(Icons.upload_rounded, size: 16),
          label: const Text('CSV 내보내기 (클립보드 복사)'),
          style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: () {
            final csv = Store.exportCsv();
            Clipboard.setData(ClipboardData(text: csv));
            Navigator.pop(ctx);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('CSV가 클립보드에 복사됐어요! 메모장 등에 붙여넣어 저장하세요.'),
                  backgroundColor: kBlue, duration: Duration(seconds: 3)));
          })),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, child: OutlinedButton.icon(
          icon: const Icon(Icons.download_rounded, size: 16, color: kBlue),
          label: const Text('CSV 가져오기', style: TextStyle(color: kBlue)),
          style: OutlinedButton.styleFrom(side: const BorderSide(color: kBlue),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
          onPressed: () {
            Navigator.pop(ctx);
            _showCsvImportDialog(context);
          })),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('닫기', style: TextStyle(color: Colors.grey))),
      ]));
  }

  void _showCsvImportDialog(BuildContext context) {
    final ctrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('CSV 가져오기', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('내보낸 CSV 내용을 붙여넣어 주세요.', style: TextStyle(fontSize: 13, color: Colors.grey)),
        const SizedBox(height: 12),
        TextField(controller: ctrl, maxLines: 6, decoration: _inputDeco('CSV 내용 붙여넣기...')),
      ]),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx),
            child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () async {
            final csv = ctrl.text.trim();
            if (csv.isEmpty) return;
            final items = await Store.importCsv(csv);
            if (items.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('가져올 수 있는 데이터가 없어요.'), backgroundColor: Colors.red));
              return;
            }
            Navigator.pop(ctx);
            for (final a in items) await Store.saveAbbreviation(a);
            setState(() {});
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('${items.length}개의 약어를 가져왔어요!'), backgroundColor: kBlue));
            }
          }, child: const Text('가져오기')),
      ]));
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
  final List<List<String>> rowGroupIds = [];
  final List<FocusNode> wordFocusNodes = [];
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
    });
    rowGroupIds.add(from?.groupIds != null ? List<String>.from(from!.groupIds) : <String>[]);
    wordFocusNodes.add(FocusNode());
  }
  addRow(from: existing);
  bool saving = false; // 저장 확인 창이 두 번 뜨는 것(Enter 중복)을 막음

  showDialog(context: context, barrierColor: Colors.black.withOpacity(0.3),
    builder: (dCtx) => StatefulBuilder(builder: (dCtx, setS) {
      final groups = Store.getGroups();
      List<String> pf(String s) => s.split(RegExp(r'[+\s]+')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

      Future<void> saveAllCore() async {
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
          final proceedAnyway = await showDialog<bool>(context: context, builder: (c) => _EnterToConfirm(
            onConfirm: () => Navigator.pop(c, true),
            child: AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('이미 등록된 약어', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
            content: Text('다음 약어는 이미 등록되어 있어요:\n${dupWords.join(", ")}\n\n그래도 저장할까요?'),
            actions: [
              TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
              ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                  onPressed: () => Navigator.pop(c, true), child: const Text('그래도 저장'))])));
          if (proceedAnyway != true) return;
        }

        final ok = await showDialog<bool>(context: context, builder: (c) => _EnterToConfirm(
          onConfirm: () => Navigator.pop(c, true),
          child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(existing != null ? '수정 확인' : '저장 확인',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          content: Text(existing != null ? '수정할까요?' : '${rows.length}개를 저장할까요?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
            ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                onPressed: () => Navigator.pop(c, true), child: const Text('저장'))])));
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
            groupIds: rowGroupIds[i]));
        }
      }

      Future<void> saveAll() async {
        if (saving) return;
        saving = true;
        try { await saveAllCore(); } finally { saving = false; }
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
          isAttached: rowFlags[i]['isAttached']!,
          onCompositeChanged: (v) => setS(() => rowFlags[i]['isComposite'] = v),
          onConcurrentChanged: (v) => setS(() => rowFlags[i]['isConcurrent'] = v),
          onAttachedChanged: (v) => setS(() => rowFlags[i]['isAttached'] = v)),
       if (groups.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(children: [
            Text('여러 그룹 선택 가능', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
            const Spacer(),
            if (rowGroupIds[i].isNotEmpty)
              GestureDetector(onTap: () => setS(() => rowGroupIds[i] = []),
                child: Text('전체 해제', style: TextStyle(fontSize: 10, color: Colors.grey.shade500, decoration: TextDecoration.underline))),
          ]),
          const SizedBox(height: 4),
          Wrap(spacing: 6, runSpacing: 6, children: [
            ...groups.map((g) {
              final selected = rowGroupIds[i].contains(g.id);
              return GestureDetector(onTap: () => setS(() {
                if (selected) rowGroupIds[i].remove(g.id); else rowGroupIds[i].add(g.id);
              }),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? g.color.withOpacity(0.15) : const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: selected ? g.color : Colors.transparent, width: 1.5)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (selected) ...[Icon(Icons.check, size: 12, color: g.color), const SizedBox(width: 3)],
                    CircleAvatar(backgroundColor: g.color, radius: 5),
                    const SizedBox(width: 5),
                    Text(g.name, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: selected ? g.color : Colors.grey)),
                  ])));
            }),
          ]),
        ],
      ]);

      return _EnterToConfirm(onConfirm: saveAll, child: AlertDialog(
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
                GestureDetector(onTap: () => setS(() {
                    rows.removeAt(i); rowFlags.removeAt(i); rowGroupIds.removeAt(i);
                    wordFocusNodes.removeAt(i).dispose();
                  }),
                  child: const Icon(Icons.remove_circle_outline, size: 16, color: Colors.red)),
                const SizedBox(width: 6),
                Text('${i + 1}번', style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
              ]),
              if (rows.length > 1) const SizedBox(height: 4),
              _lbl('약어'),
              Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent) {
                    final isShiftKey = event.logicalKey == LogicalKeyboardKey.shift ||
                        event.logicalKey == LogicalKeyboardKey.shiftLeft ||
                        event.logicalKey == LogicalKeyboardKey.shiftRight;
                    final isAltKey = event.logicalKey == LogicalKeyboardKey.alt ||
                        event.logicalKey == LogicalKeyboardKey.altLeft ||
                        event.logicalKey == LogicalKeyboardKey.altRight;
                    final altShiftCombo = (isShiftKey && HardwareKeyboard.instance.isAltPressed) ||
                        (isAltKey && HardwareKeyboard.instance.isShiftPressed);
                    if (altShiftCombo) {
                      if (existing == null && i == rows.length - 1) {
                        setS(() => addRow());
                      }
                      final targetIndex = i + 1;
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (targetIndex < wordFocusNodes.length) wordFocusNodes[targetIndex].requestFocus();
                      });
                      return KeyEventResult.handled;
                    }
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(controller: row['word'], focusNode: wordFocusNodes[i],
                  decoration: _inputDeco(''), textInputAction: TextInputAction.next),
              ),
              const SizedBox(height: 4),
              Text('※ 띄어쓰기 → * 자동 변환  |  약어 입력 후 Alt+Shift → 초중종성 생략하고 다음 약어로', style: TextStyle(fontSize: 10, color: Colors.grey.shade500)),
              const SizedBox(height: 8),
              // 속기 키보드 클릭 입력
              _SoggiKeyboardInput(
                isOn: (label, type) {
                  final c = type == 'cho' ? row['initial'] : type == 'jung' ? row['medial'] : row['final'];
                  return c != null && c.text.split('+').map((e) => e.trim()).contains(label);
                },
                onKeyTap: (label, type) {
                  // 타입에 따라 해당 입력창에 추가 (이미 눌린 키를 다시 누르면 제거)
                  TextEditingController? ctrl;
                  if (type == 'cho') ctrl = row['initial'];
                  else if (type == 'jung') ctrl = row['medial'];
                  else ctrl = row['final'];
                  if (ctrl == null) return;
                  final parts = ctrl.text.split('+').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
                  if (parts.contains(label)) { parts.removeWhere((e) => e == label); } else { parts.add(label); }
                  ctrl.text = parts.join('+');
                  ctrl.selection = TextSelection.collapsed(offset: ctrl.text.length);
                  setS(() {});
                }),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('초성'), TextField(controller: row['initial'], decoration: _inputDeco(''), textInputAction: TextInputAction.next,
                    onChanged: (_) => setS(() {})),
                ])),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('중성'), TextField(controller: row['medial'], decoration: _inputDeco(''), textInputAction: TextInputAction.next,
                    onChanged: (_) => setS(() {})),
                ])),
                const SizedBox(width: 6),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  _lbl('종성'),
                  TextField(controller: row['final'], decoration: _inputDeco(''),
                    onChanged: (_) => setS(() {}),
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
        ]));
    }));
}

// ── 취약점 분석 화면 ──────────────────────────────────────────────────────────
class WeakPointScreen extends StatelessWidget {
  const WeakPointScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final weakPoints = Store.analyzeWeakPoints(days: 30);
    final recommended = Store.recommendByWeakPoints(weakPoints);
    final allEmpty = weakPoints.values.every((m) => m.isEmpty);

    String buildPrompt() {
      final cho = (weakPoints['cho'] ?? {}).entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
      final jung = (weakPoints['jung'] ?? {}).entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
      final jong = (weakPoints['jong'] ?? {}).entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
      final recWords = recommended.map((a) => a.displayWord.replaceAll('*',' ')).join(', ');
      return '''속기 학습 취약점 분석 결과입니다.

[취약한 초성] ${cho.take(5).map((e)=>'${e.key}(${e.value}회)').join(', ')}
[취약한 중성] ${jung.take(5).map((e)=>'${e.key}(${e.value}회)').join(', ')}
[취약한 종성] ${jong.take(5).map((e)=>'${e.key}(${e.value}회)').join(', ')}
[취약 관련 약어] $recWords

위 취약점을 집중적으로 연습할 수 있는 속기 연습 문장 10개를 만들어주세요.
각 문장은 취약한 자음/모음이 자주 등장하도록 구성해주세요.''';
    }

    return Scaffold(backgroundColor: Colors.white,
      appBar: AppBar(backgroundColor: Colors.white, elevation: 0,
        leading: IconButton(icon: const Icon(Icons.arrow_back_ios_rounded, color: kBlue),
            onPressed: () => Navigator.pop(context)),
        title: const Text('취약점 분석', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18))),
      body: allEmpty
        ? const Center(child: Padding(padding: EdgeInsets.all(32),
            child: Text('아직 오답 데이터가 없어요.\n테스트를 더 진행하면 분석 결과가 나타납니다.',
                textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 14))))
        : SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // 초/중/종성별 취약도
            for (final entry in [
              MapEntry('초성', weakPoints['cho']!),
              MapEntry('중성', weakPoints['jung']!),
              MapEntry('종성', weakPoints['jong']!),
            ]) ...[
              if (entry.value.isNotEmpty) ...[
                Text(entry.key, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
                const SizedBox(height: 8),
                () {
                  final sorted = entry.value.entries.toList()..sort((a,b)=>b.value.compareTo(a.value));
                  final max = sorted.first.value;
                  return Column(children: sorted.take(8).map((e) => Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      SizedBox(width: 36, child: Text(e.key, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700))),
                      const SizedBox(width: 8),
                      Expanded(child: ClipRRect(borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(value: e.value / max,
                          backgroundColor: const Color(0xFFEEEEEE),
                          color: entry.key == '초성' ? const Color(0xFF4A90E2) : entry.key == '중성' ? const Color(0xFF7B5EA7) : const Color(0xFFE2574A),
                          minHeight: 16))),
                      const SizedBox(width: 8),
                      Text('${e.value}회', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                    ]))).toList());
                }(),
                const SizedBox(height: 20),
              ],
            ],
            // 취약 약어 추천
            if (recommended.isNotEmpty) ...[
              const Text('취약점 관련 추천 약어', style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: recommended.map((a) =>
                Container(padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(20)),
                  child: Text(a.displayWord.replaceAll('*',' '),
                      style: const TextStyle(fontSize: 13, color: kBlue, fontWeight: FontWeight.w600)))).toList()),
              const SizedBox(height: 24),
            ],
            // AI 프롬프트 복사
            Container(width: double.infinity, padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: const Color(0xFFF8F4FF), borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: const Color(0xFFD0B8FF))),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.auto_awesome_rounded, size: 16, color: Color(0xFF7B5EA7)),
                  SizedBox(width: 6),
                  Text('AI 연습 문장 생성', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: Color(0xFF7B5EA7))),
                ]),
                const SizedBox(height: 8),
                const Text('아래 프롬프트를 복사해서 AI에게 붙여넣으면\n취약점 맞춤 연습 문장을 만들어 줍니다.',
                    style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: buildPrompt()));
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('프롬프트가 복사됐어요!'), backgroundColor: kBlue, duration: Duration(seconds: 2)));
                  },
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('프롬프트 복사'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF7B5EA7), foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
              ])),
          ])));
  }
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
        final groups = Store.getRealGroups();
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
                  final count = Store.getAbbreviations().where((a) => a.groupIds.contains(g.id)).length;
                  return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: const Color(0xFFEEF0F8))),
                    child: Row(children: [
                      Column(mainAxisSize: MainAxisSize.min, children: [
                        GestureDetector(onTap: i == 0 ? null : () => Store.moveGroupUp(g.id),
                          child: Icon(Icons.keyboard_arrow_up_rounded, size: 20,
                              color: i == 0 ? const Color(0xFFDDDDDD) : Colors.grey)),
                        GestureDetector(onTap: i == groups.length - 1 ? null : () => Store.moveGroupDown(g.id),
                          child: Icon(Icons.keyboard_arrow_down_rounded, size: 20,
                              color: i == groups.length - 1 ? const Color(0xFFDDDDDD) : Colors.grey)),
                      ]),
                      const SizedBox(width: 6),
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
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> doSave() async {
        final name = nameCtrl.text.trim();
        if (name.isEmpty) return;
        await Store.saveGroup(GroupModel(
          id: existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
          name: name, colorValue: selectedColor.value,
          order: existing?.order ?? Store.nextGroupOrder()));
        if (ctx.mounted) Navigator.pop(ctx);
      }
      return _EnterToConfirm(onConfirm: doSave, child: AlertDialog(
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
            onPressed: doSave, child: const Text('저장')),
        ]));
    }));
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
            for (final a in Store.getAbbreviations().where((a) => a.groupIds.contains(g.id)))
              await Store.saveAbbreviation(a.copyWith(groupIds: a.groupIds.where((id) => id != g.id).toList()));
            if (ctx.mounted) Navigator.pop(ctx);
          }, child: const Text('삭제')),
      ]));
  }
}

// 약어 등록 시 키보드 클릭으로 초/중/종성 입력하는 위젯
class _SoggiKeyboardInput extends StatefulWidget {
  final void Function(String label, String type) onKeyTap;
  final bool Function(String label, String type)? isOn;
  const _SoggiKeyboardInput({required this.onKeyTap, this.isOn});
  @override State<_SoggiKeyboardInput> createState() => _SoggiKeyboardInputState();
}
class _SoggiKeyboardInputState extends State<_SoggiKeyboardInput> {
  bool _show = false;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
    GestureDetector(
      onTap: () => setState(() => _show = !_show),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(_show ? Icons.keyboard_hide_rounded : Icons.keyboard_rounded, size: 16, color: kBlue),
        const SizedBox(width: 4),
        Text(_show ? '키보드 숨기기' : '키보드로 입력',
            style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.w600)),
      ])),
    if (_show) ...[
      const SizedBox(height: 8),
      // 가로 스크롤로 감싸지 않아야 창 크기에 맞춰 키보드 크기가 줄어듦
      _SoggiInputKeyboard(onKeyTap: widget.onKeyTap, isOn: widget.isOn),
    ],
  ]);
}

class _SoggiInputKeyboard extends StatelessWidget {
  final void Function(String label, String type) onKeyTap;
  final bool Function(String label, String type)? isOn;
  const _SoggiInputKeyboard({required this.onKeyTap, this.isOn});

  @override
  Widget build(BuildContext context) {
    final rows = <int, List<_SoggiKey>>{};
    for (final k in _kbKeys) {
      rows.putIfAbsent(k.row, () => []).add(k);
    }
    for (final r in rows.values) r.sort((a, b) => a.col.compareTo(b.col));

    Color keyBg(String type) {
      if (type == 'cho') return const Color(0xFFE8F0FE);
      if (type == 'jung') return const Color(0xFFF3E8FD);
      return const Color(0xFFFFE8E8);
    }
    Color keyFg(String type) {
      if (type == 'cho') return const Color(0xFF4A90E2);
      if (type == 'jung') return const Color(0xFF7B5EA7);
      return const Color(0xFFE2574A);
    }

    Widget buildKey(_SoggiKey k, {double w = 34, double h = 34, double fs = 13}) {
      final isThumb = k.row == 3;
      final mType = k.type == 'jong_special' ? 'jong' : k.type;
      final fgColor = keyFg(mType);
      final bgColor = keyBg(mType);
      final on = isOn?.call(k.label, mType) ?? false; // 눌려 있는(선택된) 키
      final br = isThumb
          ? BorderRadius.only(bottomLeft: Radius.circular(w/2), bottomRight: Radius.circular(w/2),
              topLeft: const Radius.circular(4), topRight: const Radius.circular(4))
          : BorderRadius.circular(6);
      return Container(
        width: w, height: h, margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(color: on ? fgColor : bgColor, borderRadius: br,
            border: Border.all(color: on ? fgColor : fgColor.withOpacity(0.4), width: on ? 1.5 : 1),
            boxShadow: on ? [BoxShadow(color: fgColor.withOpacity(0.4), blurRadius: 4, offset: const Offset(0, 2))] : null),
        child: Material(color: Colors.transparent, borderRadius: br,
          child: InkWell(
            onTap: () => onKeyTap(k.label, mType),
            borderRadius: br, splashColor: fgColor.withOpacity(0.4), highlightColor: fgColor.withOpacity(0.2),
            child: Center(child: Text(k.label,
                style: TextStyle(fontSize: fs, color: on ? Colors.white : fgColor, fontWeight: FontWeight.w700))))));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        _kbLegendStatic(const Color(0xFF4A90E2), '초성'),
        const SizedBox(width: 10),
        _kbLegendStatic(const Color(0xFF7B5EA7), '중성'),
        const SizedBox(width: 10),
        _kbLegendStatic(const Color(0xFFE2574A), '종성'),
      ]),
      const SizedBox(height: 6),
      LayoutBuilder(builder: (context, constraints) {
        // 한 줄 너비 = 키 10칸(키 38*scale + 마진 4) + 구분선 8*scale = 388*scale + 40
        // 사용 가능한 너비에 맞춰 배율을 계산해서 창이 작아지면 키보드도 같이 작아짐
        final avail = constraints.maxWidth.isFinite ? constraints.maxWidth : 428.0;
        final double scale = ((avail - 40) / 388).clamp(0.35, 1.0).toDouble();
        final double kw = 38.0 * scale;
        final double kh = 38.0 * scale;
        final double fs = (13.0 * scale).clamp(8.0, 13.0).toDouble();
        final double rowW = 10 * (kw + 4) + 8 * scale;
        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          for (int r = 0; r < 3; r++)
            Row(mainAxisSize: MainAxisSize.min, children: [
              ...rows[r]!.map((k) {
                if (k.col == 5 && rows[r]!.indexOf(k) > 0) {
                  return Row(mainAxisSize: MainAxisSize.min, children: [
                    Container(width: 4 * scale, height: kh * 0.8, margin: EdgeInsets.symmetric(horizontal: 2 * scale),
                        decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2))),
                    buildKey(k, w: kw, h: kh, fs: fs),
                  ]);
                }
                return buildKey(k, w: kw, h: kh, fs: fs);
              }),
            ]),
          SizedBox(height: 4 * scale),
          // 엄지 모음(중성): ㅗㅏㅜ는 초성 쪽, ㅡㅓㅣ는 종성 쪽 아래에 붙어서 키보드 가운데에 정렬
          SizedBox(width: rowW, child: Center(
            child: Row(mainAxisSize: MainAxisSize.min,
                children: rows[3]!.map((k) => buildKey(k, w: kw + 2, h: kh * 1.2, fs: fs)).toList()))),
        ]);
      }),
    ]);
  }

  Widget _kbLegendStatic(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 9, color: Colors.grey)),
  ]);
}

// ── 속기 키보드 배열 시각화 ──────────────────────────────────────────────────

// 각 키의 ID → 표시 문자, 타입(cho/jung/jong), 행/열 위치
// 레이아웃: 왼사이드(col=0), 왼본체(col=1~4), 오른본체(col=5~8), 오른사이드(col=9)
// type: cho=초성, jong=종성, jung=중성, jong_special=(ㅋ)종성
class _SoggiKey {
  final String label, type;
  final int row, col;
  const _SoggiKey(this.label, this.type, this.row, this.col);
}

const _kbKeys = [
  // 왼쪽 사이드 (col 0)
  _SoggiKey('ㅊ','cho',0,0), _SoggiKey('ㅅ','cho',1,0), _SoggiKey('ㅁ','cho',2,0),
  // 왼쪽 본체 상단 (row 0, col 1~4)
  _SoggiKey('ㅌ','cho',0,1), _SoggiKey('ㅋ','cho',0,2), _SoggiKey('ㅂ','cho',0,3), _SoggiKey('ㅍ','cho',0,4),
  // 왼쪽 본체 중단 (row 1, col 1~4)
  _SoggiKey('ㄷ','cho',1,1), _SoggiKey('ㅈ','cho',1,2), _SoggiKey('ㄱ','cho',1,3), _SoggiKey('(ㅋ)','jong_special',1,4),
  // 왼쪽 본체 하단 (row 2, col 1~4)
  _SoggiKey('ㄹ','cho',2,1), _SoggiKey('ㄴ','cho',2,2), _SoggiKey('ㅎ','cho',2,3), _SoggiKey('ㅢ','jung',2,4),
  // 오른쪽 본체 상단 (row 0, col 5~8)
  _SoggiKey('ㄲ','jong',0,5), _SoggiKey('ㅎ','jong',0,6), _SoggiKey('ㅌ','jong',0,7), _SoggiKey('ㅊ','jong',0,8),
  // 오른쪽 본체 중단 (row 1, col 5~8)
  _SoggiKey('ㄱ','jong',1,5), _SoggiKey('ㄴ','jong',1,6), _SoggiKey('ㄹ','jong',1,7), _SoggiKey('ㅅ','jong',1,8),
  // 오른쪽 본체 하단 (row 2, col 5~8)
  _SoggiKey('ㅆ','jong',2,5), _SoggiKey('ㅇ','jong',2,6), _SoggiKey('ㅁ','jong',2,7), _SoggiKey('ㄷ','jong',2,8),
  // 오른쪽 사이드 (col 9)
  _SoggiKey('ㅍ','jong',0,9), _SoggiKey('ㅂ','jong',1,9), _SoggiKey('ㅈ','jong',2,9),
  // 엄지 모음 (row 3, col 0~5)
  _SoggiKey('ㅗ','jung',3,0), _SoggiKey('ㅏ','jung',3,1), _SoggiKey('ㅜ','jung',3,2),
  _SoggiKey('ㅡ','jung',3,3), _SoggiKey('ㅓ','jung',3,4), _SoggiKey('ㅣ','jung',3,5),
];

// 약어 문자열에서 초/중/종성을 추출해서 어떤 키를 눌러야 하는지 반환
Map<String, Set<String>> _decomposeSoggi(String word) {
  const choseong =  ['ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
  const jungseong = ['ㅏ','ㅐ','ㅑ','ㅒ','ㅓ','ㅔ','ㅕ','ㅖ','ㅗ','ㅘ','ㅙ','ㅚ','ㅛ','ㅜ','ㅝ','ㅞ','ㅟ','ㅠ','ㅡ','ㅢ','ㅣ'];
  const jongseong = ['','ㄱ','ㄲ','ㄳ','ㄴ','ㄵ','ㄶ','ㄷ','ㄹ','ㄺ','ㄻ','ㄼ','ㄽ','ㄾ','ㄿ','ㅀ','ㅁ','ㅂ','ㅄ','ㅅ','ㅆ','ㅇ','ㅈ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
  final cho = <String>{}, jung = <String>{}, jong = <String>{};
  for (final ch in word.replaceAll('*',' ').runes.map(String.fromCharCode)) {
    final code = ch.codeUnitAt(0);
    if (code >= 0xAC00 && code <= 0xD7A3) {
      final idx = code - 0xAC00;
      final jongIdx = idx % 28;
      final jungIdx = (idx ~/ 28) % 21;
      final choIdx = idx ~/ 28 ~/ 21;
      cho.add(choseong[choIdx]);
      jung.add(jungseong[jungIdx]);
      if (jongIdx > 0) {
        final j = jongseong[jongIdx];
        // 종성 ㅋ → (ㅋ) 특수키로 변환
        jong.add(j == 'ㅋ' ? '(ㅋ)' : j);
      }
    } else if (RegExp(r'[ㄱ-ㅎ]').hasMatch(ch)) {
      cho.add(ch);
    } else if (RegExp(r'[ㅏ-ㅣ]').hasMatch(ch)) {
      jung.add(ch);
    }
  }
  return {'cho': cho, 'jung': jung, 'jong': jong};
}

class SoggiKeyboardWidget extends StatelessWidget {
  final AbbreviationModel abbr;
  const SoggiKeyboardWidget({super.key, required this.abbr});

  @override
  Widget build(BuildContext context) {
    // 약어 글자에서 추측하지 않고, 내가 등록해 둔 운지(초성/중성/종성)를 그대로 표시
    final choSet = abbr.initial.map((e) => e.trim()).toSet();
    final jungSet = abbr.medial.map((e) => e.trim()).toSet();
    final jongSet = abbr.final_.map((e) => e.trim()).map((e) => e == 'ㅋ' ? '(ㅋ)' : e).toSet();
    final hasStroke = choSet.isNotEmpty || jungSet.isNotEmpty || jongSet.isNotEmpty;

    Color keyColor(_SoggiKey k) {
      if (k.type == 'cho' && choSet.contains(k.label)) return const Color(0xFF4A90E2);
      if ((k.type == 'jung') && jungSet.contains(k.label)) return const Color(0xFF7B5EA7);
      if ((k.type == 'jong' || k.type == 'jong_special') && jongSet.contains(k.label)) return const Color(0xFFE2574A);
      return Colors.transparent;
    }
    Color textColor(_SoggiKey k) {
      final c = keyColor(k);
      return c == Colors.transparent ? Colors.black87 : Colors.white;
    }

    final rows = <int, List<_SoggiKey>>{};
    for (final k in _kbKeys) {
      rows.putIfAbsent(k.row, () => []).add(k);
    }
    for (final r in rows.values) {
      r.sort((a, b) => a.col.compareTo(b.col));
    }

    const double kw = 34, kh = 34, fs = 13;
    Widget buildKey(_SoggiKey k, {double w = kw, double h = kh}) {
      final bg = keyColor(k);
      final isThumb = k.row == 3;
      return Container(
        width: w, height: h,
        margin: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: bg == Colors.transparent ? const Color(0xFFF0F0F5) : bg,
          borderRadius: isThumb
              ? BorderRadius.only(bottomLeft: Radius.circular(w/2), bottomRight: Radius.circular(w/2), topLeft: const Radius.circular(4), topRight: const Radius.circular(4))
              : BorderRadius.circular(6),
          border: Border.all(color: bg == Colors.transparent ? const Color(0xFFDDDDE8) : bg.withOpacity(0.7)),
          boxShadow: bg != Colors.transparent ? [BoxShadow(color: bg.withOpacity(0.4), blurRadius: 4, spreadRadius: 0, offset: const Offset(0,2))] : null,
        ),
        child: Center(child: Text(k.label, style: TextStyle(fontSize: fs, color: textColor(k), fontWeight: FontWeight.w700))),
      );
    }

    // 한 줄 너비: 키 10칸 x (34+4) + 구분선(6+4)
    const double rowW = 10 * (kw + 4) + 10;

    // 창이 좁으면 FittedBox가 키보드 전체를 비율대로 줄여 줌
    return FittedBox(fit: BoxFit.scaleDown, alignment: Alignment.centerLeft,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _kbLegend(const Color(0xFF4A90E2), '초성'),
          const SizedBox(width: 10),
          _kbLegend(const Color(0xFF7B5EA7), '중성'),
          const SizedBox(width: 10),
          _kbLegend(const Color(0xFFE2574A), '종성'),
        ]),
        if (!hasStroke)
          const Padding(padding: EdgeInsets.only(top: 6),
            child: Text('등록된 운지가 없습니다', style: TextStyle(fontSize: 11, color: Colors.grey))),
        const SizedBox(height: 8),
        for (int r = 0; r < 3; r++)
          Row(mainAxisSize: MainAxisSize.min, children: [
            ...rows[r]!.map((k) {
              if (k.col == 5 && rows[r]!.indexOf(k) > 0) {
                return Row(mainAxisSize: MainAxisSize.min, children: [
                  Container(width: 6, height: 34, margin: const EdgeInsets.symmetric(horizontal: 2),
                    decoration: BoxDecoration(color: const Color(0xFFE0E0E0), borderRadius: BorderRadius.circular(2))),
                  buildKey(k),
                ]);
              }
              return buildKey(k);
            }),
          ]),
        const SizedBox(height: 4),
        // 엄지 모음(중성): 가운데 정렬 (ㅗㅏㅜ = 초성 쪽 아래, ㅡㅓㅣ = 종성 쪽 아래, 서로 붙어 있음)
        SizedBox(width: rowW, child: Center(
          child: Row(mainAxisSize: MainAxisSize.min,
            children: rows[3]!.map((k) => buildKey(k, w: kw, h: 44)).toList()))),
      ]));
  }

  Widget _kbLegend(Color color, String label) => Row(mainAxisSize: MainAxisSize.min, children: [
    Container(width: 10, height: 10, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3))),
    const SizedBox(width: 4),
    Text(label, style: const TextStyle(fontSize: 10, color: Colors.grey)),
  ]);
}

// ─────────────────────────────────────────────────────────────────────────────

class _AbbrContent extends StatelessWidget {
  final AbbreviationModel abbr;
  final List<GroupModel> groups;
  final bool selectable; // true면 약어 글자를 드래그·복사할 수 있음 (선택 모드가 아닌 목록용)
  const _AbbrContent({required this.abbr, required this.groups, this.selectable = false});
  @override
  Widget build(BuildContext context) {
    final abbrGroups = groups.where((g) => abbr.groupIds.contains(g.id)).toList();
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        if (abbr.isAttached) const Padding(padding: EdgeInsets.only(right: 3),
          child: Icon(Icons.south_west_rounded, size: 16, color: kBlueDark)),
        selectable
          ? SelectionArea(child: Text(abbr.displayWord, style: TextStyle(color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 15)))
          : Text(abbr.displayWord, style: TextStyle(color: abbr.typeColor, fontWeight: FontWeight.w700, fontSize: 15)),
        ...abbr.typeLabels.map((label) {
          final color = label == '동시' ? kPurple : label == '합성' ? kBlueSky : kBlueDark;
          final bgColor = label == '동시' ? kPurpleLight : const Color(0xFFE0F4FF);
          return Container(margin: const EdgeInsets.only(left: 4),
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(color: bgColor, borderRadius: BorderRadius.circular(8)),
            child: Text(label, style: TextStyle(fontSize: 10, color: color, fontWeight: FontWeight.w700)));
        }),
...abbrGroups.map((group) => Container(margin: const EdgeInsets.only(left: 4),
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          decoration: BoxDecoration(color: group.color.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
          child: Text(group.name, style: TextStyle(fontSize: 10, color: group.color, fontWeight: FontWeight.w700)))),
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
      Expanded(child: _AbbrContent(abbr: widget.abbr, groups: widget.groups, selectable: true)),
      PopupMenuButton<String>(
        icon: const Icon(Icons.more_horiz, color: Colors.grey),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        itemBuilder: (_) => [
          PopupMenuItem(child: Text(widget.abbr.isFavorite ? '⭐ 즐겨찾기 해제' : '☆ 즐겨찾기 추가'),
              onTap: () => widget.onFav?.call()),
          PopupMenuItem(child: const Text('⌨️ 키보드 보기'),
              onTap: () => showDialog(context: context, builder: (_) => AlertDialog(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                title: Text(widget.abbr.displayWord.replaceAll('*',' '),
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                content: SoggiKeyboardWidget(abbr: widget.abbr),
                actions: [TextButton(onPressed: () => Navigator.pop(context),
                    child: const Text('닫기', style: TextStyle(color: Colors.grey)))],
              ))),
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
  final bool isComposite, isConcurrent, isAttached;
  final ValueChanged<bool> onCompositeChanged, onConcurrentChanged, onAttachedChanged;
  const _TypeToggleRow({required this.isComposite, required this.isConcurrent,
    required this.isAttached,
    required this.onCompositeChanged, required this.onConcurrentChanged,
    required this.onAttachedChanged});
  @override
  Widget build(BuildContext context) => Wrap(spacing: 6, runSpacing: 6, children: [
    _ToggleChip(label: '합성약어', color: kBlueSky, selected: isComposite, onTap: () => onCompositeChanged(!isComposite)),
    _ToggleChip(label: '동시처리', color: kPurple, selected: isConcurrent, onTap: () => onConcurrentChanged(!isConcurrent)),
    _ToggleChip(label: '붙여쓰기', color: kBlueDark, selected: isAttached, onTap: () => onAttachedChanged(!isAttached)),
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

// 긴 텍스트는 maxLines(기본 10줄)까지만 보여주고 '더보기'로 전체 확인
class _ClampedText extends StatefulWidget {
  final String text;
  final TextStyle style;
  final bool selectable;
  final int maxLines;
  const _ClampedText({required this.text, required this.style, this.selectable = false, this.maxLines = 10});
  @override State<_ClampedText> createState() => _ClampedTextState();
}
class _ClampedTextState extends State<_ClampedText> {
  bool _expanded = false;
  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (ctx, cons) {
    final tp = TextPainter(
      text: TextSpan(text: widget.text, style: widget.style),
      textDirection: TextDirection.ltr, maxLines: widget.maxLines)
      ..layout(maxWidth: cons.maxWidth.isFinite ? cons.maxWidth : 10000);
    final overflow = tp.didExceedMaxLines;
    final collapsed = overflow && !_expanded;
    final body = widget.selectable
        ? SelectableText(widget.text, style: widget.style, maxLines: collapsed ? widget.maxLines : null)
        : Text(widget.text, style: widget.style, maxLines: collapsed ? widget.maxLines : null,
            overflow: collapsed ? TextOverflow.ellipsis : TextOverflow.clip);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      body,
      if (overflow)
        GestureDetector(
          onTap: () => setState(() => _expanded = !_expanded),
          child: Padding(padding: const EdgeInsets.only(top: 6),
            child: Text(_expanded ? '접기' : '더보기',
                style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.w600)))),
    ]);
  });
}

class SentenceRegisterScreen extends StatefulWidget {
  const SentenceRegisterScreen({super.key});
  @override State<SentenceRegisterScreen> createState() => _SentenceRegisterScreenState();
}
class _SentenceRegisterScreenState extends State<SentenceRegisterScreen> with _SelectionMixin<SentenceRegisterScreen> {
  final _ctrl = TextEditingController(); final _focusNode = FocusNode();
  @override void dispose() { _ctrl.dispose(); _focusNode.dispose(); super.dispose(); }

  Future<void> _bulkDelete(BuildContext context, List<SavedSentenceModel> all) async {
    if (!await _confirmBulkDelete(context)) return;
    for (final s in all.where((s) => _selected.contains(s.id)))
      await Store.deleteSentence(s.id);
    _exitSelectMode();
  }

  void _bulkRemind(BuildContext context, List<SavedSentenceModel> all) {
    final targets = all.where((s) => _selected.contains(s.id)).map((s) => s.text).toList();
    _showBulkReminderDialog(context, targets, 'sentence');
    _exitSelectMode();
  }

  void _bulkCopy(List<SavedSentenceModel> all) {
    final text = all.where((s) => _selected.contains(s.id)).map((s) => s.text).join('\n');
    Clipboard.setData(ClipboardData(text: text));
    _exitSelectMode();
  }

  void _bulkCopyForAI(List<SavedSentenceModel> all) {
    final sentences = all.where((s) => _selected.contains(s.id)).map((s) => s.text).join('\n');
    final prompt = '다음 문장들과 비슷한 스타일로 자연스러운 한국어 문장을 만들어줘:\n$sentences';
    Clipboard.setData(ClipboardData(text: prompt));
    _exitSelectMode();
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
            _exitSelectMode();
          }, child: const Text('저장')),
      ]));
  }

  void _save(BuildContext context) {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    bool saving = false; // Enter/버튼 중복 저장 방지
    Future<void> doSave(BuildContext ctx) async {
      if (saving) return;
      saving = true;
      await Store.saveSentence(SavedSentenceModel(
        id: DateTime.now().millisecondsSinceEpoch.toString(), text: text,
        createdAt: DateTime.now().toString().substring(0, 10)));
      _ctrl.clear(); if (ctx.mounted) Navigator.pop(ctx);
    }
    showDialog(context: context, builder: (ctx) => _EnterToConfirm(
      onConfirm: () => doSave(ctx),
      child: AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('저장 확인', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
      content: const Text('저장할까요?'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
        ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
          onPressed: () => doSave(ctx), child: const Text('저장')),
      ])));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('sentences').listenable(),
      builder: (context, box, _) {
        final sentences = Store.getSentences();
        return Scaffold(backgroundColor: Colors.white, resizeToAvoidBottomInset: true,
          body: SafeArea(child: Column(children: [
            Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  const Text('문장 등록', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                  if (!_selectMode)
                    GestureDetector(onTap: _toggleSelectMode, child: _iconToolBtn(Icons.checklist_rounded)),
                ]),
                if (_selectMode) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (_selected.length == 1)
                      GestureDetector(onTap: () => _editSelected(context, sentences),
                        child: _actionChip(Icons.edit_rounded, '수정', kBlueSky)),
                    GestureDetector(onTap: () => _bulkRemind(context, sentences),
                      child: _actionChip(Icons.notifications_rounded, '리마인드', kBlue)),
                    GestureDetector(onTap: () => _bulkCopy(sentences),
                      child: _actionChip(Icons.copy, '복사', kBlueSky)),
                    GestureDetector(onTap: () => _bulkCopyForAI(sentences),
                      child: _actionChip(Icons.auto_awesome_rounded, 'AI 복사', kPurple)),
                    GestureDetector(onTap: () => _bulkDelete(context, sentences),
                      child: _actionChip(Icons.delete_rounded, '삭제', Colors.red)),
                    GestureDetector(onTap: _toggleSelectMode,
                      child: _actionChip(Icons.close, '취소', Colors.grey)),
                  ]),
                ],
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
              Focus(onKeyEvent: (node, event) {
                if (event is KeyDownEvent &&
                    (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) &&
                    HardwareKeyboard.instance.isControlPressed) {
                  _save(context);
                  return KeyEventResult.handled;
                }
                return KeyEventResult.ignored;
              },
              child: TextField(controller: _ctrl, focusNode: _focusNode, maxLines: 3,
                decoration: InputDecoration(hintText: '복습할 문장을 입력하세요... (Ctrl+Enter로 저장)',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: kBlue))))),
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
                            Expanded(child: _ClampedText(text: s.text, style: const TextStyle(fontSize: 14, height: 1.6))),
                          ])));
                    }
                    return Container(margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFEEF0F8))),
                      child: Row(children: [
                        Expanded(child: _ClampedText(text: s.text, selectable: true, style: const TextStyle(fontSize: 14, height: 1.6))),
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
class _RemindersScreenState extends State<RemindersScreen> with _SelectionMixin<RemindersScreen> {
  String _tl(String t) => t == 'word' ? '약어' : t == 'favorite' ? '즐겨찾기' : '문장';

  Future<void> _bulkDelete(BuildContext context, List<ReminderModel> all) async {
    if (!await _confirmBulkDelete(context)) return;
    for (final r in all.where((r) => _selected.contains(r.id)))
      await Store.deleteReminder(r.id);
    _exitSelectMode();
  }

  void _editSelected(BuildContext context, List<ReminderModel> all) {
    if (_selected.isEmpty) return;
    final selectedReminders = all.where((r) => _selected.contains(r.id)).toList();
    final single = selectedReminders.length == 1;
    final r0 = selectedReminders.first;
    final targetCtrl = TextEditingController(text: single ? r0.target.replaceAll('*', ' ') : '');
    int interval = r0.intervalDays;
    bool repeat = r0.repeat;
    DateTime date = DateTime.tryParse(r0.date) ?? DateTime.now();

    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      Future<void> doSave() async {
        final ds = _ymd(date);
        if (single) {
          final target = targetCtrl.text.trim();
          if (target.isEmpty) return;
          await Store.saveReminder(ReminderModel(
            id: r0.id, type: r0.type,
            target: r0.type == 'word' ? encodeWord(target) : target,
            date: ds, intervalDays: interval, repeat: repeat, active: r0.active));
        } else {
          for (final r in selectedReminders) {
            await Store.saveReminder(ReminderModel(
              id: r.id, type: r.type, target: r.target,
              date: ds, intervalDays: interval, repeat: repeat, active: r.active));
          }
        }
        if (ctx.mounted) Navigator.pop(ctx);
        _exitSelectMode();
      }
      return _EnterToConfirm(onConfirm: doSave, child: AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(single ? '리마인드 수정' : '리마인드 일괄 수정 (${selectedReminders.length}개)',
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (single) ...[
            _lbl(r0.type == 'word' ? '약어' : '문장'),
            TextField(controller: targetCtrl, maxLines: r0.type == 'sentence' ? 3 : 1, decoration: _inputDeco('')),
            const SizedBox(height: 12),
          ],
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
                Text(_ymd(date),
                    style: const TextStyle(fontSize: 14)),
              ]))),
          const SizedBox(height: 12),
          _lbl('간격'),
          _IntervalRepeatPicker(interval: interval, repeat: repeat,
            onIntervalChanged: (v) => setS(() => interval = v),
            onRepeatChanged: (v) => setS(() => repeat = v)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
            onPressed: doSave, child: const Text('저장')),
        ]));
    }));
  }

  // 선택된 리마인드(약어 유형)의 실제 약어들을 하나 이상의 그룹에 일괄 추가
  void _groupifySelected(BuildContext context, List<ReminderModel> all) async {
    final targets = all.where((r) => _selected.contains(r.id) && r.type == 'word').toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('약어 리마인드만 그룹에 추가할 수 있어요'), backgroundColor: kBlue, duration: Duration(seconds: 2)));
      return;
    }
    final groups = Store.getGroups();
    if (groups.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('먼저 그룹을 만들어 주세요'), backgroundColor: kBlue, duration: Duration(seconds: 2)));
      return;
    }
    final Set<String> checked = {};
    final apply = await showDialog<bool>(context: context, builder: (ctx) => StatefulBuilder(
      builder: (ctx, setS) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('그룹 추가 (중복 가능)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
          ...groups.map((g) => CheckboxListTile(
            value: checked.contains(g.id),
            activeColor: g.color,
            secondary: CircleAvatar(backgroundColor: g.color, radius: 10),
            title: Text(g.name),
            onChanged: (v) => setS(() { if (v == true) checked.add(g.id); else checked.remove(g.id); }))),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true), child: const Text('추가')),
        ])));
    if (apply != true || checked.isEmpty) return;
    final abbrevs = Store.getAbbreviations();
    for (final r in targets) {
      AbbreviationModel? a;
      try { a = abbrevs.firstWhere((x) => x.word == r.target); } catch (_) { a = null; }
      if (a != null) {
        final newIds = {...a.groupIds, ...checked}.toList();
        await Store.saveAbbreviation(a.copyWith(groupIds: newIds));
      }
    }
    if (context.mounted) {
      _exitSelectMode();
    }
  }

  // 선택된 리마인드(약어 유형)의 실제 약어들로 바로 테스트 시작
  void _testSelected(BuildContext context, List<ReminderModel> all) {
    final targets = all.where((r) => _selected.contains(r.id) && r.type == 'word').toList();
    if (targets.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('약어 리마인드를 선택해주세요'), backgroundColor: kBlue, duration: Duration(seconds: 2)));
      return;
    }
    final abbrevs = Store.getAbbreviations();
    final items = <AbbreviationModel>[];
    for (final r in targets) {
      try { items.add(abbrevs.firstWhere((x) => x.word == r.target)); } catch (_) {}
    }
    if (items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('해당 약어를 찾을 수 없어요'), backgroundColor: kBlue, duration: Duration(seconds: 2)));
      return;
    }
    _exitSelectMode();
    // 새 화면을 덮지 않고 하단 바가 있는 테스트 탭으로 전환
    kQuizPreset.value = items;
    kTabRequest.value = 5;
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(valueListenable: Hive.box('reminders').listenable(),
      builder: (context, box, _) {
        final reminders = Store.getReminders();
        return Scaffold(backgroundColor: Colors.white,
          body: SafeArea(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(20,20,20,12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    const Text('리마인드', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
                    Text('${reminders.length}개', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                  ]),
                  if (!_selectMode) ...[
                    Row(children: [
                      GestureDetector(onTap: _toggleSelectMode,
                        child: Padding(padding: const EdgeInsets.only(right: 8), child: _iconToolBtn(Icons.checklist_rounded))),
                      ElevatedButton.icon(onPressed: () => _showAddReminderDialog(context),
                        icon: const Icon(Icons.add, size: 16), label: const Text('추가'),
                        style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6))),
                    ]),
                  ],
                ]),
                if (_selectMode) ...[
                  const SizedBox(height: 10),
                  Wrap(spacing: 6, runSpacing: 6, children: [
                    if (_selected.isNotEmpty) ...[
                      GestureDetector(onTap: () => _editSelected(context, reminders),
                        child: _actionChip(Icons.edit_rounded, '수정', kBlueSky)),
                      GestureDetector(onTap: () => _groupifySelected(context, reminders),
                        child: _actionChip(Icons.label_rounded, '그룹화', kPurple)),
                      GestureDetector(onTap: () => _testSelected(context, reminders),
                        child: _actionChip(Icons.quiz_rounded, '테스트', kBlueDark)),
                    ],
                    GestureDetector(onTap: () => _bulkDelete(context, reminders),
                      child: _actionChip(Icons.delete_rounded, '삭제', Colors.red)),
                    GestureDetector(onTap: _toggleSelectMode,
                      child: _actionChip(Icons.close, '취소', Colors.grey)),
                  ]),
                ],
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
                          SelectionArea(child: Text('${r.date} · ${r.intervalDays}일 간격${r.repeat ? " · 반복" : ""}', style: const TextStyle(fontSize: 11, color: Colors.grey))),
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
    String type = 'word'; final Set<String> selectedTargets = {};
    final customCtrl = TextEditingController(); bool useCustom = false;
    final pickerSearchCtrl = TextEditingController();
    showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
      final abbrevs = Store.getAbbreviations(); final sentences = Store.getSentences();
      var items = type == 'word' ? abbrevs.map((a) => a.displayWord).toList() : sentences.map((s) => s.text).toList();
      final q = pickerSearchCtrl.text.trim();
      if (q.isNotEmpty) {
        items = items.where((t) => t.replaceAll('*', ' ').contains(q) || t.contains(q)).toList();
      }
      return AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('리마인드 추가', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
        content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          _lbl('유형'),
          Row(children: [
            Expanded(child: GestureDetector(onTap: () => setS(() { type = 'word'; selectedTargets.clear(); }),
              child: Container(padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: type == 'word' ? kBlue : kBlueLight, borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('약어', style: TextStyle(color: type == 'word' ? Colors.white : kBlue, fontWeight: FontWeight.w700)))))),
            const SizedBox(width: 8),
            Expanded(child: GestureDetector(onTap: () => setS(() { type = 'sentence'; selectedTargets.clear(); }),
              child: Container(padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(color: type == 'sentence' ? kBlue : kBlueLight, borderRadius: BorderRadius.circular(8)),
                child: Center(child: Text('문장', style: TextStyle(color: type == 'sentence' ? Colors.white : kBlue, fontWeight: FontWeight.w700)))))),
          ]),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: _lbl(type == 'word' ? '약어 선택 (중복 선택 가능)' : '문장 선택 (중복 선택 가능)')),
            if (selectedTargets.isNotEmpty)
              Text('${selectedTargets.length}개 선택됨', style: const TextStyle(fontSize: 12, color: kBlue, fontWeight: FontWeight.w600)),
          ]),
          TextField(controller: pickerSearchCtrl, onChanged: (_) => setS(() {}),
            decoration: _inputDeco('검색...').copyWith(
              prefixIcon: const Icon(Icons.search, size: 18, color: Colors.grey),
              isDense: true, contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8))),
          const SizedBox(height: 8),
          if (items.isEmpty)
            Padding(padding: const EdgeInsets.only(bottom: 8),
                child: Text(q.isNotEmpty ? '검색 결과가 없습니다' : (type == 'word' ? '등록된 약어가 없습니다' : '등록된 문장이 없습니다'),
                    style: const TextStyle(color: Colors.grey, fontSize: 12)))
          else Container(height: 280,
            decoration: BoxDecoration(border: Border.all(color: const Color(0xFFE0E0E0)), borderRadius: BorderRadius.circular(8)),
            child: ListView.builder(itemCount: items.length, itemBuilder: (_, i) {
              final item = items[i]; final isSel = selectedTargets.contains(item);
              return GestureDetector(
                onTap: () => setS(() { if (isSel) selectedTargets.remove(item); else selectedTargets.add(item); }),
                child: Container(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  color: isSel ? kBlueLight : Colors.transparent,
                  child: Row(children: [
                    Checkbox(value: isSel, activeColor: kBlue,
                      onChanged: (v) => setS(() { if (v == true) selectedTargets.add(item); else selectedTargets.remove(item); })),
                    Expanded(child: Text(item, style: TextStyle(fontSize: 13, color: isSel ? kBlue : Colors.black87,
                        fontWeight: isSel ? FontWeight.w600 : FontWeight.w400), maxLines: 2, overflow: TextOverflow.ellipsis)),
                  ])));
            })),
          const SizedBox(height: 8),
          Row(children: [
            Checkbox(value: useCustom, activeColor: kBlue,
                onChanged: (v) => setS(() { useCustom = v ?? false; })),
            const Text('직접 입력 추가', style: TextStyle(fontSize: 13)),
          ]),
          if (useCustom) TextField(controller: customCtrl, decoration: _inputDeco('내용을 입력하세요')),
          const SizedBox(height: 12),
          _lbl('간격'),
          _IntervalRepeatPicker(interval: interval, repeat: repeat,
            onIntervalChanged: (v) => setS(() => interval = v),
            onRepeatChanged: (v) => setS(() => repeat = v)),
        ])),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
          ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
            onPressed: () async {
              final targets = <String>[...selectedTargets];
              if (useCustom && customCtrl.text.trim().isNotEmpty) targets.add(customCtrl.text.trim());
              if (targets.isEmpty) return;
              Navigator.pop(ctx);
              final hasDup = targets.any((t) => Store.findReminder(t) != null);
              if (hasDup) {
                final ok = await showDialog<bool>(context: context, builder: (c2) => AlertDialog(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  title: const Text('중복 리마인드', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                  content: const Text('이미 추가된 리마인드가 있습니다.\n그래도 저장하시겠습니까?'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(c2, false), child: const Text('취소', style: TextStyle(color: Colors.grey))),
                    ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
                        onPressed: () => Navigator.pop(c2, true), child: const Text('저장'))]));
                if (ok != true) return;
              }
              final date = DateTime.now().add(Duration(days: interval));
              final ds = _ymd(date);
              for (int i = 0; i < targets.length; i++) {
                await Store.saveReminder(ReminderModel(
                  id: '${DateTime.now().millisecondsSinceEpoch}_$i',
                  type: type, target: targets[i], date: ds, intervalDays: interval, repeat: repeat));
              }
            }, child: const Text('설정')),
        ]);
    }));
  }
}

// 리마인드 간격/반복 선택 UI (단일/일괄 설정 다이얼로그에서 공용으로 사용)
class _IntervalRepeatPicker extends StatelessWidget {
  final int interval;
  final bool repeat;
  final ValueChanged<int> onIntervalChanged;
  final ValueChanged<bool> onRepeatChanged;
  const _IntervalRepeatPicker({
    required this.interval, required this.repeat,
    required this.onIntervalChanged, required this.onRepeatChanged});
  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
    Wrap(spacing: 8, children: [1, 3, 7].map((d) => GestureDetector(onTap: () => onIntervalChanged(d),
      child: Container(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(color: interval == d ? kBlue : kBlueLight, borderRadius: BorderRadius.circular(20)),
        child: Text('$d일', style: TextStyle(color: interval == d ? Colors.white : kBlue, fontWeight: FontWeight.w700))))).toList()),
    const SizedBox(height: 10),
    Row(children: [
      Checkbox(value: repeat, activeColor: kBlue, onChanged: (v) => onRepeatChanged(v ?? false)),
      const Text('반복'),
    ]),
  ]);
}

void _showReminderDialog(BuildContext context, String target, String type) =>
    _reminderDialog(context, [target], type);

void _showBulkReminderDialog(BuildContext context, List<String> targets, String type) =>
    _reminderDialog(context, targets, type, bulk: true);

// 리마인드 설정 팝업: 단일 항목(기존 설정 수정 포함) / 여러 항목 한 번에
void _reminderDialog(BuildContext context, List<String> targets, String type, {bool bulk = false}) {
  final existing = bulk ? null : Store.findReminder(targets.first);
  int interval = existing?.intervalDays ?? 1;
  bool repeat = existing?.repeat ?? false;
  showDialog(context: context, builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => AlertDialog(
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    title: Text(bulk ? '리마인드 설정 (${targets.length}개)' : (existing != null ? '리마인드 수정' : '리마인드 설정'),
        style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w700)),
    content: _IntervalRepeatPicker(interval: interval, repeat: repeat,
      onIntervalChanged: (v) => setS(() => interval = v),
      onRepeatChanged: (v) => setS(() => repeat = v)),
    actions: [
      TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('취소', style: TextStyle(color: Colors.grey))),
      ElevatedButton(style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white),
        onPressed: () async {
          final ds = _ymd(DateTime.now().add(Duration(days: interval)));
          for (final t in targets) {
            await Store.saveReminder(ReminderModel(
              id: bulk
                  ? '${DateTime.now().millisecondsSinceEpoch}_${t.hashCode}'
                  : (existing?.id ?? DateTime.now().millisecondsSinceEpoch.toString()),
              type: type, target: t, date: ds, intervalDays: interval, repeat: repeat));
          }
          if (ctx.mounted) Navigator.pop(ctx);
        }, child: Text(bulk ? '설정' : '저장')),
    ])));
}

// ── 스프린트(타이핑 연습) 화면 ──────────────────────────────────────────────────────────
// 타율(정확도)과 속도를 연습하는 곳.
// - 저장된 문장을 여러 개 골라 순서대로 연습 (Enter: 다음 문장 / 마지막 문장에서 Enter: 결과)
// - 중단(Esc)하면 그때까지 친 만큼으로 결과를 내고 기록
// - 20줄을 넘는 긴 글은 위 3분의 2는 문장, 아래 3분의 1은 타이핑 창으로 나눠서 보여주고
//   내가 치고 있는 자리가 문장 칸의 가운데에 오도록 부드럽게 따라가며 스크롤
// - 치는 동안의 시간은 순공시간(스프린트)으로 쌓임
class TypingPracticeScreen extends StatefulWidget {
  const TypingPracticeScreen({super.key});
  @override State<TypingPracticeScreen> createState() => _TypingPracticeScreenState();
}

// 글자 비교 결과 (공백·줄바꿈을 뺀 글자 기준)
class _SprintDiff {
  final int oja, chum, tal, alignEnd; // alignEnd: 지금까지 친 글자가 목표 문장의 어디까지에 해당하는지
  final List<String> states;          // 목표 글자별 상태: correct / wrong / pending
  const _SprintDiff(this.oja, this.chum, this.tal, this.alignEnd, this.states);
}

// 결과 화면용 글자별 비교 (ok 맞음 / oja 오자 / chum 첨자 / tal 탈자)
class _SOp {
  final String kind;
  final String typed, target; // 친 글자 / 원문 글자 (해당 없으면 '')
  const _SOp(this.kind, this.typed, this.target);
}
class _SprintSentenceResult {
  final String target;        // 원문 (공백·줄바꿈 포함)
  final List<int> normToFull; // 공백 뺀 위치 → 원문 위치
  final List<_SOp> ops;
  const _SprintSentenceResult(this.target, this.normToFull, this.ops);
}

class _TypingPracticeScreenState extends State<TypingPracticeScreen> with SingleTickerProviderStateMixin {
  static const int kLongLines = 20; // 이 줄 수를 넘으면 위 2/3 · 아래 1/3 배치
  static const double kBoxPad = 16;
  static const TextStyle _baseStyle = TextStyle(fontSize: 18, fontWeight: FontWeight.w700);

  final _textCtrl = TextEditingController();
  final _inputCtrl = TextEditingController();
  final _inputFocus = FocusNode();
  final _resultFocus = FocusNode();
  final _sentenceScroll = ScrollController();
  late final Ticker _ticker;

  // 문장 선택 (저장된 문장 id, 누른 순서대로)
  final List<String> _selectedIds = [];

  // 진행 상태
  List<String> _queue = [];
  int _idx = 0;
  bool _started = false, _finished = false, _stoppedEarly = false, _savedToHome = false;
  DateTime? _resultShownAt;
  int _elapsedSec = 0;
  int _sprintMs = 0; // 이번 스프린트에서 쌓은 순공시간 (결과 화면용)
  Timer? _timer;
  bool _advancing = false;

  // 결과 화면에 보여줄 문장별 비교 결과
  final List<_SprintSentenceResult> _sentenceResults = [];

  // 끝낸 문장들의 누적 / 지금 치는 문장
  int _accOja = 0, _accChum = 0, _accTal = 0, _accTyped = 0, _doneCount = 0;
  int _ojaCnt = 0, _chumCnt = 0, _talCnt = 0, _totalTyped = 0;
  String _lastValue = '';

  // 지금 문장
  String _target = '';
  String _targetN = '';          // 공백·줄바꿈 뺀 목표
  List<int> _normToFull = [];    // 공백 뺀 위치 → 원문 위치
  List<String> _states = [];
  int _alignEnd = 0;

  // 긴 글 자동 스크롤
  double _boxInnerW = 0;
  double _scrollTarget = 0;
  Duration _lastElapsed = Duration.zero;
  TextPainter? _tp;
  String _tpKey = '';
  final Map<String, int> _lineCache = {};

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
  }

  @override
  void dispose() {
    _ticker.dispose();
    _timer?.cancel();
    // 화면을 나가도 지금까지 친 시간은 순공시간으로 저장
    if (TypingTracker.sprint.active) TypingTracker.sprint.finish();
    _textCtrl.dispose();
    _inputCtrl.dispose();
    _inputFocus.dispose();
    _resultFocus.dispose();
    _sentenceScroll.dispose();
    super.dispose();
  }

  // ── 합계 (끝낸 문장 + 지금 치는 문장) ──
  int get _sumOja => _accOja + _ojaCnt;
  int get _sumChum => _accChum + _chumCnt;
  int get _sumTal => _accTal + _talCnt;
  int get _sumTyped => _accTyped + _totalTyped;
  int get _sumErrors => _sumOja + _sumChum + _sumTal;
  // 타수 = 타이핑한 글자 수 ÷ 걸린 시간(분)
  double get _tasu => _elapsedSec > 0 ? (_sumTyped / (_elapsedSec / 60)) : 0;
  double get _accuracy => _sumTyped > 0
      ? ((_sumTyped - _sumErrors) / _sumTyped * 100).clamp(0, 100).toDouble()
      : 100;

  // ── 시작 / 문장 불러오기 ──
  int _readyCount(List<SavedSentenceModel> sentences) {
    final ids = sentences.map((s) => s.id).toSet();
    return (_textCtrl.text.trim().isNotEmpty ? 1 : 0) + _selectedIds.where(ids.contains).length;
  }

  void _begin(List<SavedSentenceModel> sentences) {
    final items = <String>[];
    final custom = _textCtrl.text.trim();
    if (custom.isNotEmpty) items.add(custom);
    for (final id in _selectedIds) {
      final m = sentences.where((s) => s.id == id);
      if (m.isNotEmpty) items.add(m.first.text.trim());
    }
    items.removeWhere((e) => _stripWs(e).isEmpty);
    if (items.isEmpty) return;
    _startRun(items);
  }

  // 같은 문장들로 처음부터 다시 시작 (결과 화면의 '다시 시작')
  void _restartSame() {
    if (_queue.isEmpty) return;
    _startRun(List<String>.from(_queue));
  }

  void _startRun(List<String> items) {
    _timer?.cancel();
    _ticker.stop();
    setState(() {
      _sentenceResults.clear();
      _queue = items; _idx = 0;
      _started = true; _finished = false; _stoppedEarly = false; _savedToHome = false;
      _elapsedSec = 0; _sprintMs = 0;
      _accOja = 0; _accChum = 0; _accTal = 0; _accTyped = 0; _doneCount = 0;
      _advancing = false;
      _loadSentence();
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && _started && !_finished) setState(() => _elapsedSec++);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _inputFocus.requestFocus());
  }

  void _loadSentence() {
    final t = _queue[_idx].trim();
    final sb = StringBuffer();
    final map = <int>[];
    for (int k = 0; k < t.length; k++) {
      if (!_isWs(t[k])) { sb.write(t[k]); map.add(k); }
    }
    _target = t; _targetN = sb.toString(); _normToFull = map;
    _inputCtrl.clear(); _lastValue = '';
    _dpRows = []; _dpTyped = ''; _dpTarget = '';
    TypingTracker.sprint.syncLength(0);
    _ojaCnt = 0; _chumCnt = 0; _talCnt = 0; _totalTyped = 0;
    _states = List<String>.filled(_targetN.length, 'pending');
    _alignEnd = 0;
    _tp = null; _tpKey = '';
    _scrollTarget = 0;
    if (_sentenceScroll.hasClients) _sentenceScroll.jumpTo(0);
  }

  // ── 끝내기 / 중단 / 처음으로 ──
  Future<void> _finishRun({required bool stopped}) async {
    if (!_started || _finished) return;
    if (stopped) _recordSentenceResult(partial: true); // 중단: 친 만큼만 결과에 표시
    _timer?.cancel();
    _ticker.stop();
    _sprintMs = TypingTracker.sprint.activeMs;
    setState(() {
      _finished = true; _stoppedEarly = stopped; _savedToHome = false;
      _resultShownAt = DateTime.now();
    });
    final sess = await TypingTracker.sprint.finish(); // 순공시간(스프린트)으로 저장
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(sess == null ? '저장할 순공시간이 없어요' : '순공시간 ${formatTypingLong(sess.activeMs)} 저장됨 (스프린트)'),
        backgroundColor: kBlue, duration: const Duration(seconds: 2)));
      WidgetsBinding.instance.addPostFrameCallback((_) { if (mounted) _resultFocus.requestFocus(); });
    }
  }

  // 중단: 지금까지 친 만큼을 기준으로 결과를 내고 기록
  void _stop() => _finishRun(stopped: true);

  void _reset() {
    _timer?.cancel();
    _ticker.stop();
    if (TypingTracker.sprint.active) TypingTracker.sprint.finish();
    setState(() {
      _started = false; _finished = false; _stoppedEarly = false; _savedToHome = false;
      _inputCtrl.clear(); _lastValue = '';
      _elapsedSec = 0; _sprintMs = 0;
      _accOja = 0; _accChum = 0; _accTal = 0; _accTyped = 0; _doneCount = 0;
      _ojaCnt = 0; _chumCnt = 0; _talCnt = 0; _totalTyped = 0;
      _sentenceResults.clear();
    });
  }

  // ── 키 입력 ──
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyDownEvent) {
      final k = event.logicalKey;
      if (k == LogicalKeyboardKey.escape) { _stop(); return KeyEventResult.handled; }
      if (k == LogicalKeyboardKey.enter || k == LogicalKeyboardKey.numpadEnter) {
        _onEnter();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  // Enter: 지금 문장을 마치고 다음 문장으로 (마지막 문장이면 결과).
  // 한글 조합 중인 마지막 글자가 확정된 뒤에 읽도록 아주 잠깐 기다린다.
  void _onEnter() {
    if (!_started || _finished || _advancing) return;
    _advancing = true;
    Future.delayed(const Duration(milliseconds: 60), () {
      _advancing = false;
      if (!mounted || !_started || _finished) return;
      _commitSentence();
    });
  }

  void _commitSentence() {
    final typedN = _stripWs(_inputCtrl.text);
    if (typedN.isEmpty) return; // 아무것도 안 쳤으면 넘기지 않음
    final d = _diff(typedN, _targetN);
    final missing = _targetN.length - d.alignEnd; // 끝까지 못 친 글자는 탈자로 계산
    _recordSentenceResult(partial: false);
    _accOja += d.oja; _accChum += d.chum; _accTal += d.tal + missing;
    _accTyped += _countTasu(typedN);
    _doneCount++;
    _ojaCnt = 0; _chumCnt = 0; _talCnt = 0; _totalTyped = 0;
    if (_idx >= _queue.length - 1) {
      _finishRun(stopped: false);
    } else {
      setState(() { _idx++; _loadSentence(); });
      WidgetsBinding.instance.addPostFrameCallback((_) => _inputFocus.requestFocus());
    }
  }

  void _onInput(String value) {
    if (!_started || _finished) return;

    // 줄바꿈은 입력으로 치지 않음 (Enter는 문장 넘기기)
    if (value.contains('\n')) {
      value = value.replaceAll('\n', '');
      _inputCtrl.value = TextEditingValue(text: value, selection: TextSelection.collapsed(offset: value.length));
    }

    // 백스페이스 금지: 이전보다 짧아지면 원복
    if (value.length < _lastValue.length) {
      _inputCtrl.text = _lastValue;
      _inputCtrl.selection = TextSelection.collapsed(offset: _lastValue.length);
      return;
    }
    _lastValue = value;
    TypingTracker.sprint.onTextChanged(value); // 치는 동안은 순공시간

    // 공백·줄바꿈은 무시하고 비교
    final typedN = _stripWs(value);
    final d = _diff(typedN, _targetN);
    setState(() {
      _ojaCnt = d.oja; _chumCnt = d.chum; _talCnt = d.tal;
      _states = d.states; _alignEnd = d.alignEnd;
      _totalTyped = _countTasu(typedN);
    });
    _updateScrollTarget();

    // 마지막 문장을 한 글자도 안 틀리고 끝까지 치면 바로 결과 (시간이 정확히 멈춤)
    if (typedN == _targetN && _idx >= _queue.length - 1) _commitSentence();
  }

  // 목표 글자와 친 글자를 비교해 오자/첨자/탈자와 글자별 상태를 구한다.
  // - 아직 안 친 뒷부분은 탈자로 세지 않는다(중단해도 친 만큼만 기준).
  // - 긴 글을 위해 대각선 주변(±200)만 계산하고, 이미 계산한 앞부분 줄은 다시 쓴다
  //   (글자를 칠 때마다 새로 친 만큼만 계산).
  List<Int32List> _dpRows = [];
  String _dpTyped = '', _dpTarget = '';

  _SprintDiff _diff(String typed, String target) {
    final n = typed.length, m = target.length;
    const int w = 200, inf = 1 << 28, width = 2 * w + 1;
    if (_dpTarget != target) { _dpRows = []; _dpTyped = ''; _dpTarget = target; }
    // 앞에서부터 그대로인 글자 수만큼은 이전 계산을 재사용
    int keep = 0;
    final lim = math.min(_dpTyped.length, n);
    while (keep < lim && _dpTyped.codeUnitAt(keep) == typed.codeUnitAt(keep)) keep++;
    if (_dpRows.length > keep + 1) _dpRows.removeRange(keep + 1, _dpRows.length);

    int at(int i, int j) {
      if (i < 0 || j < 0 || j > m || i >= _dpRows.length) return inf;
      final c = j - (i - w);
      if (c < 0 || c >= width) return inf;
      return _dpRows[i][c];
    }
    for (int i = _dpRows.length; i <= n; i++) {
      final row = Int32List(width)..fillRange(0, width, inf);
      _dpRows.add(row);
      final jlo = math.max(0, i - w), jhi = math.min(m, i + w);
      for (int j = jlo; j <= jhi; j++) {
        int v;
        if (i == 0) { v = j; }
        else if (j == 0) { v = i; }
        else if (typed[i - 1] == target[j - 1]) { v = at(i - 1, j - 1); }
        else { v = 1 + math.min(at(i - 1, j - 1), math.min(at(i - 1, j), at(i, j - 1))); }
        row[j - (i - w)] = v;
      }
    }
    _dpTyped = typed;

    // 친 글자 수(n)에 해당하는 목표 위치(jEnd) 찾기
    int jEnd = 0, best = inf;
    for (int j = math.max(0, n - w); j <= math.min(m, n + w); j++) {
      final v = at(n, j);
      if (v <= best) { best = v; jEnd = j; } // 같은 점수면 더 뒤쪽(= 글자가 바뀐 오자 쪽)을 택함
    }
    final states = List<String>.filled(m, 'pending');
    int oja = 0, chum = 0, tal = 0;
    int i = n, j = jEnd;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && typed[i - 1] == target[j - 1]) { states[j - 1] = 'correct'; i--; j--; }
      else if (i > 0 && j > 0 && at(i, j) == at(i - 1, j - 1) + 1) { oja++; states[j - 1] = 'wrong'; i--; j--; }
      else if (i > 0 && at(i, j) == at(i - 1, j) + 1) { chum++; i--; }
      else if (j > 0) { tal++; j--; }
      else { break; }
    }
    return _SprintDiff(oja, chum, tal, jEnd, states);
  }

  // _diff가 계산해 둔 표(_dpRows)에서 값 읽기
  int _dpAt(int i, int j, int m) {
    const int w = 200, inf = 1 << 28, width = 2 * w + 1;
    if (i < 0 || j < 0 || j > m || i >= _dpRows.length) return inf;
    final c = j - (i - w);
    if (c < 0 || c >= width) return inf;
    return _dpRows[i][c];
  }

  // 결과 화면용: 글자별로 맞음/오자/첨자/탈자를 구한다 (셈하는 방식은 _diff와 같음)
  List<_SOp> _traceOps(String typed, String target, {required bool fillTail}) {
    final d = _diff(typed, target);
    final m = target.length;
    final rev = <_SOp>[];
    int i = typed.length, j = d.alignEnd;
    while (i > 0 || j > 0) {
      if (i > 0 && j > 0 && typed[i - 1] == target[j - 1]) {
        rev.add(_SOp('ok', typed[i - 1], target[j - 1])); i--; j--;
      } else if (i > 0 && j > 0 && _dpAt(i, j, m) == _dpAt(i - 1, j - 1, m) + 1) {
        rev.add(_SOp('oja', typed[i - 1], target[j - 1])); i--; j--;
      } else if (i > 0 && _dpAt(i, j, m) == _dpAt(i - 1, j, m) + 1) {
        rev.add(_SOp('chum', typed[i - 1], '')); i--;
      } else if (j > 0) {
        rev.add(_SOp('tal', '', target[j - 1])); j--;
      } else { break; }
    }
    final out = rev.reversed.toList();
    // 끝까지 못 친 뒷부분: 문장을 마친 경우만 탈자로 표시 (중단하면 친 만큼만)
    if (fillTail) {
      for (int k = d.alignEnd; k < m; k++) { out.add(_SOp('tal', '', target[k])); }
    }
    return out;
  }

  void _recordSentenceResult({required bool partial}) {
    final typedN = _stripWs(_inputCtrl.text);
    if (typedN.isEmpty) return;
    _sentenceResults.add(_SprintSentenceResult(
        _target, List<int>.from(_normToFull), _traceOps(typedN, _targetN, fillTail: !partial)));
  }

  // ── 긴 글 자동 스크롤: 치고 있는 자리를 문장 칸 가운데로 부드럽게 ──
  TextPainter _painter(double width) {
    final key = '${_target.hashCode}|${width.round()}';
    if (_tp == null || _tpKey != key) {
      _tp = TextPainter(text: TextSpan(text: _target, style: _baseStyle), textDirection: TextDirection.ltr)
        ..layout(maxWidth: width);
      _tpKey = key;
    }
    return _tp!;
  }

  int _lineCount(double width) {
    if (width <= 0 || _target.isEmpty) return 0;
    final key = '${_target.hashCode}|${width.round()}';
    return _lineCache.putIfAbsent(key, () {
      final tp = TextPainter(text: TextSpan(text: _target, style: _baseStyle), textDirection: TextDirection.ltr)
        ..layout(maxWidth: width);
      return tp.computeLineMetrics().length;
    });
  }

  void _updateScrollTarget() {
    if (!_sentenceScroll.hasClients || _boxInnerW <= 0) return;
    final tp = _painter(_boxInnerW);
    final full = _alignEnd >= _normToFull.length ? _target.length : _normToFull[_alignEnd];
    final off = tp.getOffsetForCaret(TextPosition(offset: full), Rect.zero);
    final lh = tp.preferredLineHeight;
    // 한 줄 안에서도 글자를 칠수록 조금씩 올라가도록 (끊기지 않고 이어지는 스크롤)
    final frac = (off.dx / _boxInnerW).clamp(0.0, 1.0);
    final y = kBoxPad + off.dy + lh * frac;
    final pos = _sentenceScroll.position;
    _scrollTarget = (y - pos.viewportDimension / 2).clamp(0.0, pos.maxScrollExtent).toDouble();
    if (!_ticker.isActive) { _lastElapsed = Duration.zero; _ticker.start(); }
  }

  // 목표 위치로 서서히 다가가다가 도착하면 멈춤 (타이핑을 멈추면 스크롤도 멈춤)
  void _onTick(Duration elapsed) {
    final dt = (elapsed - _lastElapsed).inMicroseconds / 1e6;
    _lastElapsed = elapsed;
    if (!_sentenceScroll.hasClients) { _ticker.stop(); return; }
    final pos = _sentenceScroll.position;
    final target = _scrollTarget.clamp(0.0, pos.maxScrollExtent).toDouble();
    final diff = target - pos.pixels;
    if (diff.abs() < 0.4) { _sentenceScroll.jumpTo(target); _ticker.stop(); return; }
    final k = 1 - math.exp(-9.0 * dt);
    _sentenceScroll.jumpTo((pos.pixels + diff * k).clamp(0.0, pos.maxScrollExtent).toDouble());
  }

  // ── 홈 기록으로 추가 ──
  String _fmtSec(int sec) => sec >= 60 ? '${sec ~/ 60}분 ${sec % 60}초' : '$sec초';

  Future<void> _saveToHome() async {
    if (_savedToHome || !_finished) return;
    _savedToHome = true;
    final now = DateTime.now();
    final key = _dateKeyFromMs(now.millisecondsSinceEpoch);
    final ex = Store.getRecord(key);
    final hm = '${now.hour.toString().padLeft(2, '0')}:${now.minute.toString().padLeft(2, '0')}';
    final line = '[스프린트 $hm] 문장 $_doneCount/${_queue.length} · ${_tasu.round()}타수 · '
        '정확도 ${_accuracy.toStringAsFixed(2)}% · 오자 $_sumOja 첨자 $_sumChum 탈자 $_sumTal · ${_fmtSec(_elapsedSec)}'
        '${_stoppedEarly ? ' (중단)' : ''}';
    final oldMemo = ex?.memo ?? '';
    await Store.saveRecord(StudyRecordModel(
      date: key,
      studyHours: ex?.studyHours, studyMinutes: ex?.studyMinutes,
      speechChars: ex?.speechChars, essayChars: ex?.essayChars,
      wpm: ex?.wpm ?? (_tasu > 0 ? _tasu.round() : null), // 이미 적어 둔 타수가 있으면 그대로 둠
      memo: oldMemo.isEmpty ? line : '$oldMemo\n$line'));
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
      content: Text('홈 기록에 추가했어요'), backgroundColor: kBlue, duration: Duration(seconds: 2)));
  }

  // 쿼티 기준 타수 계산 (자모 분해)
  int _countTasu(String text) {
    const choseong =  ['ㄱ','ㄲ','ㄴ','ㄷ','ㄸ','ㄹ','ㅁ','ㅂ','ㅃ','ㅅ','ㅆ','ㅇ','ㅈ','ㅉ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
    const jungseong = ['ㅏ','ㅐ','ㅑ','ㅒ','ㅓ','ㅔ','ㅕ','ㅖ','ㅗ','ㅘ','ㅙ','ㅚ','ㅛ','ㅜ','ㅝ','ㅞ','ㅟ','ㅠ','ㅡ','ㅢ','ㅣ'];
    const jongseong = ['','ㄱ','ㄲ','ㄳ','ㄴ','ㄵ','ㄶ','ㄷ','ㄹ','ㄺ','ㄻ','ㄼ','ㄽ','ㄾ','ㄿ','ㅀ','ㅁ','ㅂ','ㅄ','ㅅ','ㅆ','ㅇ','ㅈ','ㅊ','ㅋ','ㅌ','ㅍ','ㅎ'];
    // 겹받침/겹모음 타수 (쿼티 기준 2타)
    const double2 = {'ㄳ','ㄵ','ㄶ','ㄺ','ㄻ','ㄼ','ㄽ','ㄾ','ㄿ','ㅀ','ㅄ','ㄲ','ㄸ','ㅃ','ㅆ','ㅉ','ㅘ','ㅙ','ㅚ','ㅝ','ㅞ','ㅟ','ㅢ','ㅐ','ㅒ','ㅔ','ㅖ'};
    int tasu = 0;
    for (final ch in text.runes.map(String.fromCharCode)) {
      final code = ch.codeUnitAt(0);
      if (code >= 0xAC00 && code <= 0xD7A3) {
        final idx = code - 0xAC00;
        final jongIdx = idx % 28;
        final jungIdx = (idx ~/ 28) % 21;
        final choIdx = idx ~/ 28 ~/ 21;
        tasu += double2.contains(choseong[choIdx]) ? 2 : 1; // 초성
        tasu += double2.contains(jungseong[jungIdx]) ? 2 : 1; // 중성
        if (jongIdx > 0) tasu += double2.contains(jongseong[jongIdx]) ? 2 : 1; // 종성
      } else {
        tasu += 1; // 영문/숫자 등
      }
    }
    return tasu;
  }

  // 글자별 색상으로 문장 그리기 (같은 색 글자는 한 덩어리로 묶음)
  List<TextSpan> _buildColoredText() {
    final spans = <TextSpan>[];
    final buf = StringBuffer();
    Color? cur;
    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(text: buf.toString(), style: _baseStyle.copyWith(color: cur ?? Colors.grey.shade400)));
      buf.clear();
    }
    int normIdx = 0;
    for (int k = 0; k < _target.length; k++) {
      final ch = _target[k];
      if (_isWs(ch)) { buf.write(ch); continue; }
      final state = normIdx < _states.length ? _states[normIdx] : 'pending';
      Color color;
      if (state == 'correct') { color = Colors.green; }
      else if (state == 'wrong') { color = Colors.red; }
      else if (normIdx == _alignEnd) { color = kBlue; }
      else { color = Colors.grey.shade400; }
      if (cur != color) { flush(); cur = color; }
      buf.write(ch);
      normIdx++;
    }
    flush();
    return spans;
  }

  // 결과 화면: 내가 친 글에 탈자(빨강)·첨자(녹색)·오자(파랑, 아래에 원문을 빨간 작은 글씨로) 표시
  List<InlineSpan> _diffSpans(_SprintSentenceResult r) {
    const base = TextStyle(fontSize: 18, fontWeight: FontWeight.w700, height: 1.5);
    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    Color bufColor = Colors.black87;
    void flush() {
      if (buf.isEmpty) return;
      spans.add(TextSpan(text: buf.toString(), style: base.copyWith(color: bufColor)));
      buf.clear();
    }
    void put(String t, Color c) {
      if (bufColor != c) { flush(); bufColor = c; }
      buf.write(t);
    }
    int tIdx = 0, lastFull = -1;
    // 원문 글자 하나를 소비하면서, 그 앞의 공백·줄바꿈을 그대로 넣는다
    void consume({required bool withWs}) {
      if (tIdx < r.normToFull.length) {
        final full = r.normToFull[tIdx];
        if (withWs && full - lastFull > 1) buf.write(r.target.substring(lastFull + 1, full));
        lastFull = full;
      }
      tIdx++;
    }
    int k = 0;
    while (k < r.ops.length) {
      final op = r.ops[k];
      if (op.kind == 'ok') { consume(withWs: true); put(op.target, Colors.black87); k++; }
      else if (op.kind == 'tal') { consume(withWs: true); put(op.target, _kTalColor); k++; }
      else if (op.kind == 'chum') { put(op.typed, _kChumColor); k++; }
      else {
        // 오자: 이어진 글자는 한 덩어리로 묶어 아래에 원문을 괄호로 표시
        final typedB = StringBuffer(), origB = StringBuffer();
        bool first = true;
        while (k < r.ops.length && r.ops[k].kind == 'oja') {
          consume(withWs: first); first = false;
          typedB.write(r.ops[k].typed); origB.write(r.ops[k].target); k++;
        }
        flush();
        spans.add(WidgetSpan(
          alignment: PlaceholderAlignment.baseline, baseline: TextBaseline.alphabetic,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(typedB.toString(), style: base.copyWith(color: _kOjaColor)),
            Text('($origB)', style: const TextStyle(fontSize: 10, height: 1.1,
                fontWeight: FontWeight.w700, color: _kTalColor)),
          ])));
      }
    }
    flush();
    return spans;
  }

  Widget _buildDiffView() {
    final multi = _sentenceResults.length > 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (int i = 0; i < _sentenceResults.length; i++) ...[
        if (i > 0) const SizedBox(height: 10),
        Container(width: double.infinity, padding: const EdgeInsets.all(kBoxPad),
          decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (multi) Padding(padding: const EdgeInsets.only(bottom: 6),
              child: Text('문장 ${i + 1}',
                  style: const TextStyle(fontSize: 11, color: Colors.grey, fontWeight: FontWeight.w700))),
            Text.rich(TextSpan(children: _diffSpans(_sentenceResults[i]))),
          ])),
      ],
    ]);
  }

  // ── 화면 ──
  @override
  Widget build(BuildContext context) {
    final sentences = Store.getSentences();
    return Scaffold(backgroundColor: Colors.white,
      body: SafeArea(child: LayoutBuilder(builder: (context, cons) {
        if (!_started) {
          // 화면이 충분히 크면: 문장 목록이 남는 공간을 채우고 시작 버튼은 맨 아래에 고정.
          // 아주 작으면: 목록을 작게 두고 화면 전체가 스크롤되도록.
          final fill = cons.maxHeight >= 470;
          if (fill) {
            return Padding(padding: const EdgeInsets.all(20), child: _buildSetup(sentences, fill: true));
          }
          return SingleChildScrollView(padding: const EdgeInsets.all(20), child: _buildSetup(sentences, fill: false));
        }
        // 문장 칸 안쪽 너비 (바깥 여백 20×2, 칸 안쪽 여백 16×2)
        final innerW = cons.maxWidth - 40 - kBoxPad * 2;
        _boxInnerW = innerW;
        final bool long = !_finished && _lineCount(innerW) > kLongLines;
        if (long) {
          // 긴 글: 위 3분의 2는 문장, 아래 3분의 1은 내 타이핑 창 (화면 크기가 바뀌어도 같은 비율)
          return Padding(padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(children: [
              Expanded(flex: 2, child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _buildHeader(),
                const SizedBox(height: 10),
                _buildStats(),
                const SizedBox(height: 10),
                Expanded(child: Container(width: double.infinity,
                  decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12)),
                  child: SingleChildScrollView(controller: _sentenceScroll,
                    padding: const EdgeInsets.all(kBoxPad),
                    child: RichText(text: TextSpan(children: _buildColoredText()))))),
              ])),
              const SizedBox(height: 10),
              Expanded(flex: 1, child: _buildInput(expand: true)),
            ]));
        }
        return SingleChildScrollView(padding: const EdgeInsets.all(20),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _buildHeader(),
            const SizedBox(height: 12),
            _buildStats(),
            const SizedBox(height: 16),
            if (_finished && _sentenceResults.isNotEmpty)
              _buildDiffView()
            else
              Container(width: double.infinity, padding: const EdgeInsets.all(kBoxPad),
                decoration: BoxDecoration(color: const Color(0xFFF8F8F8), borderRadius: BorderRadius.circular(12)),
                child: RichText(text: TextSpan(children: _buildColoredText()))),
            const SizedBox(height: 12),
            if (!_finished) _buildInput(expand: false) else _buildResult(),
          ]));
      })));
  }

  Widget _buildHeader() => Row(children: [
    const Text('스프린트', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
    const Spacer(),
    if (!_finished) ...[
      GestureDetector(onTap: _stop,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(color: const Color(0xFFFFEEEE), borderRadius: BorderRadius.circular(20)),
          child: const Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(Icons.stop_rounded, size: 16, color: Colors.red),
            SizedBox(width: 4),
            Text('중단 (Esc)', style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w700)),
          ]))),
      const SizedBox(width: 8),
    ],
    GestureDetector(onTap: _reset, child: _iconToolBtn(Icons.refresh_rounded)),
  ]);

  Widget _buildStats() {
    final last = _idx >= _queue.length - 1;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Wrap(spacing: 8, runSpacing: 6, children: [
        _statChip(Icons.timer_rounded, '$_elapsedSec초', kBlue),
        _statChip(Icons.speed_rounded, '${_tasu.round()} 타수', kPurple),
        _statChip(Icons.check_circle_rounded, '${_accuracy.toStringAsFixed(2)}%', Colors.teal.shade700),
        // 타율(정확도) 오른쪽: 이번 스프린트에서 쌓인 순공시간
        AnimatedBuilder(animation: TypingTracker.sprint, builder: (context, _) =>
          _statChip(Icons.hourglass_bottom_rounded,
              '순공 ${formatTypingClock(_finished ? _sprintMs : TypingTracker.sprint.activeMs)}', kBlueDark)),
      ]),
      const SizedBox(height: 6),
      Wrap(spacing: 8, runSpacing: 6, children: [
        _statChip(Icons.swap_horiz_rounded, '오자 $_sumOja', _kOjaColor),
        _statChip(Icons.add_rounded, '첨자 $_sumChum', _kChumColor),
        _statChip(Icons.remove_rounded, '탈자 $_sumTal', _kTalColor),
      ]),
      if (!_finished) Padding(padding: const EdgeInsets.only(top: 8),
        child: Text('문장 ${_idx + 1} / ${_queue.length}  ·  Enter: ${last ? '결과 보기' : '다음 문장'}  ·  Esc: 중단',
            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600))),
    ]);
  }

  Widget _buildInput({required bool expand}) => Focus(
    onKeyEvent: _onKey,
    child: TextField(
      controller: _inputCtrl,
      focusNode: _inputFocus,
      onChanged: _onInput,
      expands: expand,
      minLines: expand ? null : 2,
      maxLines: null,
      textAlignVertical: expand ? TextAlignVertical.top : null,
      decoration: InputDecoration(
        hintText: '여기에 타이핑하세요...',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kBlue))),
      style: const TextStyle(fontSize: 16)));

  Widget _buildResult() => Focus(
    focusNode: _resultFocus,
    autofocus: true,
    onKeyEvent: (node, event) {
      if (event is KeyDownEvent &&
          (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
        // 결과 화면이 막 떴을 때 같은 Enter가 또 들어와도 바로 저장되지 않게 잠깐 무시
        final shown = _resultShownAt;
        if (shown != null && DateTime.now().difference(shown).inMilliseconds < 600) return KeyEventResult.handled;
        _saveToHome();
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    },
    child: Container(width: double.infinity, padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
          color: _stoppedEarly ? const Color(0xFFFFF4E5) : const Color(0xFFE8F5E9),
          borderRadius: BorderRadius.circular(16)),
      child: Column(children: [
        Icon(_stoppedEarly ? Icons.pause_circle_filled_rounded : Icons.emoji_events_rounded,
            color: _stoppedEarly ? Colors.orange : Colors.green, size: 48),
        const SizedBox(height: 8),
        Text(_stoppedEarly ? '중단 (여기까지 기록)' : '완료!',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900,
                color: _stoppedEarly ? Colors.orange : Colors.green)),
        const SizedBox(height: 4),
        Text('문장 $_doneCount / ${_queue.length}',
            style: const TextStyle(fontSize: 12, color: Colors.grey, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _resultItem('시간', '$_elapsedSec초'),
          _resultItem('타수', '${_tasu.round()}'),
          _resultItem('정확도', '${_accuracy.toStringAsFixed(2)}%'),
        ]),
        const SizedBox(height: 8),
        Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
          _resultItem('오자', '$_sumOja개', color: _kOjaColor),
          _resultItem('첨자', '$_sumChum개', color: _kChumColor),
          _resultItem('탈자', '$_sumTal개', color: _kTalColor),
        ]),
        const SizedBox(height: 8),
        _resultItem('순공시간', formatTypingLong(_sprintMs)),
        const SizedBox(height: 16),
        Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
          ElevatedButton.icon(
            onPressed: _savedToHome ? null : _saveToHome,
            icon: Icon(_savedToHome ? Icons.check_rounded : Icons.playlist_add_rounded),
            label: Text(_savedToHome ? '홈 기록에 추가됨' : '홈 기록에 추가 (Enter)'),
            style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
          ElevatedButton.icon(
            onPressed: _restartSame,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('다시 시작'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.green, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
          ElevatedButton.icon(
            onPressed: _reset,
            icon: const Icon(Icons.home_rounded),
            label: const Text('처음 화면'),
            style: ElevatedButton.styleFrom(backgroundColor: kBlueDark, foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))),
        ]),
      ])));

  Widget _buildSetup(List<SavedSentenceModel> sentences, {required bool fill}) {
    final ready = _readyCount(sentences);
    final list = ListView.builder(itemCount: sentences.length,
            itemBuilder: (_, i) {
              final s = sentences[i];
              final order = _selectedIds.indexOf(s.id);
              final isSel = order >= 0;
              return GestureDetector(
                onTap: () => setState(() {
                  if (isSel) _selectedIds.remove(s.id); else _selectedIds.add(s.id);
                }),
                child: Container(margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSel ? kBlueLight : const Color(0xFFF8F8F8),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: isSel ? kBlue : Colors.transparent)),
                  child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Container(width: 22, height: 22, margin: const EdgeInsets.only(right: 10, top: 1),
                      decoration: BoxDecoration(shape: BoxShape.circle,
                          color: isSel ? kBlue : Colors.transparent,
                          border: Border.all(color: isSel ? kBlue : Colors.grey.shade400, width: 1.5)),
                      child: Center(child: isSel
                          ? Text('${order + 1}', style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.w800))
                          : null)),
                    // 문장당 기본 최대 9줄, 10줄 이상이면 '더보기'
                    Expanded(child: _ClampedText(text: s.text, maxLines: 9,
                        style: const TextStyle(fontSize: 13, height: 1.5))),
                  ])));
            });
    final startBtn = SizedBox(width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: ready == 0 ? null : () => _begin(sentences),
          icon: const Icon(Icons.play_arrow_rounded),
          label: Text(ready > 1 ? '시작 ($ready문장)' : '시작', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
          style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)))));
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('스프린트', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
      const SizedBox(height: 16),
      // 문장 직접 입력 (입력하면 맨 앞 문장으로 들어감)
      _lbl('연습할 문장'),
      TextField(controller: _textCtrl, maxLines: 4, onChanged: (_) => setState(() {}),
        decoration: InputDecoration(
          hintText: '연습할 문장을 입력하거나 아래에서 골라 주세요...',
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: kBlue)))),
      const SizedBox(height: 12),

      // 저장된 문장에서 여러 개 선택 (누른 순서대로 연습)
      if (sentences.isNotEmpty) ...[
        Row(children: [
          const Expanded(child: Text('저장된 문장에서 선택 (여러 개 가능 · 누른 순서대로)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.grey))),
          if (_selectedIds.isNotEmpty)
            GestureDetector(onTap: () => setState(() => _selectedIds.clear()),
              child: const Text('선택 해제', style: TextStyle(fontSize: 12, color: Colors.grey,
                  decoration: TextDecoration.underline))),
        ]),
        const SizedBox(height: 6),
        // 큰 화면: 남는 공간을 목록이 채우고(넘치면 목록 안에서 스크롤), 시작 버튼은 맨 아래 고정
        // 작은 화면: 목록은 작게, 화면 전체가 스크롤
        if (fill) Expanded(child: list) else SizedBox(height: 160, child: list),
        const SizedBox(height: 12),
      ] else if (fill) const Spacer(),

      startBtn,
    ]);
  }

  Widget _statChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(color: color.withOpacity(0.1), borderRadius: BorderRadius.circular(20)),
    child: Row(mainAxisSize: MainAxisSize.min, children: [
      Icon(icon, size: 14, color: color),
      const SizedBox(width: 4),
      Text(label, style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w700)),
    ]));

  Widget _resultItem(String label, String value, {Color color = kBlueDark}) => Column(children: [
    Text(value, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900, color: color)),
    Text(label, style: const TextStyle(fontSize: 12, color: Colors.grey)),
  ]);
}

// 스프린트 결과 색: 탈자 빨강 · 첨자 녹색 · 오자 파랑
const Color _kTalColor = Color(0xFFE53935);
const Color _kChumColor = Color(0xFF2E9E4F);
const Color _kOjaColor = Color(0xFF1E6BFF);

bool _isWs(String ch) => ch.trim().isEmpty;
final RegExp _wsRe = RegExp(r'\s');
String _stripWs(String s) => s.replaceAll(_wsRe, '');

// ── 퀴즈 화면 ────────────────────────────────────────────────────────
class QuizScreen extends StatefulWidget {
  final List<AbbreviationModel>? presetItems;
  const QuizScreen({super.key, this.presetItems});
  @override State<QuizScreen> createState() => _QuizScreenState();
}

class _QuizScreenState extends State<QuizScreen> {
  // 공부방 탭 (연습장 / 약어테스트 / 스프린트)
  bool _showTyping = false;
  bool _showPad = false; // 연습장 (순공시간 측정)

  // 설정
  String _mode = 'abbr'; // 'abbr' or 'sentence'
  final Set<String> _filterGroupIds = {};
  int _quizCount = 10;
  final TextEditingController _quizCountCtrl = TextEditingController();

  // 출제 방식 (약어 테스트 전용): 'group' 그룹별 / 'review' 복습 / 'old' 묵은 약어 / 'mix' 혼합
  String _pick = 'group';
  int _reviewDays = 30;      // 복습 기간 (0 = 전체)
  int _reviewMinWrong = 1;   // 기간 내 최소 오답 횟수
  int _graduateStreak = 3;   // 연속 정답 N회면 복습에서 제외 (0 = 제외 안 함)
  int _oldDays = 0;          // 묵은 약어 기준 일수 (0 = 오래된 순)
  bool _includeNever = true; // 한 번도 안 본 약어 포함 여부

  // 퀴즈 진행
  List<dynamic> _questions = [];
  int _currentIdx = 0;
  bool _started = false;
  bool _finished = false;
  
  // 채점
  final _answerCtrl = TextEditingController();
  List<Map<String, dynamic>> _results = []; // {question, userAnswer, correct, wrong}
  
  // TTS
  bool _ttsPlayed = false;
  final _inputFocusNode = FocusNode();
  final _keyboardFocusNode = FocusNode();

  List<AbbreviationModel>? _presetOverride; // 리마인드에서 넘어온 선택 약어 (한 번만 사용)

  // TTS 오류: 이번 테스트에서 표시한 문제들 / 마지막 '보면서 테스트' 라운드 여부
  List<dynamic> _ttsFlagged = [];
  bool _seeRound = false;

  @override
  void initState() {
    super.initState();
    kQuizPreset.addListener(_onPresetRequest);
    if (widget.presetItems != null && widget.presetItems!.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _start());
    }
  }

  void _onPresetRequest() {
    final items = kQuizPreset.value;
    if (items == null || items.isEmpty) return;
    kQuizPreset.value = null;
    if (!mounted) return;
    _presetOverride = items;
    _showTyping = false;
    _showPad = false;
    TtsController.instance.stop();
    _start();
  }

  @override
  void dispose() {
    kQuizPreset.removeListener(_onPresetRequest);
    _answerCtrl.dispose();
    _quizCountCtrl.dispose();
    _inputFocusNode.dispose();
    _keyboardFocusNode.dispose();
    TtsController.instance.stop();
    super.dispose();
  }

  // 그룹 필터를 적용한 약어 목록
  List<AbbreviationModel> _groupFiltered() {
    final all = Store.getAbbreviations();
    if (_filterGroupIds.isEmpty) return all;
    return all.where((a) => a.groupIds.any((id) => _filterGroupIds.contains(id))).toList();
  }

  // 복습 후보: 기간 내 틀린 약어를 오답 많은 순(동률은 무작위)으로
  List<AbbreviationModel> _reviewList(List<AbbreviationModel> base) {
    final counts = Store.getRecentWrongCounts(days: _reviewDays == 0 ? 36500 : _reviewDays);
    final rnd = math.Random();
    final scored = <MapEntry<AbbreviationModel, double>>[];
    for (final a in base) {
      final key = a.quizText;
      final c = counts[key] ?? 0;
      if (c < _reviewMinWrong) continue;
      if (_graduateStreak > 0 && Store.getStreak(key) >= _graduateStreak) continue;
      scored.add(MapEntry(a, c + rnd.nextDouble()));
    }
    scored.sort((x, y) => y.value.compareTo(x.value));
    return scored.map((e) => e.key).toList();
  }

  // 묵은 약어 후보: 한 번도 안 본 약어(무작위) → 마지막 테스트가 오래된 순
  List<AbbreviationModel> _oldList(List<AbbreviationModel> base) {
    final now = DateTime.now();
    final never = <AbbreviationModel>[];
    final seen = <MapEntry<AbbreviationModel, DateTime>>[];
    for (final a in base) {
      final t = Store.getLastSeen(a.quizText);
      if (t == null) { never.add(a); continue; }
      if (_oldDays > 0 && now.difference(t).inDays < _oldDays) continue;
      seen.add(MapEntry(a, t));
    }
    seen.sort((x, y) => x.value.compareTo(y.value));
    never.shuffle();
    return [
      if (_includeNever) ...never,
      ...seen.map((e) => e.key),
    ];
  }

  // 출제 방식별 후보를 우선순위 순으로 반환 (혼합은 복습 절반 + 묵은 약어, 부족하면 서로 채움)
  List<AbbreviationModel> _smartPool() {
    final base = _groupFiltered();
    if (_pick == 'review') return _reviewList(base);
    if (_pick == 'old') return _oldList(base);
    final review = _reviewList(base);
    final old = _oldList(base);
    final picked = <AbbreviationModel>[];
    final ids = <String>{};
    final half = (_quizCount / 2).ceil();
    for (final a in review.take(half)) { if (ids.add(a.id)) picked.add(a); }
    for (final a in old) { if (ids.add(a.id)) picked.add(a); }
    for (final a in review) { if (ids.add(a.id)) picked.add(a); }
    return picked;
  }

  // 현재 모드/그룹 기준으로 중복 없는 전체 풀 개수 반환
  int _totalPoolCount() {
    if (_mode == 'abbr' && _pick != 'group') return _smartPool().length;
    final sentences = Store.getSentences();
    final Set<String> ids = {};
    if (_mode == 'abbr' || _mode == 'both') {
      for (final a in _groupFiltered()) ids.add(a.id);
    }
    if (_mode == 'sentence' || _mode == 'both') {
      for (final s in sentences) ids.add(s.id);
    }
    return ids.length;
  }

  List<dynamic> _buildQuestions() {
    final preset = _presetOverride ?? widget.presetItems;
    if (preset != null && preset.isNotEmpty) {
      final list = List<dynamic>.from(preset);
      _presetOverride = null; // 한 번 쓰고 비워서, 이후 일반 테스트에 영향이 없게 함
      list.shuffle();
      return list;
    }
    // 복습 / 묵은 약어 / 혼합 출제
    if (_mode == 'abbr' && _pick != 'group') {
      final smart = _smartPool();
      if (smart.isEmpty) return [];
      final n = _quizCount.clamp(1, smart.length);
      return List<dynamic>.from(smart.take(n))..shuffle();
    }
    final sentences = Store.getSentences();
    List<dynamic> pool = [];
    if (_mode == 'abbr' || _mode == 'both') {
      pool.addAll(_groupFiltered());
    }
    if (_mode == 'sentence' || _mode == 'both') {
      pool.addAll(sentences);
    }
    pool.shuffle();
    // 오답 가중치: 최근 7일 많이 틀린 약어는 풀에 중복 추가
    final wrongCounts = Store.getRecentWrongCounts(days: 7);
    if (wrongCounts.isNotEmpty) {
      final extras = <dynamic>[];
      for (final item in pool) {
        final text = _itemText(item);
        final cnt = wrongCounts[text] ?? 0;
        if (cnt >= 3) extras.add(item);       // 3번 이상 틀림 → 1개 추가
        if (cnt >= 6) extras.add(item);       // 6번 이상 틀림 → 1개 더 추가
      }
      pool.addAll(extras);
      pool.shuffle();
    }
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
      _ttsFlagged = [];
      _seeRound = false;
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
    final text = _itemText(q);
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
    final correctText = _itemText(q);
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

    // 이번 테스트에서 TTS 오류로 표시한 약어가 (중복 출제 등으로) 텍스트를 보며 이미 채점됐다면
    // 마지막 '보고 테스트' 라운드에서 다시 묻지 않는다
    if (!_seeRound) {
      _ttsFlagged.removeWhere((f) => _itemText(f) == correctText);
    }

    Store.logQuizSeen(correctText); // 마지막 테스트 시각 기록
    if (wrongWords.isNotEmpty) {
      Store.logQuizWrong(correctText);
      Store.resetStreak(correctText);
    } else {
      Store.logQuizCorrect(correctText);
    }

    _goNext();
  }

  String _itemText(dynamic q) => q is AbbreviationModel
      ? q.quizText
      : (q as SavedSentenceModel).text;

  // TTS 오류: 이 문제를 목록에 저장하고 채점·오답 기록 없이 다음 문제로
  void _ttsErrorSkip() {
    if (_seeRound || _currentIdx >= _questions.length) return;
    final q = _questions[_currentIdx];
    Store.addTtsError(_itemText(q));
    if (!_ttsFlagged.contains(q)) _ttsFlagged.add(q);
    TtsController.instance.stop();
    _goNext();
  }

  // 현재 문제 소리 재생 + 입력창 포커스
  void _presentQuestion() {
    _playCurrentTts();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputFocusNode.requestFocus();
    });
  }

  // 다음 문제로 / 마지막이면 TTS 오류 약어 보면서 테스트 → 결과
  void _goNext() {
    if (_currentIdx < _questions.length - 1) {
      setState(() {
        _currentIdx++;
        _ttsPlayed = false;
        _answerCtrl.clear();
      });
      _presentQuestion();
      return;
    }
    if (!_seeRound && _ttsFlagged.isNotEmpty) {
      final items = List<dynamic>.from(_ttsFlagged)..shuffle();
      setState(() {
        _seeRound = true;
        _questions = items;
        _currentIdx = 0;
        _ttsPlayed = false;
        _answerCtrl.clear();
      });
      _presentQuestion();
      return;
    }
    TtsController.instance.stop();
    // 테스트 완료 시 오늘 결과 기록 (TTS 오류로 건너뛴 문제는 보면서 테스트에서 채점됨)
    final correct = _results.where((r) => r['correct'] as bool).length;
    if (_results.isNotEmpty) Store.logTodayQuizResult(correct, _results.length);
    setState(() => _finished = true);
  }

  void _retryWrong() {
    final wrongItems = _results.where((r) => !(r['correct'] as bool)).map((r) => r['item']).toList();
    if (wrongItems.isEmpty) return;
    setState(() {
      _questions = wrongItems..shuffle();
      _ttsFlagged = [];
      _seeRound = false;
      _currentIdx = 0;
      _results = [];
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
                await Store.saveAbbreviation(item.copyWith(groupIds: {...item.groupIds, gid}.toList()));
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
        .map((a) => a.quizText)
        .join(', ');
    final prompt = '다음 약어들을 포함한 자연스러운 한국어 문장을 공백 제외 30자 내외로 각 단어마다 5개씩 만들어줘: $words';
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
          return Column(children: [
            // 상단 탭 토글 (연습장 / 약어 테스트 / 스프린트)
            if (!_started || _showTyping || _showPad)
              Container(color: Colors.white,
                padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
                child: Row(children: [
                  Expanded(child: _tabBtn('연습장', _showPad,
                      () => setState(() { _showPad = true; _showTyping = false; }))),
                  const SizedBox(width: 8),
                  Expanded(child: _tabBtn('약어 테스트', !_showPad && !_showTyping,
                      () => setState(() { _showPad = false; _showTyping = false; }))),
                  const SizedBox(width: 8),
                  Expanded(child: _tabBtn('스프린트', _showTyping,
                      () => setState(() { _showPad = false; _showTyping = true; }))),
                ])),
            // 하단 콘텐츠
            Expanded(child: _showPad
              ? const _PracticePad(margin: EdgeInsets.fromLTRB(16, 4, 16, 12))
              : _showTyping
                ? const TypingPracticeScreen()
                : _started ? (_finished ? _buildResult() : _buildQuiz())
                           : _buildSetup()),
          ]);
        }));
  }

  // TTS 오류 약어 목록 (검색 + 체크박스로 선택해서 해제)
  void _showTtsErrorList() {
    final searchCtrl = TextEditingController();
    final selected = <String>{};
    String query = '';
    showModalBottomSheet(
      context: context, isScrollControlled: true, backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) {
        final all = Store.getTtsErrors();
        final q = query.trim();
        final list = q.isEmpty ? all : all.where((t) => t.contains(q)).toList();
        final allChecked = list.isNotEmpty && list.every(selected.contains);
        return SafeArea(child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.75),
            child: Padding(padding: const EdgeInsets.all(20), child: Column(
              mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('TTS 오류 약어 (${all.length}개)',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 4),
              const Text('체크하고 해제하면 다음 테스트부터 텍스트 없이 소리로만 출제돼요.',
                  style: TextStyle(fontSize: 11, color: Colors.grey)),
              const SizedBox(height: 12),
              TextField(
                controller: searchCtrl,
                onChanged: (v) => setS(() => query = v),
                decoration: InputDecoration(
                  hintText: '약어 검색',
                  prefixIcon: const Icon(Icons.search, size: 18),
                  suffixIcon: query.isEmpty ? null : IconButton(
                    icon: const Icon(Icons.close, size: 16),
                    onPressed: () { searchCtrl.clear(); setS(() => query = ''); }),
                  isDense: true,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: Color(0xFFE0E0E0))),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                      borderSide: const BorderSide(color: kBlue)))),
              const SizedBox(height: 8),
              if (list.isEmpty)
                Padding(padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: Text(all.isEmpty ? '표시한 약어가 없어요.' : '검색 결과가 없어요.',
                      style: const TextStyle(color: Colors.grey))))
              else ...[
                InkWell(
                  onTap: () => setS(() {
                    if (allChecked) { selected.removeAll(list); } else { selected.addAll(list); }
                  }),
                  child: Row(children: [
                    Checkbox(
                      value: allChecked, activeColor: kBlue,
                      visualDensity: VisualDensity.compact,
                      onChanged: (v) => setS(() {
                        if (allChecked) { selected.removeAll(list); } else { selected.addAll(list); }
                      })),
                    Text(q.isEmpty ? '전체 선택' : '검색 결과 전체 선택 (${list.length}개)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.grey)),
                  ])),
                const Divider(height: 1),
                Flexible(child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: list.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final t = list[i];
                    final on = selected.contains(t);
                    return InkWell(
                      onTap: () => setS(() { if (on) { selected.remove(t); } else { selected.add(t); } }),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: Row(children: [
                          Checkbox(
                            value: on, activeColor: kBlue,
                            visualDensity: VisualDensity.compact,
                            onChanged: (v) => setS(() { if (on) { selected.remove(t); } else { selected.add(t); } })),
                          Expanded(child: Text(t,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600))),
                        ])));
                  })),
              ],
              const SizedBox(height: 12),
              SizedBox(width: double.infinity, child: ElevatedButton(
                onPressed: selected.isEmpty ? null : () async {
                  for (final t in selected.toList()) {
                    await Store.removeTtsError(t);
                  }
                  selected.clear();
                  setS(() {});
                  if (mounted) setState(() {});
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red, foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                child: Text(selected.isEmpty ? '해제할 약어를 체크하세요' : '선택한 ${selected.length}개 해제',
                    style: const TextStyle(fontWeight: FontWeight.w700)))),
            ])))));
      }));
  }

  // 설정 화면용 작은 선택 칩 줄
  Widget _intChips(String label, List<MapEntry<String, int>> opts, int cur, void Function(int) onSel) =>
    Padding(padding: const EdgeInsets.only(bottom: 14), child: Column(
      crossAxisAlignment: CrossAxisAlignment.start, children: [
      _lbl(label),
      Wrap(spacing: 8, runSpacing: 8, children: opts.map((o) {
        final sel = o.value == cur;
        return GestureDetector(
          onTap: () => setState(() => onSel(o.value)),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: sel ? kBlue : kBlueLight,
              borderRadius: BorderRadius.circular(20)),
            child: Text(o.key, style: TextStyle(
                color: sel ? Colors.white : kBlue,
                fontWeight: FontWeight.w700, fontSize: 12))));
      }).toList()),
    ]));

  Widget _tabBtn(String label, bool selected, VoidCallback onTap) => GestureDetector(
    onTap: onTap,
    child: Container(padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: selected ? kBlue : kBlueLight,
        borderRadius: BorderRadius.circular(12)),
      child: Center(child: Text(label,
          style: TextStyle(color: selected ? Colors.white : kBlue,
              fontWeight: FontWeight.w700, fontSize: 14)))));

  // ── 설정 화면 ──
Widget _buildSetup() {
    final groups = Store.getGroups();
    return Scaffold(backgroundColor: Colors.white,
      body: SafeArea(child: SingleChildScrollView(padding: const EdgeInsets.all(20), child: Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('테스트 설정', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900)),
        const SizedBox(height: 24),

        // 문제 수 + TTS 속도 (붙여서 나란히 배치)
        Wrap(spacing: 20, runSpacing: 16, children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('문제 수'),
            const SizedBox(height: 8),
            Row(mainAxisSize: MainAxisSize.min, children: [
              GestureDetector(
                onTap: () => setState(() {
                  if (_quizCount <= 1) {
                    _quizCount = _totalPoolCount();
                  } else {
                    _quizCount = _quizCount - 1;
                  }
                }),
                child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.remove_rounded, color: kBlue, size: 20))),
              const SizedBox(width: 8),
              SizedBox(width: 60, child: Focus(
                onKeyEvent: (node, event) {
                  if (event is KeyDownEvent &&
                      (event.logicalKey == LogicalKeyboardKey.enter ||
                       event.logicalKey == LogicalKeyboardKey.numpadEnter)) {
                    final n = int.tryParse(_quizCountCtrl.text);
                    if (n != null && n == 0) setState(() => _quizCount = _totalPoolCount());
                    else if (n != null && n > 0) setState(() => _quizCount = n);
                    _quizCountCtrl.clear();
                    return KeyEventResult.handled;
                  }
                  return KeyEventResult.ignored;
                },
                child: TextField(
                  controller: _quizCountCtrl,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.w900, color: kBlueDark, fontSize: 16),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '$_quizCount',
                    hintStyle: const TextStyle(fontWeight: FontWeight.w900, color: kBlueDark, fontSize: 16),
                    contentPadding: const EdgeInsets.symmetric(vertical: 8),
                    filled: true, fillColor: kBlueLight,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none))))),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () => setState(() => _quizCount = (_quizCount + 1).clamp(1, 9999)),
                child: Container(width: 36, height: 36,
                  decoration: BoxDecoration(color: kBlueLight, borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.add_rounded, color: kBlue, size: 20))),
            ]),
          ]),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _lbl('TTS 속도'),
            const SizedBox(height: 8),
            _TtsSpeedStepper(onChanged: () => setState(() {})),
          ]),
        ]),
        const SizedBox(height: 32),
        // 모드 선택
        _lbl('테스트 유형'),
        Row(children: [
          _ModeChip(label: '약어', value: 'abbr', selected: _mode, onTap: (v) => setState(() { _mode = v; _filterGroupIds.clear(); })),
          const SizedBox(width: 8),
          _ModeChip(label: '문장', value: 'sentence', selected: _mode, onTap: (v) => setState(() { _mode = v; _filterGroupIds.clear(); })),
          const SizedBox(width: 8),
          _ModeChip(label: '둘 다', value: 'both', selected: _mode, onTap: (v) => setState(() { _mode = v; _filterGroupIds.clear(); })),
        ]),
        const SizedBox(height: 20),

        // 출제 방식 (약어 테스트 전용)
        if (_mode == 'abbr') ...[
          _lbl('출제 방식'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            _ModeChip(label: '그룹별', value: 'group', selected: _pick, onTap: (v) => setState(() => _pick = v)),
            _ModeChip(label: '복습(틀린 약어)', value: 'review', selected: _pick, onTap: (v) => setState(() => _pick = v)),
            _ModeChip(label: '묵은 약어', value: 'old', selected: _pick, onTap: (v) => setState(() => _pick = v)),
            _ModeChip(label: '혼합', value: 'mix', selected: _pick, onTap: (v) => setState(() => _pick = v)),
          ]),
          const SizedBox(height: 16),
          if (_pick == 'review' || _pick == 'mix') ...[
            _intChips('복습 기간', const [MapEntry('최근 7일', 7), MapEntry('최근 30일', 30), MapEntry('전체', 0)],
                _reviewDays, (v) => _reviewDays = v),
            _intChips('최소 오답 횟수', const [MapEntry('1회 이상', 1), MapEntry('2회 이상', 2), MapEntry('3회 이상', 3)],
                _reviewMinWrong, (v) => _reviewMinWrong = v),
            _intChips('복습에서 제외할 기준 (연속 정답)',
                const [MapEntry('마지막에 틀린 것만', 1), MapEntry('3번 맞히면 제외', 3), MapEntry('5번 맞히면 제외', 5), MapEntry('제외 안 함', 0)],
                _graduateStreak, (v) => _graduateStreak = v),
          ],
          if (_pick == 'old' || _pick == 'mix') ...[
            _intChips('묵은 약어 기준', const [MapEntry('오래된 순', 0), MapEntry('7일 이상', 7), MapEntry('14일 이상', 14), MapEntry('30일 이상', 30)],
                _oldDays, (v) => _oldDays = v),
            _intChips('한 번도 안 본 약어', const [MapEntry('포함', 1), MapEntry('제외', 0)],
                _includeNever ? 1 : 0, (v) => _includeNever = v == 1),
            const Padding(padding: EdgeInsets.only(bottom: 14), child: Text(
              '※ 테스트 날짜는 이 기능을 쓰기 시작한 뒤부터 기록돼요. 기록이 없는 약어는 "한 번도 안 본" 약어로 처리해요.',
              style: TextStyle(fontSize: 11, color: Colors.grey))),
          ],
        ],

        // 그룹 필터
        if (_mode == 'abbr' && groups.isNotEmpty) ...[
          _lbl('그룹 필터'),
          Wrap(spacing: 8, runSpacing: 8, children: [
            GestureDetector(
              onTap: () => setState(() => _filterGroupIds.clear()),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _filterGroupIds.isEmpty ? kBlue : kBlueLight,
                  borderRadius: BorderRadius.circular(20)),
                child: Text('전체', style: TextStyle(
                    color: _filterGroupIds.isEmpty ? Colors.white : kBlue,
                    fontWeight: FontWeight.w700, fontSize: 12)))),
            ...groups.map((g) {
              final selected = _filterGroupIds.contains(g.id);
              return GestureDetector(
                onTap: () => setState(() {
                  if (selected) _filterGroupIds.remove(g.id);
                  else _filterGroupIds.add(g.id);
                }),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: selected ? g.color : kBlueLight,
                    borderRadius: BorderRadius.circular(20)),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    CircleAvatar(backgroundColor: selected ? Colors.white : g.color, radius: 5),
                    const SizedBox(width: 5),
                    Text(g.name, style: TextStyle(
                        color: selected ? Colors.white : g.color,
                        fontWeight: FontWeight.w700, fontSize: 12)),
                  ])));
            }),
          ]),
          const SizedBox(height: 20),
        ],


        if (_mode == 'abbr' && _pick != 'group') ...[
          Builder(builder: (_) {
            final n = _smartPool().length;
            return Container(
              width: double.infinity,
              margin: const EdgeInsets.only(bottom: 14),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: n == 0 ? const Color(0xFFFFF3E0) : kBlueLight,
                borderRadius: BorderRadius.circular(12)),
              child: Text(
                n == 0 ? '조건에 맞는 약어가 없어요. 옵션을 바꿔보세요.'
                       : '조건에 맞는 약어 $n개 중 ${_quizCount.clamp(1, n)}문제 출제',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700,
                    color: n == 0 ? const Color(0xFFE65100) : kBlueDark)));
          }),
        ],
        SizedBox(width: double.infinity, child: ElevatedButton(
          onPressed: _start,
          style: ElevatedButton.styleFrom(backgroundColor: kBlue, foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
          child: const Text('테스트 시작', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)))),
        const SizedBox(height: 8),
        Center(child: TextButton.icon(
          onPressed: _showTtsErrorList,
          icon: const Icon(Icons.error_outline_rounded, size: 16),
          label: Text('TTS 오류 약어 관리 (${Store.getTtsErrors().length}개)',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
          style: TextButton.styleFrom(foregroundColor: const Color(0xFFE65100)))),
      ]))));
  }

  // ── 퀴즈 진행 화면 ──
Widget _buildQuiz() {
    final tts = TtsController.instance;
    final progress = (_currentIdx + 1) / _questions.length;
    final curText = _itemText(_questions[_currentIdx]);
    final showText = _seeRound || Store.isTtsError(curText); // 정답 텍스트를 보여줄지
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
              if (!_seeRound && !showText) ...[
                const SizedBox(height: 8),
                Center(child: TextButton.icon(
                  onPressed: _ttsErrorSkip,
                  icon: const Icon(Icons.error_outline_rounded, size: 16),
                  label: const Text('TTS 오류 (다음 문제로)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFFE65100)))),
              ],
              const SizedBox(height: 16),
              // 속도 조절
              Row(children: [
                _TtsSpeedStepper(onChanged: () {
                  setState(() {});
                  _inputFocusNode.requestFocus();
                }),
                const SizedBox(width: 8),
                const Text('속도', style: TextStyle(fontSize: 12, color: Colors.grey)),
              ]),
              const SizedBox(height: 20),
              // TTS 오류 표시된 약어 / 보면서 테스트 라운드: 정답 텍스트를 보여줌
              if (showText) Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF8F0), borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFFFE0B0))),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(_seeRound ? 'TTS 오류 약어 · 보면서 입력' : 'TTS 오류로 표시된 약어',
                      style: const TextStyle(fontSize: 11, color: Color(0xFFE65100), fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  SelectionArea(child: Text(curText,
                      style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: kBlueDark))),
                ])),
              _lbl(showText ? '보이는 내용을 입력하세요' : '들은 내용을 입력하세요'),
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
                child: Text(_currentIdx < _questions.length - 1 ? '제출 → 다음'
                    : (!_seeRound && _ttsFlagged.any((f) => _itemText(f) != curText)
                        ? '제출 → TTS 오류 약어 테스트' : '제출 → 결과 보기'),
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

    // 최근 7일간 역대 오답 기록 기준으로, 많이 틀린 항목(전체 텍스트) 순 정렬
    final sortedWrong = Store.getRecentWrongCounts(days: 7).entries.toList()
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
            Text('${total == 0 ? 0 : (correct / total * 100).round()}점',
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
            final userAnswer = r['userAnswer'] as String;
            return Container(
              margin: const EdgeInsets.only(bottom: 8), padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFFFE0E0))),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('정답', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  SelectionArea(child: Text(r['question'] as String,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700))),
                ])),
                Container(width: 1, height: 32, margin: const EdgeInsets.symmetric(horizontal: 10),
                    color: const Color(0xFFFFD5D5)),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('내 답', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  SelectionArea(child: Text(userAnswer.isEmpty ? '(입력 없음)' : userAnswer,
                      style: const TextStyle(fontSize: 13, color: Colors.red, fontWeight: FontWeight.w700))),
                ])),
              ]));
          }),
          const SizedBox(height: 20),
        ],

        // 많이 틀린 항목 순위 (최근 7일, 역대 테스트 기록 기준)
        if (sortedWrong.isNotEmpty) ...[
          const Text('최근 7일 많이 틀린 약어·문장',
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