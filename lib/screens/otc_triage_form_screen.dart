import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:uuid/uuid.dart';
import 'package:intl/intl.dart';
import '../models/otc_triage_model.dart';
import '../models/patient_model.dart';
import '../services/ai_drug_service.dart';

class OTCTriageFormScreen extends StatefulWidget {
  final String facilityId;
  final PatientModel patient;

  const OTCTriageFormScreen({
    super.key,
    required this.facilityId,
    required this.patient,
  });

  @override
  State<OTCTriageFormScreen> createState() => _OTCTriageFormScreenState();
}

class _OTCTriageFormScreenState extends State<OTCTriageFormScreen> {
  late OTCTriageFormState _formState;
  bool _isLoading = false;
  String? _aiResult;
  OTCTriageRecord? _triageRecord;

  // 症状カテゴリー別の選択肢。
  // 「アルゴリズムで考える 薬剤師の臨床判断」(症候の鑑別からトリアージまで 改訂2版)の
  // 15症候の枠組みを元に、施設スタッフ(医療専門職ではない介護士・看護師)が実際に
  // 観察・聴取できる範囲の平易な表現に翻訳している(2026-07-20拡張)。
  static const Map<String, List<String>> symptomQualityOptions = {
    'cold': ['咳', '鼻水', '喉痛', '鼻づまり', 'くしゃみ'],
    'fever': ['発熱', '悪寒', '倦怠感'],
    'headache': ['頭痛', '締め付けられる感じ', 'ズキズキする感じ'],
    'rash': ['発疹', 'かゆみ', '水疱'],
    'edema': ['むくみ'],
    'dysphagia': ['飲み込みにくい', 'むせる', '食事量の低下'],
    'abdominalPain': ['腹痛'],
    'nauseaVomiting': ['吐き気', '嘔吐'],
    'diarrheaConstipation': ['下痢', '便秘'],
    'palpitations': ['動悸', '脈が速い・乱れる'],
    'coughDyspnea': ['咳', '痰', '息切れ', '呼吸が苦しい'],
    'backPain': ['腰痛'],
    'jointPain': ['関節痛', '腫れ'],
    'dizziness': ['めまい', 'ふらつき'],
    'consciousness': ['反応が鈍い', '呼びかけに答えない', 'もうろうとしている'],
    'memoryImpairment': ['もの忘れ', '見当識の混乱'],
    'other': ['その他'],
  };

  static const Map<String, List<String>> redFlagOptions = {
    'cold': [
      'highFever38Plus',
      'respiratoryDistress',
      'yellowSputum',
      'coughingUpBlood',
    ],
    'fever': [
      'consciousnessOrLethargy',
      'severeHeadacheNeckStiff',
      'breathingDifficulty',
      'cantSwallowSaliva',
      'newMedicationStarted',
      'severeAbdominalOrBackPain',
      'heatstrokeRisk',
      'travelHistory',
      'steroidWithdrawal',
    ],
    'headache': [
      'headacheSuddenOnset',
      'worstEverHeadache',
      'worseningTrend',
      'headInjuryRecent',
      'weaknessNumbnessSpeech',
      'visionOrEyePain',
      'vomitingNeckStiff',
      'consciousnessOrLethargy',
      'temporalArteritis',
    ],
    'rash': [
      'mucosalInvolvement',
      'blistersErosion',
      'newMedicationStarted',
      'feverWithRash',
      'spreadingRapidly',
      'darkNoduleUlcer',
    ],
    'edema': [
      'breathingDifficulty',
      'oneLegSuddenSwelling',
      'chestPainPalpitation',
      'faceLipSwelling',
      'jaundiceRapidWorsening',
    ],
    'dysphagia': [
      'suddenOnsetWithWeakness',
      'headInjuryRecent',
      'consciousnessOrLethargy',
      'newMedicationStarted',
    ],
    'abdominalPain': [
      'severeShockSigns',
      'vomitingBloodOrBlackStool',
      'possiblePregnancy',
      'feverWithPain',
      'rigidAbdomen',
      'noStoolGas',
      'jaundice',
      'chestPainShock',
      'pancreatitisAlcohol',
      'appendicitisPattern',
    ],
    'nauseaVomiting': [
      'severeHeadache',
      'chestPainOrBreathless',
      'bloodInVomit',
      'oneMonthOrMore',
      'dehydrationSigns',
      'suddenLowerAbdominalPainFemale',
      'jaundiceFever',
      'appendicitisPattern',
      'eyePainRednessHeadache',
      'noStoolGasVomiting',
      'backPainRadiating',
      'weaknessNumbnessSpeech',
    ],
    'diarrheaConstipation': [
      'bloodyStool',
      'vomitingBloodOrBlackStool',
      'severeAbdominalPain',
      'dizzinessOrShock',
      'breathingDifficulty',
      'noStoolGasWithVomiting',
      'urticariaWithDiarrhea',
      'highFever',
    ],
    'palpitations': [
      'breathingDifficultySwelling',
      'suddenRegularFastPulse',
      'irregularPulseNew',
    ],
    'coughDyspnea': [
      'suddenBreathlessnessAfterRest',
      'lowOxygenSigns',
      'bloodInSputum',
      'chokingEpisode',
      'highFever',
      'suddenChestPainCough',
    ],
    'backPain': [
      'analNumbnessBowelBladder',
      'severeShockSigns',
      'painMigratingBackToFlank',
      'pancreatitisAlcohol',
      'fallOrInjury',
      'feverWithBackPain',
    ],
    'jointPain': [
      'singleJointFeverHot',
      'recentInjectionOrDental',
      'dermatomyositis',
      'infectionElsewhereJoint',
    ],
    'dizziness': [
      'suddenWithWeaknessSpeech',
      'gradualWeaknessDysphagia',
      'withVomiting',
      'vertigoSpinning',
      'suddenHearingLoss',
      'chestPainPalpitation',
      'nsaidsWithBleedingSigns',
    ],
    'consciousness': [
      'seizure',
      'suddenOnsetMinutes',
    ],
    'memoryImpairment': [
      'suddenOnset',
      'headInjuryOrFall',
      'newMedicationStarted',
      'weaknessNumbness',
      'heavyAlcoholUse',
      'feverConsciousnessChange',
      'diabetesMedication',
    ],
  };

