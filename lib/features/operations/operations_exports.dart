import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../sales/domain/sales_models.dart';

/// Acknowledges a manually entered ledger entry. Not proof of bank settlement.
Future<void> exportPaymentAcknowledgement({
  required String businessName,
  required String bookingId,
  required String entryId,
  required int amountPaisa,
  required String kind,
  required String method,
  required String reference,
  required DateTime timestamp,
}) async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: PdfPageFormat.a4,
      build: (_) => pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            businessName,
            style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 18),
          pw.Text(
            kind == 'refund'
                ? 'REFUND ACKNOWLEDGEMENT'
                : 'PAYMENT ACKNOWLEDGEMENT',
            style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 12),
          pw.Text('Booking: $bookingId'),
          pw.Text('Entry: $entryId'),
          pw.Text(
            'Date: ${timestamp.toLocal().toIso8601String().substring(0, 16)}',
          ),
          pw.Text('Amount: ${pkr(amountPaisa)}'),
          pw.Text('Method: $method'),
          pw.Text('Reference: $reference'),
          pw.SizedBox(height: 24),
          pw.Text(
            'Manually recorded in Caterer Pro. Verify the payment independently against bank or cash records.',
            style: const pw.TextStyle(fontSize: 10),
          ),
        ],
      ),
    ),
  );
  await Printing.layoutPdf(
    onLayout: (_) => pdf.save(),
    name: 'payment_$entryId.pdf',
  );
}

Future<void> exportPreparationSheet({
  required String businessName,
  required String bookingId,
  required String eventName,
  required DateTime eventDate,
  required int guests,
  required List<Map<String, String>> tasks,
}) async {
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (_) => [
        pw.Text(
          businessName,
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'EVENT PREPARATION SHEET',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          '$eventName | ${eventDate.toLocal().toIso8601String().substring(0, 10)} | $guests guests',
        ),
        pw.Text('Booking: $bookingId'),
        pw.SizedBox(height: 18),
        pw.TableHelper.fromTextArray(
          headers: ['Category', 'Task', 'Assigned to', 'Done'],
          data: tasks
              .map(
                (t) => [
                  t['category'] ?? '',
                  t['title'] ?? '',
                  t['assignee'] ?? '',
                  t['completed'] ?? '',
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 20),
        pw.Text(
          'Confirm ingredient quantities, staff, equipment and transport separately. This checklist is not an automatically calculated recipe requisition.',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
  await Printing.layoutPdf(
    onLayout: (_) => pdf.save(),
    name: 'preparation_$bookingId.pdf',
  );
}
