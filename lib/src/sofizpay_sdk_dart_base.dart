import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'stellar_models.dart';
import 'stellar_utils.dart';

class SofizPayTransactionResponse {
  final bool success;
  final String? transactionHash;
  final double? amount;
  final String? memo;
  final String? destinationPublicKey;
  final double? duration;
  final String? error;
  final String timestamp;

  SofizPayTransactionResponse({
    required this.success,
    this.transactionHash,
    this.amount,
    this.memo,
    this.destinationPublicKey,
    this.duration,
    this.error,
  }) : timestamp = DateTime.now().toIso8601String();

  Map<String, dynamic> toJson() {
    return {
      'success': success,
      'transactionHash': transactionHash,
      'amount': amount,
      'memo': memo,
      'destinationPublicKey': destinationPublicKey,
      'duration': duration,
      'error': error,
      'timestamp': timestamp,
    };
  }
}

class SofizPaySDK {
  static const String version = '1.2.0';
  final bool isSandbox;

  static const String sofizpayPublicKeyPem = '''-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA1N+bDPxpqeB9QB0affr/
02aeRXAAnqHuLrgiUlVNdXtF7t+2w8pnEg+m9RRlc+4YEY6UyKTUjVe6k7v2p8Jj
UItk/fMNOEg/zY222EbqsKZ2mF4hzqgyJ3QHPXjZEEqABkbcYVv4ZyV2Wq0x0ykI
+Hy/5YWKeah4RP2uEML1FlXGpuacnMXpW6n36dne3fUN+OzILGefeRpmpnSGO5+i
JmpF2mRdKL3hs9WgaLSg6uQyrQuJA9xqcCpUmpNbIGYXN9QZxjdyRGnxivTE8awx
THV3WRcKrP2krz3ruRGF6yP6PVHEuPc0YDLsYjV5uhfs7JtIksNKhRRAQ16bAsj/
9wIDAQAB
-----END PUBLIC KEY-----''';
  
  final Map<String, Map<String, dynamic>> _activeStreams = {};
  final Map<String, Function(StellarTransaction)> _transactionCallbacks = {};
  final Map<String, Timer> _pollingTimers = {};
  final Map<String, Set<String>> _seenTransactionHashes = {};

  SofizPaySDK({this.isSandbox = false});

  Future<SofizPayTransactionResponse> submit({
    required String secretkey,
    required String destinationPublicKey,
    required double amount,
    required String memo,
  }) async {
    try {
      if (secretkey.isEmpty) {
        throw Exception('Secret key is required.');
      }
      if (destinationPublicKey.isEmpty) {
        throw Exception('Destination public key is required.');
      }
      if (amount <= 0) {
        throw Exception('Valid amount is required.');
      }
      if (memo.isEmpty) {
        throw Exception('Memo is required.');
      }

      final result = await StellarUtils.sendPayment(
        sourceKey: secretkey,
        destinationPublicKey: destinationPublicKey,
        amount: amount,
        memo: memo,
      );

      if (result['success'] == true) {
        return SofizPayTransactionResponse(
          success: true,
          transactionHash: result['hash'],
          amount: amount,
          memo: memo,
          destinationPublicKey: destinationPublicKey,
          duration: result['duration'],
        );
      } else {
        throw Exception(result['error'] ?? 'Transaction failed');
      }
    } catch (error) {
      return SofizPayTransactionResponse(
        success: false,
        error: error.toString(),
      );
    }
  }

  Future<Map<String, dynamic>> getTransactions(
    String publicKey, {
    int limit = 50,
  }) async {
    if (publicKey.isEmpty) {
      throw Exception('Public key is required.');
    }

    final transactions = await StellarUtils.getTransactions(
      publicKey,
      limit: limit,
    );

    final formattedTransactions = transactions.map((tx) => {
      'id': tx.hash,
      'hash': tx.hash,
      'amount': tx.amount,
      'memo': tx.memo,
      'type': tx.type,
      'from': tx.sourceAccount,
      'to': tx.destination,
      'asset_code': tx.assetCode,
      'asset_issuer': tx.assetIssuer,
      'status': 'completed',
      'timestamp': tx.createdAt.toIso8601String(),
      'created_at': tx.createdAt.toIso8601String(),
    }).toList();

    return {
      'transactions': formattedTransactions,
      'total': formattedTransactions.length,
      'publicKey': publicKey,
      'message': 'All transactions fetched (${formattedTransactions.length} transactions)',
    };
  }