  // レッドフラッグの日本語説明
  static const Map<String, String> redFlagLabels = {
    'highFever38Plus': '38℃以上が3日以上続く',
    'respiratoryDistress': '呼吸困難がある',
    'yellowSputum': '黄色や緑色の痰が出ている',
    'coughingUpBlood': '血痰が出ている',
    'consciousnessOrLethargy': '意識がはっきりしない・ぐったりしている',
    'severeHeadacheNeckStiff': '激しい頭痛や首の後ろのこわばりを伴う',
    'breathingDifficulty': '呼吸が苦しそう',
    'cantSwallowSaliva': 'よだれが垂れる・唾も飲み込めないほどのどが痛い',
    'newMedicationStarted': '最近新しい薬を始めた直後に起きた',
    'severeAbdominalOrBackPain': '強い腹痛・背中の痛みを伴う',
    'heatstrokeRisk': '猛暑・エアコンのない環境に長時間いた',
    'travelHistory': '最近海外渡航歴がある',
    'steroidWithdrawal': 'ステロイド薬を最近中止した',
    'headacheSuddenOnset': '頭痛が急に始まった(数分〜数時間以内)',
    'worstEverHeadache': '今までで一番ひどい頭痛だと感じる',
    'worseningTrend': '日に日にひどくなっている',
    'temporalArteritis': 'こめかみ付近の脈打つような圧痛+だるさ・関節の痛み等の全身症状がある(高齢者)',
    'headInjuryRecent': '最近(数ヶ月以内)頭をぶつけた・転倒した',
    'weaknessNumbnessSpeech': '手足の麻痺・しびれ・ろれつが回らない等を伴う',
    'visionOrEyePain': '目の痛みや見え方の異常を伴う',
    'vomitingNeckStiff': '嘔吐や首の後ろのこわばりを伴う',
    'mucosalInvolvement': '目・口・唇にも症状が広がっている',
    'blistersErosion': '水疱が破れてただれている',
    'feverWithRash': '発疹に発熱を伴う',
    'spreadingRapidly': '短時間で急速に広がっている',
    'darkNoduleUlcer': '黒っぽいしこりや、治らないただれ・潰瘍がある',
    'oneLegSuddenSwelling': '片足だけ急に腫れている(長時間座った後など)',
    'chestPainPalpitation': '胸の痛みや動悸を伴う',
    'faceLipSwelling': '顔や唇が急に腫れている',
    'jaundiceRapidWorsening': '白目や皮膚が黄色い(黄疸)+数日で急に悪化している',
    'suddenOnsetWithWeakness': '急に始まり手足の麻痺やしびれを伴う',
    'severeShockSigns': '激痛でぐったりしている・顔面蒼白・冷や汗がある',
    'vomitingBloodOrBlackStool': '吐血や真っ黒な便がある',
    'possiblePregnancy': '妊娠している可能性がある',
    'feverWithPain': '発熱を伴う',
    'rigidAbdomen': 'お腹が板のように硬い',
    'noStoolGas': '排便・おならが全く出ない',
    'jaundice': '白目や皮膚が黄色い(黄疸)',
    'chestPainShock': '前胸部の痛みや締め付け感を伴う(心筋梗塞の可能性)',
    'pancreatitisAlcohol': '前かがみになると少し楽・お酒を飲んだ直後・背中に痛みが広がる',
    'appendicitisPattern': 'みぞおちの痛みが右下腹部に移動してきた+発熱+右下腹部を押すと痛がる',
    'severeHeadache': '激しい頭痛を伴う',
    'chestPainOrBreathless': '胸の痛みや息苦しさを伴う',
    'bloodInVomit': '吐血がある',
    'oneMonthOrMore': '1ヶ月以上続いている',
    'dehydrationSigns': '水分が摂れず脱水症状がある',
    'suddenLowerAbdominalPainFemale': '女性で、急な下腹部の激しい痛みがある',
    'jaundiceFever': '黄疸(白目や皮膚が黄色い)+発熱を伴う',
    'eyePainRednessHeadache': '目の痛み・充血・頭痛を伴う',
    'noStoolGasVomiting': '便やおならが全く出ない状態で嘔吐している',
    'backPainRadiating': '背中への痛みの広がりを伴う',
    'bloodyStool': '血の混じった便が出る',
    'severeAbdominalPain': '強い腹痛を伴う',
    'dizzinessOrShock': '立ちくらみ・ぐったりしている',
    'noStoolGasWithVomiting': '排便・おならが全く出ず嘔吐を伴う',
    'urticariaWithDiarrhea': '下痢と同時にじんましんが出ている',
    'breathingDifficultySwelling': '呼吸が苦しい・強いむくみを伴う',
    'suddenRegularFastPulse': '急に始まり脈が規則正しく異常に速い',
    'irregularPulseNew': '急に脈が乱れ始めた',
    'suddenBreathlessnessAfterRest': '長時間座った/寝たきりの後に急に息苦しくなった',
    'lowOxygenSigns': '唇や爪の色が悪い・呼吸がとても苦しそう',
    'bloodInSputum': '血の混じった痰が出る',
    'chokingEpisode': '食事中にむせて詰まらせた後の症状',
    'highFever': '高熱を伴う',
    'suddenChestPainCough': '運動中や体を伸ばした時に突然の胸の痛みが咳と一緒に起きた(片側だけ呼吸音が弱い場合も)',
    'analNumbnessBowelBladder': '肛門周囲のしびれ・排尿排便の異常を伴う',
    'painMigratingBackToFlank': '激しい痛みが背中から腰・脇腹へ移動してきた',
    'fallOrInjury': '転倒・尻もちをついた後の痛み',
    'feverWithBackPain': '発熱を伴う',
    'singleJointFeverHot': '1つの関節だけが赤く腫れて熱を持ち、発熱を伴う',
    'recentInjectionOrDental': '最近その関節に注射や歯科治療を受けた',
    'dermatomyositis': '筋力の低下+特徴的な発疹+息苦しさを伴う',
    'infectionElsewhereJoint': '発熱+他の部位の感染症(尿路感染・皮膚感染・歯科治療後の感染等)の症状もある状態での関節の痛み',
    'suddenWithWeaknessSpeech': '急に始まり手足の麻痺・しびれ・ろれつが回らない等を伴う',
    'gradualWeaknessDysphagia': '数日〜数週間かけて徐々に手足の麻痺・しびれ・飲み込みにくさが進行している',
    'withVomiting': '嘔吐を伴う',
    'vertigoSpinning': '周囲がぐるぐる回る感じがする',
    'suddenHearingLoss': '片側の聴力が急に低下した',
    'nsaidsWithBleedingSigns': '痛み止め(NSAIDs)を常用中で、立ちくらみや真っ黒な便がある',
    'seizure': 'けいれんを伴う',
    'suddenOnsetMinutes': '数分以内に急に始まった',
    'suddenOnset': '急に起こった',
    'headInjuryOrFall': '頭部外傷・転倒の既往がある',
    'weaknessNumbness': '手足の麻痺・しびれを伴う',
    'heavyAlcoholUse': '大量の飲酒歴がある',
    'feverConsciousnessChange': '頭痛・発熱を伴い、反応がぼんやりしてきた',
    'diabetesMedication': '糖尿病治療薬(インスリン・血糖降下薬)を使用中',
  };

