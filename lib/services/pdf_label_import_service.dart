import 'dart:js_interop';

/// 添付文書PDFの取り込み(管理画面の手動登録用)。
///
/// これまで手動登録は、管理者が添付文書PDFを別ウィンドウで開き、5つの入力欄へ
/// 該当章を1つずつ手で貼り付ける作業だった。PDFを選ぶだけで下書きが埋まるようにする。
///
/// 設計上の要点:
///   - **PDFはサーバーへ送らない**。テキスト抽出はブラウザ内(pdf.js)で完結し、
///     外へ出るのは抽出後のテキストだけ。医療情報が動く範囲を狭く保つ。
///   - **章の分割はここでやらない**。抽出したテキストはプロキシへ渡し、
///     自動取得と同じ `ChunkAttachmentDocument` で分割する。取り込み経路によって
///     同じ添付文書から違う結果が出る状態を作らないため。
///   - **抽出結果をそのまま保存しない**。画面に下書きとして出し、管理者が
///     確認・修正してから保存する(取りこぼしや誤検出が黙って通ると、
///     後段の注意点表示が間違ったまま動く)。
///
/// 実体は web/index.html の `pickAndExtractPdfText`。
@JS('pickAndExtractPdfText')
external JSPromise<JSAny?> _pickAndExtractPdfText();

class PickedPdfLabel {
  final String fileName;
  final String text;

  const PickedPdfLabel({required this.fileName, required this.text});
}

class PdfLabelImportService {
  /// PDFを選ばせ、テキストを抜き出して返す。選択がキャンセルされたら null。
  ///
  /// 抽出できたページが1つも無い(＝文字情報を持たないスキャン画像のPDF)場合は
  /// 空文字が返るため、呼び出し側で扱いを分けること。
  static Future<PickedPdfLabel?> pick() async {
    final result = await _pickAndExtractPdfText().toDart;
    if (result == null) return null;

    final map = result.dartify();
    if (map is! Map) return null;

    final text = map['text'];
    final fileName = map['fileName'];
    if (text is! String) return null;

    return PickedPdfLabel(
      fileName: fileName is String ? fileName : 'PDF',
      text: text,
    );
  }
}