  Future<Map<String, dynamic>> getBalance(String publicKey) async {
    if (publicKey.isEmpty) {
      throw Exception('Public key is required.');
    }

    final balance = await StellarUtils.getBalance(publicKey);

    return {
      'balance': balance,
      'publicKey': publicKey,
      'asset_code': StellarConfig.assetCode,
      'asset_issuer': StellarConfig.assetIssuer,
    };
  }

  String getPublicKey(String secretkey) {
    if (secretkey.isEmpty) {
      throw Exception('Secret key is required.');
    }

    return StellarUtils.getPublicKeyFromSecret(secretkey);
  }


  Future<Map<String, dynamic>> searchTransactionsByMemo(
    String publicKey,
    String memo, {
    int limit = 50,
  }) async {
    if (publicKey.isEmpty) {
      throw Exception('Public key is required.');
    }
    if (memo.isEmpty) {
      throw Exception('Memo is required for search.');
    }

    final transactions = await StellarUtils.getTransactions(publicKey, limit: 200);

    final filteredTransactions = transactions.where((tx) {
      return tx.memo.toLowerCase().contains(memo.toLowerCase());
    }).take(limit).toList();

    final formattedTransactions = filteredTransactions.map((tx) => {
      'id': tx.hash,
      'hash': tx.hash,
      'amount': tx.amount,
      'memo': tx.memo,
      'type': tx.type,
      'from': tx.sourceAccount,
      'to': tx.destination,
      'asset_code': tx.assetCode,
      'asset_issuer': tx.assetIssuer,
      'status': 'completed',
      'timestamp': tx.createdAt.toIso8601String(),
      'created_at': tx.createdAt.toIso8601String(),
    }).toList();

    return {
      'transactions': formattedTransactions,
      'total': formattedTransactions.length,
      'totalFound': filteredTransactions.length,
      'searchMemo': memo,
      'publicKey': publicKey,
      'message': '${filteredTransactions.length} transactions found containing "$memo"',
    };
  }

  Future<Map<String, dynamic>> getTransactionByHash(String transactionHash) async {
    if (transactionHash.isEmpty) {
      throw Exception('Transaction hash is required.');
    }

    final result = await StellarUtils.getTransactionByHash(transactionHash);

    if (result['success'] == true && result['found'] == true) {
      return {
        'found': true,
        'transaction': result['transaction'],
        'has_operations': result['has_operations'],
        'operations_count': result['operations_count'],
        'operations': result['operations'],
        'hash': transactionHash,
        'message': result['message'],
      };
    } else {
      return {
        'found': false,
        'transaction': null,
        'hash': transactionHash,
        'message': result['message'] ?? 'Transaction not found',
        'error': result['error'],
      };
    }
  }

