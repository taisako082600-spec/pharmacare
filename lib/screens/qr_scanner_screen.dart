import 'package:flutter/material.dart';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:js' as js;
import 'dart:async';
import 'dart:convert';
import '../models/user_model.dart';
import '../services/qr_medicine_service.dart';
import '../services/ocr_medicine_service.dart';
import '../services/connectivity_guard.dart';

class QRScannerScreen extends StatefulWidget {
  final String patientId;
  final String patientName;
  final UserModel user;

  const QRScannerScreen({
    super.key,
    required this.patientId,
    required this.patientName,
    required this.user,
  });

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final _qrService = QRMedicineService();
  final _ocrService = OcrMedicineService();
  static const int _maxScans = 3;

  final List<String> _scanned = [];
  List<Map<String, dynamic>>? _ocrMedicines;
  bool _isProcessing = false;
  bool _isOcrLoading = false;
  String? _lastError;

  void Function(FlutterErrorDetails)? _originalOnError;

  @override
  void initState() {
    super.initState();
    _originalOnError = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      _originalOnError?.call(details);
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _lastError = '[Flutter] ${details.exception}\n${details.stack.toString().split('\n').take(4).join('\n')}';
        });
      }
    };
  }

  @override
  void dispose() {
    FlutterError.onError = _originalOnError;
    super.dispose();
  }

  void _shoot() {
    if (!mounted) return;
    setState(() { _isProcessing = false; _lastError = null; });

    final completer = Completer<String?>();
    js.context['_qrLiveDone'] = js.JsFunction.withThis((_, dynamic result) {
      if (!completer.isCompleted) completer.complete(result?.toString());
    });

    // ライブカメラスキャナーを起動（index.html に定義済み）
    final jsMaxScans = _maxScans;
    final jsHeader = '(function(){'
        'if(document.getElementById("_liveqr_overlay"))return;'
        'var maxScans=$jsMaxScans;';
    // ignore: prefer_adjacent_string_concatenation
    js.context.callMethod('eval', [jsHeader + r'''
        var scanned = [];
        var scanner = null;

        var ov = document.createElement('div');
        ov.id = '_liveqr_overlay';
        ov.style.cssText = 'position:fixed;inset:0;background:#000;z-index:99999;display:flex;flex-direction:column;align-items:center;font-family:sans-serif;';

        var hdr = document.createElement('div');
        hdr.style.cssText = 'width:100%;display:flex;align-items:center;justify-content:space-between;padding:16px 20px;box-sizing:border-box;background:rgba(0,0,0,0.8);';
        var titleEl = document.createElement('div');
        titleEl.style.cssText = 'color:#fff;font-size:15px;font-weight:bold;';
        titleEl.textContent = 'QRコードをかざしてください';
        var closeBtn = document.createElement('button');
        closeBtn.textContent = '✕';
        closeBtn.style.cssText = 'background:none;border:none;color:#fff;font-size:22px;cursor:pointer;padding:4px 12px;';
        hdr.appendChild(titleEl); hdr.appendChild(closeBtn); ov.appendChild(hdr);

        var counter = document.createElement('div');
        counter.style.cssText = 'display:flex;gap:12px;padding:10px 0 8px;';
        function updateCounter() {
          counter.innerHTML = '';
          for (var i = 0; i < maxScans; i++) {
            var dot = document.createElement('div');
            var done = i < scanned.length;
            dot.style.cssText = 'width:40px;height:40px;border-radius:8px;display:flex;align-items:center;justify-content:center;font-size:20px;font-weight:bold;' +
              (done ? 'background:#1976D2;color:#fff;' : 'background:rgba(255,255,255,0.15);color:rgba(255,255,255,0.4);');
            dot.textContent = done ? '✓' : (i + 1);
            counter.appendChild(dot);
          }
        }
        updateCounter(); ov.appendChild(counter);

        var vwrap = document.createElement('div');
        vwrap.style.cssText = 'position:relative;width:100%;flex:1;overflow:hidden;';
        var video = document.createElement('video');
        video.autoplay = true; video.playsInline = true; video.muted = true;
        video.style.cssText = 'width:100%;height:100%;object-fit:cover;';
        vwrap.appendChild(video);

        var box = document.createElement('div');
        box.style.cssText = 'position:absolute;top:50%;left:50%;transform:translate(-50%,-55%);width:230px;height:230px;border:3px solid #42A5F5;border-radius:12px;box-shadow:0 0 0 9999px rgba(0,0,0,0.45);pointer-events:none;';
        vwrap.appendChild(box);

        var flash = document.createElement('div');
        flash.style.cssText = 'position:absolute;inset:0;background:#fff;opacity:0;pointer-events:none;transition:opacity 0.25s;';
        vwrap.appendChild(flash);

        var status = document.createElement('div');
        status.style.cssText = 'position:absolute;bottom:12px;left:0;right:0;text-align:center;color:#fff;font-size:13px;text-shadow:0 1px 4px #000;padding:0 12px;';
        status.textContent = 'QRコードが枠内に収まるよう近づけてください';
        vwrap.appendChild(status);
        ov.appendChild(vwrap);

        var ftr = document.createElement('div');
        ftr.style.cssText = 'width:100%;padding:12px 20px 28px;box-sizing:border-box;background:rgba(0,0,0,0.8);';
        var doneBtn = document.createElement('button');
        doneBtn.style.cssText = 'width:100%;padding:14px;background:#388E3C;color:#fff;border:none;border-radius:12px;font-size:16px;font-weight:bold;cursor:pointer;opacity:0.35;';
        doneBtn.textContent = '完了（0/' + maxScans + '）';
        doneBtn.disabled = true;
        ftr.appendChild(doneBtn); ov.appendChild(ftr);
        document.body.appendChild(ov);

        var paused = false;

        function onDetected(data) {
          if (!data || scanned.indexOf(data) !== -1 || paused) return;
          paused = true;
          scanned.push(data);
          flash.style.opacity = '0.8';
          setTimeout(function() { flash.style.opacity = '0'; }, 120);
          updateCounter();
          doneBtn.textContent = '完了（' + scanned.length + '/' + maxScans + '）';
          doneBtn.disabled = false; doneBtn.style.opacity = '1';
          if (scanned.length >= maxScans) {
            status.textContent = 'すべて読み取り完了！';
            setTimeout(function() { _stop(); }, 600);
            return;
          }
          status.textContent = scanned.length + '枚読み取り！次のQRをかざしてください';
          setTimeout(function() { paused = false; status.textContent = 'QRコードが枠内に収まるよう近づけてください'; }, 800);
        }

        function _stop() {
          if (scanner) { try { scanner.stop(); scanner.destroy(); } catch(e) {} scanner = null; }
          if (ov.parentNode) ov.parentNode.removeChild(ov);
          var result = scanned.length > 0 ? JSON.stringify(scanned) : null;
          if (window._qrLiveDone) { window._qrLiveDone(result); window._qrLiveDone = null; }
        }

        closeBtn.onclick = function() { _stop(); };
        doneBtn.onclick = function() { _stop(); };

        if (typeof QrScanner !== 'undefined') {
          try {
            scanner = new QrScanner(video, function(result) {
              var data = (result && typeof result === 'object') ? result.data : result;
              onDetected(data);
            }, {
              onDecodeError: function() {},
              preferredCamera: 'environment',
              highlightScanRegion: false,
              calculateScanRegion: function(v) {
                var s = Math.min(v.videoWidth, v.videoHeight) * 0.7;
                return { x: (v.videoWidth - s) / 2, y: (v.videoHeight - s) / 2, width: s, height: s };
              }
            });
            scanner.start().catch(function(err) {
              status.textContent = 'カメラにアクセスできません: ' + err.message;
            });
          } catch(e) {
            status.textContent = 'エラー: ' + e;
          }
        } else {
          navigator.mediaDevices.getUserMedia({ video: { facingMode: 'environment' } }).then(function(stream) {
            video.srcObject = stream;
            var canvas = document.createElement('canvas');
            var ctx2 = canvas.getContext('2d');
            var active = true;
            var lastScanTime = 0;
            var id = null;
            function stopStream() { active = false; stream.getTracks().forEach(function(t){t.stop();}); }
            closeBtn.addEventListener('click', stopStream);
            doneBtn.addEventListener('click', stopStream);
            function tick() {
              if (!active || !ov.parentNode) return;
              if (video.readyState >= 2 && typeof jsQR !== 'undefined') {
                var now = performance.now();
                if (now - lastScanTime >= 50) {
                  lastScanTime = now;
                  canvas.width = video.videoWidth; canvas.height = video.videoHeight;
                  ctx2.drawImage(video, 0, 0);
                  id = ctx2.getImageData(0, 0, canvas.width, canvas.height);
                  var res = jsQR(id.data, id.width, id.height, { inversionAttempts: 'attemptBoth' });
                  if (res) onDetected(res.data);
                }
              }
              requestAnimationFrame(tick);
            }
            tick();
          }).catch(function(err) {
            status.textContent = 'カメラにアクセスできません: ' + err.message;
          });
        }
      })()
    ''']);

    completer.future.then((jsonResult) async {
      if (!mounted) return;
      try {
        if (jsonResult == null || jsonResult.isEmpty) {
          setState(() { _lastError = null; });
          return;
        }

        final List<dynamic> decoded = jsonDecode(jsonResult) as List;
        final newCodes = decoded
            .map((e) => e.toString())
            .where((s) => s.isNotEmpty && !_scanned.contains(s))
            .toList();

        if (newCodes.isEmpty) {
          setState(() { _lastError = 'すでに読み取り済みのQRコードです。'; });
          return;
        }

        setState(() {
          for (final code in newCodes) {
            if (_scanned.length < _maxScans) _scanned.add(code);
          }
          _isProcessing = false;
        });
      } catch (err, stack) {
        debugPrint('QR process error: $err\n$stack');
        if (!mounted) return;
        setState(() {
          _isProcessing = false;
          _lastError = '$err';
        });
      }
    });

  }

  Future<void> _pickPhoto() async {
    setState(() { _isOcrLoading = true; _lastError = null; });
    try {
      final img = await _ocrService.pickImage();
      if (img == null) {
        setState(() => _isOcrLoading = false);
        return;
      }
      if (!mounted) return;
      // プレビューダイアログ（処理中）
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => const AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('AIが薬袋を解析中…'),
            ],
          ),
        ),
      );

      final medicines = await _ocrService.extractMedicines(img.base64, img.mediaType);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // ダイアログを閉じる

      if (medicines == null || medicines.isEmpty) {
        setState(() {
          _isOcrLoading = false;
          _lastError = '薬剤情報を認識できませんでした。写真を撮り直してください。';
        });
        return;
      }

      setState(() {
        _ocrMedicines = medicines;
        _isOcrLoading = false;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _isOcrLoading = false;
          _lastError = 'OCRエラー: $e';
        });
      }
    }
  }

  Future<void> _register() async {
    final medicines = _ocrMedicines ?? _qrService.parseMultipleQRCodes(_scanned);

    if (medicines == null || medicines.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('薬剤データを認識できませんでした。QRの形式を確認してください。'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);

    // Step 1: 薬剤内容を確認
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('${medicines.length}剤を一括登録します'),
        content: SizedBox(
          width: double.maxFinite,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('患者：${widget.patientName}',
                    style: const TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 12),
                ...medicines.asMap().entries.map((e) {
                  final m = e.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF5F7FA),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('第${e.key + 1}剤',
                            style: const TextStyle(fontSize: 11, color: Colors.black38)),
                        const SizedBox(height: 4),
                        Text(m['name'] ?? '',
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.bold)),
                        if ((m['dosage'] ?? '').toString().isNotEmpty)
                          Text(m['dosage'].toString(),
                              style: const TextStyle(fontSize: 13, color: Colors.black54)),
                        if ((m['frequency'] ?? '').toString().isNotEmpty)
                          Text(m['frequency'].toString(),
                              style: const TextStyle(fontSize: 13, color: Colors.black54)),
                      ],
                    ),
                  );
                }),
                const Text('次の画面で受診情報を入力してください',
                    style: TextStyle(fontSize: 12, color: Colors.orange)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('キャンセル')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green, foregroundColor: Colors.white),
            child: const Text('次へ'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    // Step 2: 受診情報を入力（薬剤別日数も設定）
    final visitInfo = await _showVisitInfoDialog(medicines);
    if (visitInfo == null || !mounted) return;
    if (!await ConnectivityGuard.ensureOnline(context)) return;

    setState(() => _isProcessing = true);
    final isOcr = _ocrMedicines != null;
    final medicinesWithDays = visitInfo['medicines'] as List<Map<String, dynamic>>;
    final result = await _qrService.registerVisitWithMedicines(
      patientId: widget.patientId,
      visitDate: visitInfo['visitDate'] as DateTime,
      department: visitInfo['department'] as String,
      mainSymptom: visitInfo['mainSymptom'] as String,
      pharmacistNote: visitInfo['pharmacistNote'] as String,
      nextVisitDate: visitInfo['nextVisitDate'] as DateTime?,
      medicines: medicinesWithDays.map((m) => {...m, 'addedVia': isOcr ? 'OCR' : 'QR'}).toList(),
      addedBy: widget.user.uid,
      addedByName: widget.user.name,
      facilityId: widget.user.facilityId,
    );
    if (!mounted) return;
    setState(() => _isProcessing = false);

    messenger.showSnackBar(SnackBar(
      content: Text(result.failed == 0
          ? '${result.success}剤を受診記録と共に登録しました'
          : '${result.success}剤登録完了、${result.failed}剤失敗'),
      backgroundColor: result.failed == 0 ? Colors.green : Colors.orange,
    ));
    _ocrMedicines = null;
    navigator.pop(true);
  }

  Future<Map<String, dynamic>?> _showVisitInfoDialog(List<Map<String, dynamic>> medicines) async {
    DateTime visitDate = DateTime.now();
    DateTime? nextVisitDate;
    final deptCtrl = TextEditingController();
    final symptomCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final daysCtrlMap = {for (final m in medicines) m: TextEditingController(text: m['days']?.toString() ?? '')};
    final dosageCtrlMap = {for (final m in medicines) m: TextEditingController(text: m['dosage']?.toString() ?? '')};
    final usageNoteCtrlMap = {for (final m in medicines) m: TextEditingController(text: m['usageNote']?.toString() ?? '')};
    final timingMap = <Map<String, dynamic>, String>{for (final m in medicines) m: (m['frequency'] as String? ?? '朝・昼・夕')};
    const timingOptions = ['朝', '昼', '夕', '就寝前', '朝・夕', '朝・昼・夕', '頓服'];
    final deptOptions = ['内科', '外科', '整形外科', '皮膚科', '耳鼻科', '眼科', '泌尿器科', '小児科', 'その他'];

    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => StatefulBuilder(
        builder: (ctx, setModal) => Padding(
          padding: EdgeInsets.fromLTRB(
              20, 20, 20, MediaQuery.of(ctx).viewInsets.bottom + 24),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const Icon(Icons.local_hospital, color: Color(0xFF2E7D32)),
                    const SizedBox(width: 8),
                    const Text('受診情報を入力',
                        style: TextStyle(
                            fontSize: 18, fontWeight: FontWeight.bold)),
                    const Spacer(),
                    IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.pop(ctx)),
                  ],
                ),
                const SizedBox(height: 16),

                // 受診日
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate: visitDate,
                      firstDate: DateTime(2020),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setModal(() => visitDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.calendar_today,
                            size: 18, color: Color(0xFF2E7D32)),
                        const SizedBox(width: 10),
                        Text(
                          '受診日: ${visitDate.year}年${visitDate.month}月${visitDate.day}日',
                          style: const TextStyle(fontSize: 15),
                        ),
                        const Spacer(),
                        const Icon(Icons.edit, size: 16, color: Colors.black38),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 診療科
                const Text('診療科',
                    style:
                        TextStyle(fontSize: 13, color: Colors.black54)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: deptOptions.map((d) {
                    final sel = deptCtrl.text == d;
                    return GestureDetector(
                      onTap: () =>
                          setModal(() => deptCtrl.text = sel ? '' : d),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: sel
                              ? const Color(0xFF2E7D32)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(d,
                            style: TextStyle(
                                fontSize: 13,
                                color: sel ? Colors.white : Colors.black87)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 12),

                // 主症状
                TextField(
                  controller: symptomCtrl,
                  decoration: const InputDecoration(
                      labelText: '主症状（例: 発熱・咳）',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),

                // 薬剤別設定
                const Text('薬剤別設定（用法・用量・日数）',
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.black54)),
                const SizedBox(height: 8),
                ...medicines.asMap().entries.map((e) {
                  final idx = e.key;
                  final med = e.value;
                  return Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade50,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.grey.shade200),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('第${idx + 1}剤: ${med['name'] ?? ''}',
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                        const SizedBox(height: 8),
                        TextField(
                          controller: dosageCtrlMap[med],
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: '1回量（例: 1錠、5mg）',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 4,
                          runSpacing: 4,
                          children: timingOptions.map((t) => ChoiceChip(
                            label: Text(t, style: const TextStyle(fontSize: 11)),
                            selected: timingMap[med] == t,
                            onSelected: (_) => setModal(() => timingMap[med] = t),
                            selectedColor: const Color(0xFF1976D2),
                            labelStyle: TextStyle(
                                color: timingMap[med] == t ? Colors.white : Colors.black87,
                                fontSize: 11),
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 0),
                            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          )).toList(),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: daysCtrlMap[med],
                          keyboardType: TextInputType.number,
                          style: const TextStyle(fontSize: 13),
                          decoration: InputDecoration(
                            labelText: '処方日数',
                            suffixText: '日',
                            isDense: true,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          ),
                        ),
                        const SizedBox(height: 8),
                        TextField(
                          controller: usageNoteCtrlMap[med],
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: '用法備考（例: 不均等、食前、隔日など）',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
                const SizedBox(height: 4),

                // 次回受診日
                GestureDetector(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: ctx,
                      initialDate:
                          nextVisitDate ?? DateTime.now().add(const Duration(days: 14)),
                      firstDate: DateTime.now(),
                      lastDate: DateTime(2030),
                    );
                    if (picked != null) setModal(() => nextVisitDate = picked);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                        border: Border.all(color: Colors.grey.shade300),
                        borderRadius: BorderRadius.circular(10)),
                    child: Row(
                      children: [
                        const Icon(Icons.event, size: 18, color: Colors.teal),
                        const SizedBox(width: 10),
                        Text(
                          nextVisitDate != null
                              ? '次回受診: ${nextVisitDate!.year}年${nextVisitDate!.month}月${nextVisitDate!.day}日'
                              : '次回受診日（任意）',
                          style: TextStyle(
                              fontSize: 15,
                              color: nextVisitDate != null
                                  ? Colors.black87
                                  : Colors.black38),
                        ),
                        const Spacer(),
                        if (nextVisitDate != null)
                          GestureDetector(
                            onTap: () => setModal(() => nextVisitDate = null),
                            child: const Icon(Icons.clear,
                                size: 16, color: Colors.black38),
                          )
                        else
                          const Icon(Icons.add, size: 16, color: Colors.black38),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // 薬剤師コメント
                TextField(
                  controller: noteCtrl,
                  maxLines: 2,
                  decoration: const InputDecoration(
                      labelText: '薬剤師コメント（服薬指導メモ）',
                      border: OutlineInputBorder()),
                ),
                const SizedBox(height: 20),

                SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: ElevatedButton(
                    onPressed: () {
                      final medicinesWithDays = medicines.map((m) {
                        final days = int.tryParse(daysCtrlMap[m]?.text.trim() ?? '') ?? 0;
                        return {
                          ...m,
                          'days': days,
                          'dosage': dosageCtrlMap[m]?.text.trim() ?? m['dosage'] ?? '',
                          'frequency': timingMap[m] ?? m['frequency'] ?? '朝・昼・夕',
                          'usageNote': usageNoteCtrlMap[m]?.text.trim() ?? '',
                        };
                      }).toList();
                      Navigator.pop(ctx, {
                        'visitDate': visitDate,
                        'department': deptCtrl.text.trim(),
                        'mainSymptom': symptomCtrl.text.trim(),
                        'pharmacistNote': noteCtrl.text.trim(),
                        'nextVisitDate': nextVisitDate,
                        'medicines': medicinesWithDays,
                      });
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF2E7D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    child: const Text('登録する',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1976D2),
        foregroundColor: Colors.white,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('お薬手帳を登録',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            Text('${widget.patientName}さんの薬',
                style: const TextStyle(fontSize: 12, color: Colors.white70)),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 読み取り進捗
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_maxScans, (i) {
                final done = i < _scanned.length;
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 8),
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: done ? const Color(0xFF1976D2) : Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: done ? const Color(0xFF1976D2) : Colors.grey.shade300,
                      width: 2,
                    ),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 8)
                    ],
                  ),
                  child: Icon(
                    done ? Icons.check : Icons.qr_code_outlined,
                    color: done ? Colors.white : Colors.grey.shade400,
                    size: 28,
                  ),
                );
              }),
            ),
            const SizedBox(height: 12),

            // 状態テキスト
            Text(
              _scanned.isEmpty
                  ? '処方箋のQRコードを撮影してください'
                  : _scanned.length < _maxScans
                      ? '${_scanned.length}枚読み取り済み。続けて撮影するか「登録へ進む」を押してください'
                      : '${_scanned.length}枚すべて読み取り完了です',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 14, color: Colors.black54, height: 1.5),
            ),
            const SizedBox(height: 8),

            // エラー表示
            if (_lastError != null)
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.red.shade200),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.error_outline, color: Colors.red, size: 18),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(_lastError!,
                          style: const TextStyle(fontSize: 12, color: Colors.red)),
                    ),
                  ],
                ),
              ),

            const Spacer(),

            // OCR抽出結果プレビュー
            if (_ocrMedicines != null) ...[
              Container(
                padding: const EdgeInsets.all(14),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F5E9),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFF4CAF50)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.auto_awesome, color: Color(0xFF2E7D32), size: 18),
                        const SizedBox(width: 6),
                        const Text('AIが読み取った薬剤',
                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF2E7D32))),
                        const Spacer(),
                        GestureDetector(
                          onTap: () => setState(() => _ocrMedicines = null),
                          child: const Icon(Icons.close, size: 18, color: Colors.black38),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    ...(_ocrMedicines!).map((m) => Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: Text(
                        '・${m['name']}${(m['dosage'] as String).isNotEmpty ? '  ${m['dosage']}' : ''}${(m['frequency'] as String).isNotEmpty ? '  ${m['frequency']}' : ''}',
                        style: const TextStyle(fontSize: 13),
                      ),
                    )),
                  ],
                ),
              ),
            ],

            // 薬袋写真ボタン
            SizedBox(
              height: 52,
              child: OutlinedButton.icon(
                onPressed: (_isProcessing || _isOcrLoading) ? null : _pickPhoto,
                icon: _isOcrLoading
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.camera_alt_outlined),
                label: Text(
                  _isOcrLoading ? '解析中…' : '薬袋の写真から読み取る',
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF1976D2),
                  side: const BorderSide(color: Color(0xFF1976D2), width: 1.5),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // QRスキャンボタン（OCR読み取り済みでなければ表示）
            if (_ocrMedicines == null)
              SizedBox(
                height: 52,
                child: ElevatedButton.icon(
                  onPressed: (_isProcessing || _isOcrLoading || _scanned.length >= _maxScans)
                      ? null
                      : _shoot,
                  icon: const Icon(Icons.qr_code_scanner),
                  label: Text(
                    _scanned.isEmpty
                        ? 'QRコードをスキャンする'
                        : '続けてスキャンする（${_scanned.length}/$_maxScans）',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1976D2),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 2,
                  ),
                ),
              ),
            const SizedBox(height: 12),

            // 登録・リセットボタン
            Row(
              children: [
                if (_ocrMedicines != null || _scanned.isNotEmpty) ...[
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: (_isProcessing || _isOcrLoading)
                          ? null
                          : () => setState(() {
                                _scanned.clear();
                                _ocrMedicines = null;
                                _lastError = null;
                              }),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('やり直す'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey.shade600,
                        side: BorderSide(color: Colors.grey.shade300),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: (_isProcessing || _isOcrLoading) ? null : _register,
                      icon: const Icon(Icons.check, size: 18),
                      label: const Text('登録へ進む',
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        elevation: 2,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
