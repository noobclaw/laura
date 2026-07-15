import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:share_plus/share_plus.dart';

import 'geo_format.dart';
import 'models.dart';
import 'store.dart';

/// Build a CSV ledger of the given photos.
String buildCsv(List<StampPhoto> photos, FieldStampStore store) {
  final rows = <String>[
    'file,project,timestamp,latitude,longitude,altitude_m,accuracy_m,heading_deg,note',
  ];
  for (final p in photos) {
    rows.add([
      p.fileName,
      csvField(store.projectName(p.projectId)),
      formatTimestamp(p.capturedAt),
      p.latitude?.toStringAsFixed(6) ?? '',
      p.longitude?.toStringAsFixed(6) ?? '',
      p.altitude?.toStringAsFixed(1) ?? '',
      p.accuracy?.toStringAsFixed(1) ?? '',
      p.heading?.toStringAsFixed(0) ?? '',
      csvField(p.note),
    ].join(','));
  }
  return rows.join('\n');
}

/// Build a one-photo-per-page PDF inspection report.
Future<Uint8List> buildPdf(
    List<StampPhoto> photos, FieldStampStore store) async {
  final doc = pw.Document();
  for (final p in photos) {
    Uint8List? thumb;
    try {
      final file = File(store.photoPath(p.fileName));
      if (await file.exists()) {
        final bytes = await file.readAsBytes();
        thumb = await compute(_downscaleJpg, bytes);
      }
    } catch (_) {}

    doc.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (ctx) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Text(
              store.projectName(p.projectId),
              style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
            ),
            pw.SizedBox(height: 8),
            if (thumb != null)
              pw.Center(
                child: pw.Image(pw.MemoryImage(thumb),
                    height: 380, fit: pw.BoxFit.contain),
              )
            else
              pw.Container(
                height: 200,
                alignment: pw.Alignment.center,
                child: pw.Text('(image unavailable)',
                    style: const pw.TextStyle(color: PdfColors.grey)),
              ),
            pw.SizedBox(height: 12),
            pw.Table(
              border: pw.TableBorder.all(color: PdfColors.grey400, width: 0.5),
              columnWidths: const {
                0: pw.FixedColumnWidth(120),
                1: pw.FlexColumnWidth(),
              },
              children: [
                _row('Timestamp', formatTimestamp(p.capturedAt)),
                _row('Coordinates',
                    formatLatLon(p.latitude, p.longitude, store.coordFormat)),
                _row('Altitude', formatAltitude(p.altitude, store.altUnit)),
                _row('Bearing', formatHeading(p.heading)),
                _row('GPS accuracy',
                    p.accuracy != null ? '±${p.accuracy!.toStringAsFixed(0)} m' : '—'),
                if (p.note.isNotEmpty) _row('Note', p.note),
                _row('File', p.fileName),
              ],
            ),
            pw.Spacer(),
            pw.Text(
              'Generated offline by FieldStamp — this data never left the device.',
              style: pw.TextStyle(fontSize: 8, color: PdfColors.grey600),
            ),
          ],
        ),
      ),
    );
  }
  return doc.save();
}

pw.TableRow _row(String k, String v) => pw.TableRow(children: [
      pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(k,
            style: pw.TextStyle(fontWeight: pw.FontWeight.bold, fontSize: 10)),
      ),
      pw.Padding(
        padding: const pw.EdgeInsets.all(5),
        child: pw.Text(v, style: const pw.TextStyle(fontSize: 10)),
      ),
    ]);

/// Downscale a JPEG for embedding in the PDF so the report stays small.
Uint8List _downscaleJpg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final resized =
      decoded.width > 1200 ? img.copyResize(decoded, width: 1200) : decoded;
  return img.encodeJpg(resized, quality: 80);
}

/// Write [data] to a temp file and open the native share sheet.
Future<void> shareBytes(Uint8List data, String fileName, {String? text}) async {
  final dir = await getTemporaryDirectory();
  final f = File('${dir.path}/$fileName');
  await f.writeAsBytes(data, flush: true);
  await SharePlus.instance
      .share(ShareParams(files: [XFile(f.path)], text: text));
}

/// Share the raw stamped JPEG files (the watermark is already burned in).
Future<void> sharePhotos(
    List<StampPhoto> photos, FieldStampStore store) async {
  final files = <XFile>[];
  for (final p in photos) {
    final path = store.photoPath(p.fileName);
    if (await File(path).exists()) files.add(XFile(path));
  }
  if (files.isEmpty) return;
  await SharePlus.instance.share(ShareParams(files: files));
}