  Future<Map<String, dynamic>> makeCIBTransaction(Map<String, dynamic> transactionData) async {
    if (!transactionData.containsKey('account') || transactionData['account'] == null || transactionData['account'].toString().isEmpty) {
      throw Exception('Account is required.');
    }
    if (!transactionData.containsKey('amount') || transactionData['amount'] == null || double.tryParse(transactionData['amount'].toString()) == null || double.parse(transactionData['amount'].toString()) <= 0) {
      throw Exception('Valid amount is required.');
    }
    if (!transactionData.containsKey('full_name') || transactionData['full_name'] == null || transactionData['full_name'].toString().isEmpty) {
      throw Exception('Full name is required.');
    }
    if (!transactionData.containsKey('phone') || transactionData['phone'] == null || transactionData['phone'].toString().isEmpty) {
      throw Exception('Phone number is required.');
    }
    if (!transactionData.containsKey('email') || transactionData['email'] == null || transactionData['email'].toString().isEmpty) {
      throw Exception('Email is required.');
    }

    final bool useSandbox = (transactionData['is_sandbox'] ?? transactionData['isSandbox'] ?? isSandbox) == true;
    final String baseUrl = useSandbox
        ? 'https://sofizpay.com/sandbox/make-cib-transaction/'
        : 'https://www.sofizpay.com/make-cib-transaction/';
    
    List<String> queryParams = [];
    queryParams.add('account=${Uri.encodeComponent(transactionData['account'].toString())}');
    queryParams.add('amount=${transactionData['amount']}');
    queryParams.add('full_name=${Uri.encodeComponent(transactionData['full_name'].toString())}');
    queryParams.add('phone=${Uri.encodeComponent(transactionData['phone'].toString())}');
    queryParams.add('email=${Uri.encodeComponent(transactionData['email'].toString())}');
    
    if (transactionData.containsKey('return_url') && transactionData['return_url'] != null) {
      queryParams.add('return_url=${Uri.encodeComponent(transactionData['return_url'].toString())}');
    }
    if (transactionData.containsKey('webhook_url') && transactionData['webhook_url'] != null) {
      queryParams.add('webhook_url=${Uri.encodeComponent(transactionData['webhook_url'].toString())}');
    }
    if (transactionData.containsKey('invoice_id') && transactionData['invoice_id'] != null) {
      queryParams.add('invoice_id=${Uri.encodeComponent(transactionData['invoice_id'].toString())}');
    }
    if (transactionData.containsKey('language') && transactionData['language'] != null) {
      queryParams.add('language=${Uri.encodeComponent(transactionData['language'].toString())}');
    }
    if (transactionData.containsKey('memo') && transactionData['memo'] != null) {
      final safeMemo = Uri.encodeComponent(transactionData['memo'].toString());
      queryParams.add('memo=$safeMemo');
    }
    if (transactionData.containsKey('redirect')) {
      final r = transactionData['redirect'];
      final redirectVal = (r == true || r == 'yes') ? 'yes' : 'no';
      queryParams.add('redirect=$redirectVal');
    } else {
      queryParams.add('redirect=no');
    }
    if (transactionData.containsKey('keep_return_url')) {
      final k = transactionData['keep_return_url'];
      final kVal = (k == true || k == 'True') ? 'True' : 'False';
      queryParams.add('keep_return_url=$kVal');
    }

    final String fullUrl = '$baseUrl?${queryParams.join('&')}';
    
    final response = await HttpUtil.fetchWithRetry(fullUrl);

    final paymentUrl = response['payment_url'] ?? (response['cib_response'] is Map ? response['cib_response']['formUrl'] : null);
    final isOk = response['status'] != 'error' && response['success'] != false;

    return {
      'success': isOk,
      'data': response,
      'payment_url': paymentUrl,
      'transaction_id': response['transaction_id'],
      'cib_transaction_id': response['cib_transaction_id'],
      'order_id': response['order_id'],
      'webhook_url': response['webhook_url'] ?? transactionData['webhook_url'],
      'account': transactionData['account'],
      'amount': transactionData['amount'],
      'full_name': transactionData['full_name'],
      'phone': transactionData['phone'],
      'email': transactionData['email'],
      'memo': transactionData['memo'],
      'is_sandbox': useSandbox,
      'timestamp': DateTime.now().toIso8601String(),
      'url': fullUrl,
    };
  }

  Future<Map<String, dynamic>> makeSandboxCIBTransaction(Map<String, dynamic> transactionData) async {
    final data = Map<String, dynamic>.from(transactionData);
    data['is_sandbox'] = true;
    return makeCIBTransaction(data);
  }

