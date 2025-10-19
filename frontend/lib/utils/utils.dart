// lib/utils/utils.dart
import 'package:flutter/material.dart';
import 'package:frontend/services/receipt_service.dart';

Future<void> shareReceiptByPaymentId(
  BuildContext context,
  int paymentId,
) async {
  await ReceiptService.shareReceiptByPaymentId(context, paymentId);
}
