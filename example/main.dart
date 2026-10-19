import 'package:sofizpay_dart_sdk/sofizpay_dart_sdk.dart';

void main() {
  // Initialize SofizPay SDK in sandbox mode
  final sdk = SofizPaySDK(isSandbox: true);
  print('SofizPay SDK Version: ${SofizPaySDK.version}');
  print('Sandbox Mode: ${sdk.isSandbox}');

  // Ready to use for Stellar payments, CIB bank card deposits, and transaction monitoring
  print('SDK initialized successfully!');
}
