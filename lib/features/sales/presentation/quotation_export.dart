import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../domain/sales_models.dart';

Future<void> exportQuotation(
  String businessName,
  SalesRecord quote,
  SalesRecord revision,
  List<QuoteLine> lines,
) async {
  final document = pw.Document();
  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      build: (context) => [
        pw.Text(
          businessName,
          style: pw.TextStyle(fontSize: 22, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'CATERING QUOTATION',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Reference: ${quote.id} | Revision: ${quote.number('revision')}',
        ),
        pw.Text(
          'Event: ${quote.str('eventType')} | Guests: ${quote.number('guests')}',
        ),
        pw.SizedBox(height: 14),
        pw.TableHelper.fromTextArray(
          headers: ['Item', 'Qty', 'Unit PKR', 'Total PKR'],
          data: lines
              .map(
                (l) => [
                  l.title,
                  '${l.quantity}',
                  pkr(l.unitPaisa),
                  pkr(l.total),
                ],
              )
              .toList(),
        ),
        pw.SizedBox(height: 16),
        pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              pw.Text('Subtotal: ${pkr(revision.number('subtotalPaisa'))}'),
              pw.Text('Extras: ${pkr(revision.number('extraPaisa'))}'),
              pw.Text('Discount: ${pkr(revision.number('discountPaisa'))}'),
              pw.Text(
                'TOTAL: ${pkr(quote.number('totalPaisa'))}',
                style: pw.TextStyle(
                  fontSize: 16,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(height: 14),
        pw.Text(revision.str('notes')),
        pw.SizedBox(height: 20),
        pw.Text(
          'This is a quotation, not a confirmed booking or receipt.',
          style: const pw.TextStyle(fontSize: 10),
        ),
      ],
    ),
  );
  await Printing.layoutPdf(
    onLayout: (_) => document.save(),
    name: 'catering_quote_${quote.id}_rev${quote.number('revision')}.pdf',
  );
}