  // consultationFlags: redFlagsより一段弱い「受診勧奨」相当のサイン。
  // 該当しても「医療機関受診推奨」(赤/緊急)にはせず、「薬剤師相談推奨」(黄)に留める。
  // 例: 風邪で鼻水・喉の痛み・咳のうち1つだけが強く出ている場合、単一臓器への細菌感染
  // (副鼻腔炎・溶連菌性咽頭炎等)の可能性があり受診が望ましいが、緊急性が高いわけではない
  // (書籍2「薬学臨床推論」第3章の核心ルール: 複数臓器にまたがる症状はウイルス性=風邪らしい)。
  static const Map<String, List<String>> consultationFlagOptions = {
    'cold': ['oneSymptomDominant'],
  };

  static const Map<String, String> consultationFlagLabels = {
    'oneSymptomDominant': '鼻水・喉の痛み・咳のうち1つだけが強く出ている(他はほとんどない)',
  };

  // 症状の経過(OPQRSTのP=増悪寛解因子・T=時間経過に対応)
  static const Map<String, String> _symptomPatternOptions = {
    'acute': '急性(数日以内)',
    'chronic': '慢性(数週間以上)',
    'recurring': '反復性(繰り返している)',
  };

  static const List<String> _timingOptions = [
    '特になし',
    '朝に悪化',
    '夜間に悪化',
    '食後に悪化',
    '空腹時に悪化',
    '安静で軽快',
  ];