  Future<Map<String, dynamic>> checkCIBStatus(String cibTransactionId, {bool? isSandbox}) async {
    final bool useSandbox = (isSandbox ?? this.isSandbox) == true;
    final String baseUrl = useSandbox
        ? 'https://sofizpay.com/sandbox/cib-transaction-check/'
        : 'https://www.sofizpay.com/cib-transaction-check/';
    final String url = '$baseUrl?order_number=${Uri.encodeComponent(cibTransactionId)}';
    try {
      final response = await HttpUtil.fetchWithRetry(url);
      return {
        'success': true,
        'data': response,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  Future<Map<String, dynamic>> checkSandboxCIBStatus(String cibTransactionId) async {
    return checkCIBStatus(cibTransactionId, isSandbox: true);
  }

  Future<Map<String, dynamic>> getProducts([String? encryptedSecretKey]) async {
    try {
      final url = Uri.parse('https://sofizpay.com/services/get_products/');
      final headers = {
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };
      http.Response response;
      if (encryptedSecretKey != null && encryptedSecretKey.isNotEmpty) {
        final request = http.Request('GET', url);
        request.headers.addAll(headers);
        request.body = json.encode({'encrypted_sk': encryptedSecretKey});
        final streamed = await request.send();
        response = await http.Response.fromStream(streamed);
      } else {
        response = await http.get(url, headers: headers);
      }
      
      final parsed = json.decode(response.body);
      return {
        'success': response.statusCode == 200,
        'data': parsed,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  Future<Map<String, dynamic>> rechargePhone(Map<String, dynamic> data) async {
    return _performServiceOperation(data);
  }

  Future<Map<String, dynamic>> rechargeInternet(Map<String, dynamic> data) async {
    return _performServiceOperation(data);
  }

  Future<Map<String, dynamic>> rechargeGame(Map<String, dynamic> data) async {
    return _performServiceOperation(data);
  }

  Future<Map<String, dynamic>> payBill(Map<String, dynamic> data) async {
    return _performServiceOperation(data);
  }

  Future<Map<String, dynamic>> _performServiceOperation(Map<String, dynamic> data) async {
    try {
      final response = await HttpUtil.postWithRetry(
        'https://www.sofizpay.com/services/operation_post',
        data,
      );
      return {
        'success': true,
        'data': response,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  Future<Map<String, dynamic>> getOperationHistory(
    String encryptedSecretKey, {
    int limit = 10,
    int offset = 0,
  }) async {
    try {
      final url = 'https://sofizpay.com/services/operation-history/?encrypted_sk=${Uri.encodeComponent(encryptedSecretKey)}&limit=$limit&offset=$offset';
      final response = await HttpUtil.fetchWithRetry(url);
      return {
        'success': true,
        'data': response,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  Future<Map<String, dynamic>> getOperationDetails(
    String operationId,
    String encryptedSecretKey,
  ) async {
    try {
      final url = 'https://sofizpay.com/services/operation-detail/$operationId/?encrypted_sk=${Uri.encodeComponent(encryptedSecretKey)}';
      final response = await HttpUtil.fetchWithRetry(url);
      return {
        'success': true,
        'data': response,
        'timestamp': DateTime.now().toIso8601String(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': e.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      };
    }
  }

  bool verifySignature(dynamic verificationData, [String? signature]) {
    String message = '';
    String sig = '';

    if (verificationData is String) {
      message = verificationData;
      sig = signature ?? '';
    } else if (verificationData is Map) {
      message = verificationData['message']?.toString() ?? '';
      sig = (verificationData['signature_url_safe'] ?? verificationData['signature'])?.toString() ?? '';
    }

    if (message.isEmpty || sig.isEmpty) {
      return false;
    }

    try {
      final keyInfo = _parseRsaPublicKey(sofizpayPublicKeyPem);
      if (keyInfo == null) return false;
      final BigInt n = keyInfo['n']!;
      final BigInt e = keyInfo['e']!;

      String base64Sig = sig.replaceAll('-', '+').replaceAll('_', '/');
      while (base64Sig.length % 4 != 0) {
        base64Sig += '=';
      }

      final Uint8List sigBytes = base64.decode(base64Sig);
      final BigInt sigBigInt = _bytesToBigInt(sigBytes);

      final BigInt decrypted = sigBigInt.modPow(e, n);

      final Uint8List decryptedBytes = Uint8List(256);
      BigInt temp = decrypted;
      for (int i = 255; i >= 0; i--) {
        decryptedBytes[i] = (temp & BigInt.from(0xff)).toInt();
        temp = temp >> 8;
      }

      if (decryptedBytes[0] != 0x00 || decryptedBytes[1] != 0x01) {
        return false;
      }

      int delimiterIndex = 2;
      while (delimiterIndex < decryptedBytes.length && decryptedBytes[delimiterIndex] == 0xff) {
        delimiterIndex++;
      }

      if (delimiterIndex < 10 || delimiterIndex >= decryptedBytes.length || decryptedBytes[delimiterIndex] != 0x00) {
        return false;
      }

      const List<int> sha256DigestInfoPrefix = [
        0x30, 0x31, 0x30, 0x0d, 0x06, 0x09, 0x60, 0x86, 0x48, 0x01, 0x65, 0x03, 0x04, 0x02, 0x01, 0x05, 0x00, 0x04, 0x20
      ];

      final payloadBytes = decryptedBytes.sublist(delimiterIndex + 1);
      if (payloadBytes.length != sha256DigestInfoPrefix.length + 32) {
        return false;
      }

      for (int i = 0; i < sha256DigestInfoPrefix.length; i++) {
        if (payloadBytes[i] != sha256DigestInfoPrefix[i]) return false;
      }

      final decryptedHash = payloadBytes.sublist(sha256DigestInfoPrefix.length);
      final expectedHash = sha256.convert(utf8.encode(message)).bytes;

      for (int i = 0; i < 32; i++) {
        if (decryptedHash[i] != expectedHash[i]) return false;
      }

      return true;
    } catch (_) {
      return false;
    }
  }

  bool verifyWebhookSignature(Map<String, dynamic> webhookPayload) {
    return verifySignature(webhookPayload);
  }

  static Map<String, BigInt>? _parseRsaPublicKey(String pem) {
    try {
      final clean = pem
          .replaceAll('-----BEGIN PUBLIC KEY-----', '')
          .replaceAll('-----END PUBLIC KEY-----', '')
          .replaceAll(RegExp(r'\s'), '');
      final der = base64.decode(clean);
      
      int offset = 0;
      if (der[offset++] != 0x30) return null;
      offset = _skipLength(der, offset);
      
      if (der[offset++] != 0x30) return null;
      int algLen = _readLength(der, offset);
      offset = _skipLength(der, offset) + algLen;
      
      if (der[offset++] != 0x03) return null;
      offset = _skipLength(der, offset);
      offset++;
      
      if (der[offset++] != 0x30) return null;
      offset = _skipLength(der, offset);
      
      if (der[offset++] != 0x02) return null;
      int modLen = _readLength(der, offset);
      offset = _skipLength(der, offset);
      final modBytes = der.sublist(offset, offset + modLen);
      offset += modLen;
      
      if (der[offset++] != 0x02) return null;
      int expLen = _readLength(der, offset);
      offset = _skipLength(der, offset);
      final expBytes = der.sublist(offset, offset + expLen);
      
      BigInt n = _bytesToBigInt(modBytes);
      BigInt e = _bytesToBigInt(expBytes);
      
      return {'n': n, 'e': e};
    } catch (_) {
      return null;
    }
  }

  static int _skipLength(Uint8List bytes, int offset) {
    if ((bytes[offset] & 0x80) == 0) {
      return offset + 1;
    }
    int numBytes = bytes[offset] & 0x7f;
    return offset + 1 + numBytes;
  }

  static int _readLength(Uint8List bytes, int offset) {
    if ((bytes[offset] & 0x80) == 0) {
      return bytes[offset];
    }
    int numBytes = bytes[offset] & 0x7f;
    int len = 0;
    for (int i = 0; i < numBytes; i++) {
      len = (len << 8) | bytes[offset + 1 + i];
    }
    return len;
  }

  static BigInt _bytesToBigInt(Uint8List bytes) {
    BigInt result = BigInt.zero;
    for (int b in bytes) {
      result = (result << 8) | BigInt.from(b);
    }
    return result;
  }

  String getVersion() {
    return version;
  }

  Future<SofizPayTransactionResponse> sendPayment({
    required String secretkey,
    required String destinationPublicKey,
    required double amount,
    required String memo,
  }) async {
    return submit(
      secretkey: secretkey,
      destinationPublicKey: destinationPublicKey,
      amount: amount,
      memo: memo,
    );
  }

  void dispose() {
    // إيقاف جميع timers
    for (final timer in _pollingTimers.values) {
      timer.cancel();
    }
    
    // تنظيف جميع البيانات
    _pollingTimers.clear();
    _activeStreams.clear();
    _transactionCallbacks.clear();
    _seenTransactionHashes.clear();
  }
}

/// Backward compatibility typedef
typedef SofizPay = SofizPaySDK;