  static const List<String> _relatedFactorOptions = [
    '体を動かすと悪化する',
    '安静にすると軽快する',
    '排便・嘔吐をすると軽快する',
    '特定の姿勢で悪化する',
    'ストレスで悪化する',
    '飲酒・食事に関連する',
  ];

  // カテゴリー表示名
  static const Map<String, String> categoryLabels = {
    'cold': '風邪シリーズ',
    'fever': '発熱',
    'headache': '頭痛',
    'rash': '発疹',
    'edema': 'むくみ',
    'dysphagia': '飲み込みにくさ',
    'abdominalPain': '腹痛',
    'nauseaVomiting': '吐き気・嘔吐',
    'diarrheaConstipation': '下痢・便秘',
    'palpitations': '動悸',
    'coughDyspnea': '咳・呼吸困難',
    'backPain': '腰痛',
    'jointPain': '関節痛',
    'dizziness': 'めまい',
    'consciousness': '意識障害・反応低下',
    'memoryImpairment': 'もの忘れ・混乱',
    'other': 'その他',
  };

  @override
  void initState() {
    super.initState();
    _formState = OTCTriageFormState();
    _initializeRedFlags();
  }

  void _initializeRedFlags() {
    final redFlags = redFlagOptions[_formState.symptomCategory] ?? [];
    for (var flag in redFlags) {
      _formState.redFlags[flag] = false;
    }
    final consultationFlags = consultationFlagOptions[_formState.symptomCategory] ?? [];
    for (var flag in consultationFlags) {
      _formState.consultationFlags[flag] = false;
    }
  }

  void _updateSymptomCategory(String category) {
    setState(() {
      _formState.symptomCategory = category;
      _formState.symptomQualities = [];
      _formState.redFlags.clear();
      _formState.consultationFlags.clear();
      _initializeRedFlags();
    });
  }

  /// トリアージフォームを AI で分析
  Future<void> _submitTriageForm() async {
    if (_formState.symptomQualities.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('症状を選択してください'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) throw Exception('User not authenticated');

      // ユーザー情報取得
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      final userName = userDoc['name'] as String? ?? 'Unknown';

      // トリアージレコードを作成（ID生成）
      final triageId = const Uuid().v4();

      // Goプロキシの /v1/triage を呼び出す。
      // triageResult・redFlagOverride はサーバー側の決定論的ロジックが権威を持つ値であり、
      // Flutter側では計算し直さず、そのまま採用する(AI呼び出しが失敗してもフォールバック値が返る)。
      final triageProxyResult = await AiDrugService().analyzeTriage(
        symptomCategory: _formState.symptomCategory,
        symptomQualities: _formState.symptomQualities,
        severityScore: _formState.severityScore,
        redFlags: _formState.redFlags,
        consultationFlags: _formState.consultationFlags,
        spo2: _formState.spo2,
        bpSystolic: _formState.bpSystolic,
        pulseRate: _formState.pulseRate,
        egfr: widget.patient.egfr,
        liverStatus: widget.patient.liverStatus.isNotEmpty ? widget.patient.liverStatus : null,
        medicineNames: widget.patient.medicines.map((m) => m.name).toList(),
      );

      final triageResult = triageProxyResult['triageResult'] as String? ?? 'consultation';
      final aiAnalysis = triageProxyResult['explanation'] as String? ?? '';

      // Firestore に保存
      final triageRecord = OTCTriageRecord(
        id: triageId,
        patientId: widget.patient.id,
        facilityId: widget.facilityId,
        symptomCategory: _formState.symptomCategory,
        symptomOnset: _formState.symptomOnset,
        symptomPattern: _formState.symptomPattern,
        symptomQualities: _formState.symptomQualities,
        relatedFactors: _formState.relatedFactors,
        severityScore: _formState.severityScore,
        timing: _formState.timing,
        redFlags: _formState.redFlags,
        consultationFlags: _formState.consultationFlags,
        spo2: _formState.spo2,
        bpSystolic: _formState.bpSystolic,
        pulseRate: _formState.pulseRate,
        egfr: widget.patient.egfr,
        liverStatus: widget.patient.liverStatus.isNotEmpty ? widget.patient.liverStatus : null,
        allergies: widget.patient.allergies,
        existingConditions: widget.patient.conditions.isNotEmpty
            ? widget.patient.conditions
            : [],
        triageResult: triageResult,
        triageExplanation: aiAnalysis,
        conductedBy: currentUser.uid,
        conductedByName: userName,
        createdAt: Timestamp.now(),
      );

      // Firestore に保存
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patient.id)
          .collection('otc_triage_records')
          .doc(triageId)
          .set(triageRecord.toJson());

      setState(() {
        _triageRecord = triageRecord;
        _aiResult = aiAnalysis;
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('トリアージを実施しました'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Triage submission error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// 相談ルームを作成して接続
  Future<void> _createConsultationRoom() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null || _triageRecord == null) return;

      // チャットルームを作成
      final roomRef = FirebaseFirestore.instance
          .collection('facilities')
          .doc(widget.facilityId)
          .collection('rooms')
          .doc();

      await roomRef.set({
        'id': roomRef.id,
        'facilityId': widget.facilityId,
        'type': 'triage_consultation',
        'patientId': widget.patient.id,
        'patientName': widget.patient.name,
        'name': '${widget.patient.name}さんのOTC症状相談',
        'members': [currentUser.uid],
        'createdAt': FieldValue.serverTimestamp(),
        'triageRecordId': _triageRecord!.id,
      });

      // トリアージレコードを更新
      await FirebaseFirestore.instance
          .collection('patients')
          .doc(widget.patient.id)
          .collection('otc_triage_records')
          .doc(_triageRecord!.id)
          .update({
            'consultationRoomId': roomRef.id,
            'updatedAt': FieldValue.serverTimestamp(),
          });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('薬剤師に相談ルームが作成されました'),
          backgroundColor: Colors.green,
        ),
      );

      // チャット画面へ遷移
      Navigator.of(context).pushNamed(
        '/chat',
        arguments: {
          'facilityId': widget.facilityId,
          'roomId': roomRef.id,
        },
      );
    } catch (e) {
      debugPrint('Consultation room creation error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('エラー: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_triageRecord != null && _aiResult != null) {
      return _buildResultScreen();
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('症状相談トリアージ - ${widget.patient.name}'),
        centerTitle: true,
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 患者情報表示
                  Card(
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '患者情報',
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          SizedBox(height: 8),
                          Text('名前: ${widget.patient.name}'),
                          Text('年齢: ${widget.patient.age}歳'),
                          if (widget.patient.egfr != null && widget.patient.egfr! > 0)
                            Text('eGFR: ${widget.patient.egfr!.toStringAsFixed(1)} mL/min'),
                          if (widget.patient.liverStatus.isNotEmpty)
                            Text('肝機能: ${widget.patient.liverStatus}'),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 20),

                  // 症状カテゴリー選択
                  Text('1. 症状カテゴリーを選択',
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: symptomQualityOptions.keys.map((category) {
                      final categoryLabel = categoryLabels[category] ?? category;

                      return ChoiceChip(
                        label: Text(categoryLabel),
                        selected: _formState.symptomCategory == category,
                        onSelected: (_) => _updateSymptomCategory(category),
                      );
                    }).toList(),
                  ),
                  if (_formState.symptomCategory == 'consciousness')
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: Colors.red.shade200),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.warning_amber_rounded, color: Colors.red, size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '意識障害・反応低下は原則として救急要請・医療機関受診が必要です。'
                                'このフォームの入力を待たず、緊急時はすぐに救急要請してください。',
                                style: TextStyle(fontSize: 12, color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  SizedBox(height: 20),

                  // 症状詳細選択
                  Text('2. 具体的な症状を選択',
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: (symptomQualityOptions[_formState.symptomCategory] ?? [])
                        .map((quality) {
                      return FilterChip(
                        label: Text(quality),
                        selected: _formState.symptomQualities.contains(quality),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _formState.symptomQualities.add(quality);
                            } else {
                              _formState.symptomQualities.remove(quality);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 20),

                  // 症状の重症度
                  Text('3. 症状の重症度',
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: List.generate(5, (i) {
                      final score = i + 1;
                      return Expanded(
                        child: GestureDetector(
                          onTap: () {
                            setState(() => _formState.severityScore = score);
                          },
                          child: Card(
                            color: _formState.severityScore == score
                                ? Colors.blue
                                : Colors.grey[200],
                            child: Padding(
                              padding: EdgeInsets.all(12),
                              child: Column(
                                children: [
                                  Text(
                                    '$score',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                      color: _formState.severityScore == score
                                          ? Colors.white
                                          : Colors.black,
                                    ),
                                  ),
                                  Text(
                                    ['軽', '軽中', '中', '中重', '重'][i],
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: _formState.severityScore == score
                                          ? Colors.white
                                          : Colors.grey,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                  SizedBox(height: 20),

                  // 症状発症時刻
                  Text('4. 症状発症時刻',
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 12),
                  Card(
                    child: ListTile(
                      title: Text(DateFormat('yyyy年M月d日 HH:mm').format(_formState.symptomOnset)),
                      trailing: Icon(Icons.calendar_today),
                      onTap: () async {
                        final picked = await showDatePicker(
                          context: context,
                          initialDate: _formState.symptomOnset,
                          firstDate: DateTime.now().subtract(Duration(days: 7)),
                          lastDate: DateTime.now(),
                        );
                        if (picked != null) {
                          setState(() {
                            _formState.symptomOnset = DateTime(
                              picked.year,
                              picked.month,
                              picked.day,
                              _formState.symptomOnset.hour,
                              _formState.symptomOnset.minute,
                            );
                          });
                        }
                      },
                    ),
                  ),
                  SizedBox(height: 20),

                  // 症状の経過(OPQRSTのP・T要素)
                  Text('5. 症状の経過',
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _symptomPatternOptions.entries.map((entry) {
                      return ChoiceChip(
                        label: Text(entry.value),
                        selected: _formState.symptomPattern == entry.key,
                        onSelected: (_) {
                          setState(() => _formState.symptomPattern = entry.key);
                        },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 12),
                  Text('悪化・軽快のタイミング（あれば選択）',
                      style: Theme.of(context).textTheme.bodyMedium),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _timingOptions.map((option) {
                      return ChoiceChip(
                        label: Text(option),
                        selected: _formState.timing == option ||
                            (option == '特になし' && _formState.timing.isEmpty),
                        onSelected: (_) {
                          setState(() {
                            _formState.timing = option == '特になし' ? '' : option;
                          });
                        },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 12),
                  Text('増悪・寛解因子（複数選択可）',
                      style: Theme.of(context).textTheme.bodyMedium),
                  SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: _relatedFactorOptions.map((option) {
                      return FilterChip(
                        label: Text(option),
                        selected: _formState.relatedFactors.contains(option),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _formState.relatedFactors.add(option);
                            } else {
                              _formState.relatedFactors.remove(option);
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  SizedBox(height: 20),

                  // バイタルサイン(オプション)
                  Text('6. バイタルサイン（測定できれば入力、未測定でも進められます）',
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: 'SpO2（%）',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            _formState.spo2 = double.tryParse(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: '収縮期血圧（mmHg）',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            _formState.bpSystolic = double.tryParse(value);
                          },
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          decoration: const InputDecoration(
                            labelText: '脈拍（回/分）',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (value) {
                            _formState.pulseRate = double.tryParse(value);
                          },
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 20),

                  // レッドフラッグサイン
                  Text('7. 危険信号（当てはまるものを選択）',
                      style: Theme.of(context).textTheme.titleMedium),
                  SizedBox(height: 12),
                  ...((redFlagOptions[_formState.symptomCategory] ?? [])
                      .map((flag) {
                    return CheckboxListTile(
                      title: Text(redFlagLabels[flag] ?? flag),
                      value: _formState.redFlags[flag] ?? false,
                      onChanged: (value) {
                        setState(() {
                          _formState.redFlags[flag] = value ?? false;
                        });
                      },
                    );
                  })),
                  if ((consultationFlagOptions[_formState.symptomCategory] ?? []).isNotEmpty) ...[
                    SizedBox(height: 20),
                    Text('8. その他、受診の目安になるサイン',
                        style: Theme.of(context).textTheme.titleMedium),
                    SizedBox(height: 12),
                    ...((consultationFlagOptions[_formState.symptomCategory] ?? [])
                        .map((flag) {
                      return CheckboxListTile(
                        title: Text(consultationFlagLabels[flag] ?? flag),
                        value: _formState.consultationFlags[flag] ?? false,
                        onChanged: (value) {
                          setState(() {
                            _formState.consultationFlags[flag] = value ?? false;
                          });
                        },
                      );
                    })),
                  ],
                  SizedBox(height: 30),

                  // 送信ボタン
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _submitTriageForm,
                      icon: Icon(Icons.check_circle),
                      label: Text('トリアージを実施'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        padding: EdgeInsets.symmetric(vertical: 16),
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  /// 結果画面
  Widget _buildResultScreen() {
    final record = _triageRecord!;
    final resultColor = Color(record.resultColor);

    return PopScope(
      canPop: true,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) Navigator.of(context).pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text('トリアージ結果'),
          centerTitle: true,
        ),
        body: SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 判定結果カード
              Card(
                color: resultColor,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '判定結果',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        record.resultLabel,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 24,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),

              // AI 分析結果
              Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'AI 分析結果',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: 12),
                      Text(
                        _aiResult ?? '',
                        style: TextStyle(height: 1.6),
                      ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),

              // トリアージ詳細情報
              Card(
                child: Padding(
                  padding: EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'トリアージ詳細',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      SizedBox(height: 12),
                      Text('症状: ${record.symptomQualities.join('、')}'),
                      Text('重症度: ${record.severityLabel}'),
                      Text('発症: ${DateFormat('M月d日 HH:mm').format(record.symptomOnset)}'),
                      if (record.spo2 != null)
                        Text('SpO2: ${record.spo2!.toStringAsFixed(0)}%'),
                      if (record.bpSystolic != null)
                        Text('収縮期血圧: ${record.bpSystolic!.toStringAsFixed(0)} mmHg'),
                      if (record.pulseRate != null)
                        Text('脈拍: ${record.pulseRate!.toStringAsFixed(0)} 回/分'),
                      if (record.redFlags.values.any((v) => v))
                        Text(
                          '⚠️ 危険信号あり',
                          style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      if (record.consultationFlags.values.any((v) => v))
                        Text(
                          '△ 受診の目安になるサインあり',
                          style: TextStyle(color: Colors.orange[800], fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),
              ),
              SizedBox(height: 20),

              // アクションボタン
              if (record.triageResult == 'consultation')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _createConsultationRoom,
                    icon: Icon(Icons.chat),
                    label: Text('薬剤師に相談'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.amber[600],
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              if (record.triageResult == 'medical_referral')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('医療機関の受診をお勧めします'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    },
                    icon: Icon(Icons.local_hospital),
                    label: Text('医療機関受診が必要です'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              if (record.triageResult == 'otc_suitable')
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.of(context).pop();
                    },
                    icon: Icon(Icons.check_circle),
                    label: Text('OTC医薬品で対応可能'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.symmetric(vertical: 16),
                    ),
                  ),
                ),
              SizedBox(height: 20),

              // 戻るボタン
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text('戻る'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
