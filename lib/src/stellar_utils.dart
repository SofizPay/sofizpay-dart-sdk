import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:ed25519_edwards/ed25519_edwards.dart' as ed;
import 'package:http/http.dart' as http;
import 'stellar_models.dart';

class StellarStrKey {
  static const String base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  static Uint8List decodeBase32(String input) {
    var clean = input.replaceAll('=', '').toUpperCase();
    var output = <int>[];
    var buffer = 0;
    var bitsLeft = 0;

    for (var i = 0; i < clean.length; i++) {
      var val = base32Alphabet.indexOf(clean[i]);
      if (val == -1) throw FormatException('Invalid Base32 character: ${clean[i]}');
      buffer = (buffer << 5) | val;
      bitsLeft += 5;
      if (bitsLeft >= 8) {
        bitsLeft -= 8;
        output.add((buffer >> bitsLeft) & 0xFF);
      }
    }
    return Uint8List.fromList(output);
  }

  static String encodeBase32(Uint8List bytes) {
    var output = StringBuffer();
    var buffer = 0;
    var bitsLeft = 0;

    for (var b in bytes) {
      buffer = (buffer << 8) | b;
      bitsLeft += 8;
      while (bitsLeft >= 5) {
        bitsLeft -= 5;
        output.write(base32Alphabet[(buffer >> bitsLeft) & 0x1F]);
      }
    }
    if (bitsLeft > 0) {
      buffer <<= (5 - bitsLeft);
      output.write(base32Alphabet[buffer & 0x1F]);
    }
    return output.toString();
  }

  static int crc16(Uint8List data) {
    var crc = 0x0000;
    for (var byte in data) {
      var code = (crc >> 8) & 0xFF;
      code ^= byte & 0xFF;
      code ^= code >> 4;
      crc = (crc << 8) & 0xFFFF;
      crc ^= code;
      code = (code << 5) & 0xFFFF;
      crc ^= code;
      code = (code << 7) & 0xFFFF;
      crc ^= code;
    }
    return crc & 0xFFFF;
  }

  static Uint8List decodeSecretSeed(String seedStr) {
    if (seedStr.length != 56 || !seedStr.startsWith('S')) {
      throw FormatException('Invalid secret seed format');
    }
    var decoded = decodeBase32(seedStr);
    if (decoded.length != 35) {
      throw FormatException('Invalid decoded length: ${decoded.length}');
    }
    var versionByte = decoded[0];
    if (versionByte != (18 << 3)) {
      throw FormatException('Invalid version byte: $versionByte');
    }
    var data = decoded.sublist(1, 33);
    var checksum = decoded[33] | (decoded[34] << 8);
    var calculated = crc16(decoded.sublist(0, 33));
    if (checksum != calculated) throw FormatException('Checksum mismatch');
    return data;
  }

  static Uint8List decodeAccountId(String accountId) {
    if (accountId.length != 56 || !accountId.startsWith('G')) {
      throw FormatException('Invalid account ID format');
    }
    var decoded = decodeBase32(accountId);
    if (decoded.length != 35) {
      throw FormatException('Invalid decoded length: ${decoded.length}');
    }
    var versionByte = decoded[0];
    if (versionByte != (6 << 3)) {
      throw FormatException('Invalid version byte: $versionByte');
    }
    var data = decoded.sublist(1, 33);
    var checksum = decoded[33] | (decoded[34] << 8);
    var calculated = crc16(decoded.sublist(0, 33));
    if (checksum != calculated) throw FormatException('Checksum mismatch');
    return data;
  }

  static String encodeAccountId(Uint8List publicKeyBytes) {
    var payload = Uint8List(35);
    payload[0] = 6 << 3; // 48 = 'G'
    payload.setRange(1, 33, publicKeyBytes);
    var crc = crc16(payload.sublist(0, 33));
    payload[33] = crc & 0xFF;
    payload[34] = (crc >> 8) & 0xFF;
    return encodeBase32(payload);
  }

  static String getPublicKeyFromSecret(String secretKey) {
    var seed = decodeSecretSeed(secretKey);
    var privateKey = ed.newKeyFromSeed(seed);
    var publicKey = ed.public(privateKey);
    return encodeAccountId(Uint8List.fromList(publicKey.bytes));
  }
}

class XdrWriter {
  final BytesBuilder _builder = BytesBuilder();

  void writeInt32(int value) {
    var b = ByteData(4)..setInt32(0, value, Endian.big);
    _builder.add(b.buffer.asUint8List());
  }

  void writeUint32(int value) {
    var b = ByteData(4)..setUint32(0, value, Endian.big);
    _builder.add(b.buffer.asUint8List());
  }

  void writeInt64(int value) {
    var b = ByteData(8)..setInt64(0, value, Endian.big);
    _builder.add(b.buffer.asUint8List());
  }

  void writeOpaque(Uint8List bytes) {
    _builder.add(bytes);
    var pad = (4 - (bytes.length % 4)) % 4;
    for (var i = 0; i < pad; i++) {
      _builder.addByte(0);
    }
  }

  void writeVarOpaque(Uint8List bytes) {
    writeUint32(bytes.length);
    writeOpaque(bytes);
  }

  void writeString(String str) {
    var bytes = utf8.encode(str);
    writeVarOpaque(Uint8List.fromList(bytes));
  }

  Uint8List toBytes() => _builder.toBytes();
}

class StellarTransactionBuilder {
  static const String publicNetworkPassphrase = StellarConfig.networkPassphrase;
  static const String assetCode = StellarConfig.assetCode;
  static const String assetIssuer = StellarConfig.assetIssuer;

  static Uint8List getNetworkId() {
    return Uint8List.fromList(crypto.sha256.convert(utf8.encode(publicNetworkPassphrase)).bytes);
  }

  static Future<Map<String, dynamic>> sendPayment({
    required String sourceKey,
    required String destinationPublicKey,
    required double amount,
    String? memo,
  }) async {
    final startTime = DateTime.now();
    try {
      if (sourceKey.isEmpty) throw Exception('Source key is required');
      if (destinationPublicKey.isEmpty) throw Exception('Destination public key is required');
      if (amount <= 0) throw Exception('Amount must be greater than 0');

      final sourceSeed = StellarStrKey.decodeSecretSeed(sourceKey);
      final privateKey = ed.newKeyFromSeed(sourceSeed);
      final publicKey = ed.public(privateKey);
      final sourceAccountId = StellarStrKey.encodeAccountId(Uint8List.fromList(publicKey.bytes));

      // 1. Load account sequence from Horizon
      final accountUrl = Uri.parse('${StellarConfig.horizonUrl}/accounts/$sourceAccountId');
      final accountRes = await http.get(accountUrl);
      if (accountRes.statusCode != 200) {
        throw Exception('Failed to load source account: ${accountRes.body}');
      }
      final accountData = jsonDecode(accountRes.body) as Map<String, dynamic>;
      final currentSeq = int.parse(accountData['sequence'].toString());
      final nextSeq = currentSeq + 1;

      // 2. Build Transaction XDR
      final txWriter = XdrWriter();
      // sourceAccount: MuxedAccount::ed25519 (0) + 32-byte public key
      txWriter.writeInt32(0);
      txWriter.writeOpaque(Uint8List.fromList(publicKey.bytes));
      // fee: 200 stroops
      txWriter.writeUint32(200);
      // seqNum: nextSeq
      txWriter.writeInt64(nextSeq);
      // timeBounds: 0 (none)
      txWriter.writeInt32(0);
      // memo
      if (memo != null && memo.isNotEmpty) {
        txWriter.writeInt32(1); // MEMO_TEXT
        txWriter.writeString(memo);
      } else {
        txWriter.writeInt32(0); // MEMO_NONE
      }
      // operations: 1 operation
      txWriter.writeUint32(1);
      // op sourceAccount: 0 (none)
      txWriter.writeInt32(0);
      // body: PAYMENT = 1
      txWriter.writeInt32(1);
      // destination: 0 (ed25519) + 32 bytes
      final destBytes = StellarStrKey.decodeAccountId(destinationPublicKey);
      txWriter.writeInt32(0);
      txWriter.writeOpaque(destBytes);
      // asset: ASSET_TYPE_CREDIT_ALPHANUM4 = 1
      txWriter.writeInt32(1);
      // 4-byte asset code
      var codeBytes = Uint8List(4);
      var rawCode = utf8.encode(assetCode);
      codeBytes.setRange(0, rawCode.length, rawCode);
      txWriter.writeOpaque(codeBytes);
      // issuer: 0 (ed25519) + 32 bytes
      final issuerBytes = StellarStrKey.decodeAccountId(assetIssuer);
      txWriter.writeInt32(0);
      txWriter.writeOpaque(issuerBytes);
      // amount in stroops: 1 DZT = 10,000,000 stroops
      final stroops = (amount * 10000000).round();
      txWriter.writeInt64(stroops);
      // ext: 0
      txWriter.writeInt32(0);

      final txBytes = txWriter.toBytes();

      // 3. Compute Transaction Hash for signature
      final sigPayloadWriter = XdrWriter();
      sigPayloadWriter.writeOpaque(getNetworkId());
      sigPayloadWriter.writeInt32(2); // ENVELOPE_TYPE_TX
      sigPayloadWriter.writeOpaque(txBytes);

      final txHash = Uint8List.fromList(crypto.sha256.convert(sigPayloadWriter.toBytes()).bytes);

      // 4. Sign with private key
      final sigBytes = Uint8List.fromList(ed.sign(privateKey, txHash));

      // 5. Build TransactionEnvelope XDR
      final envWriter = XdrWriter();
      envWriter.writeInt32(2); // ENVELOPE_TYPE_TX
      envWriter.writeOpaque(txBytes);
      // signatures array: length 1
      envWriter.writeUint32(1);
      // hint: last 4 bytes of public key
      final hint = Uint8List.fromList(publicKey.bytes.sublist(28, 32));
      envWriter.writeOpaque(hint);
      // signature bytes
      envWriter.writeVarOpaque(sigBytes);

      final envelopeBytes = envWriter.toBytes();
      final envelopeBase64 = base64Encode(envelopeBytes);

      // 6. Submit to Horizon
      final submitUrl = Uri.parse('${StellarConfig.horizonUrl}/transactions');
      final submitRes = await http.post(
        submitUrl,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {'tx': envelopeBase64},
      );

      final duration = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      final submitData = jsonDecode(submitRes.body) as Map<String, dynamic>;

      if (submitRes.statusCode == 200 && submitData['successful'] == true) {
        return {
          'success': true,
          'hash': submitData['hash'],
          'transaction_id': submitData['hash'],
          'transactionHash': submitData['hash'],
          'duration': duration,
        };
      } else {
        return {
          'success': false,
          'error': submitData['extras']?['result_codes']?.toString() ?? submitData['detail'] ?? submitRes.body,
          'duration': duration,
        };
      }
    } catch (e) {
      final duration = DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      return {
        'success': false,
        'error': e.toString(),
        'duration': duration,
      };
    }
  }
}

class StellarUtils {
  static Future<Map<String, dynamic>> sendPayment({
    required String sourceKey,
    required String destinationPublicKey,
    required double amount,
    String? memo,
  }) async {
    return StellarTransactionBuilder.sendPayment(
      sourceKey: sourceKey,
      destinationPublicKey: destinationPublicKey,
      amount: amount,
      memo: memo,
    );
  }

  static Future<double> getBalance(String publicKey) async {
    try {
      final url = '${StellarConfig.horizonUrl}/accounts/$publicKey';
      final account = await HttpUtil.fetchWithRetry(url);
      final balances = account['balances'] as List? ?? [];
      
      for (final balance in balances) {
        if (balance['asset_type'] != 'native' &&
            balance['asset_code'] == StellarConfig.assetCode &&
            balance['asset_issuer'] == StellarConfig.assetIssuer) {
          return double.tryParse(balance['balance'].toString()) ?? 0.0;
        }
      }
      return 0.0;
    } catch (error) {
      rethrow;
    }
  }

  static String getPublicKeyFromSecret(String secretKey) {
    if (secretKey.isEmpty) throw Exception('Secret key is required.');
    return StellarStrKey.getPublicKeyFromSecret(secretKey);
  }

  static Future<List<StellarTransaction>> getTransactions(
    String publicKey, {
    int limit = 200,
  }) async {
    try {
      final url = '${StellarConfig.horizonUrl}/accounts/$publicKey/operations?limit=$limit&order=desc&join=transactions';
      final response = await HttpUtil.fetchWithRetry(url);
      final records = response['_embedded']?['records'] as List? ?? [];
      final transactions = <StellarTransaction>[];

      for (final op in records) {
        final isPayment = op['type'] == 'payment' ||
            op['type'] == 'path_payment_strict_receive' ||
            op['type'] == 'path_payment_strict_send';
        
        if (isPayment &&
            op['asset_code'] == StellarConfig.assetCode &&
            op['asset_issuer'] == StellarConfig.assetIssuer) {
          
          final txMemo = op['transaction'] != null
              ? (op['transaction']['memo']?.toString() ?? '')
              : '';

          final transaction = StellarTransaction(
            id: op['transaction_hash']?.toString() ?? op['id']?.toString() ?? '',
            hash: op['transaction_hash']?.toString() ?? op['id']?.toString() ?? '',
            memo: txMemo,
            amount: double.tryParse(op['amount']?.toString() ?? '0') ?? 0.0,
            status: 'completed',
            sourceAccount: op['from']?.toString() ?? op['source_account']?.toString() ?? '',
            destination: op['to']?.toString() ?? '',
            assetCode: op['asset_code']?.toString() ?? '',
            assetIssuer: op['asset_issuer']?.toString() ?? '',
            createdAt: DateTime.tryParse(op['created_at']?.toString() ?? '') ?? DateTime.now(),
            processedAt: DateTime.now(),
            type: op['from'] == publicKey ? 'sent' : 'received',
          );
          
          transactions.add(transaction);
        }
      }

      return transactions;
    } catch (error) {
      rethrow;
    }
  }

  static Future<Map<String, dynamic>> getTransactionByHash(String transactionHash) async {
    if (transactionHash.isEmpty) {
      throw Exception('Transaction hash is required.');
    }

    try {
      final txUrl = '${StellarConfig.horizonUrl}/transactions/$transactionHash';
      final opUrl = '${StellarConfig.horizonUrl}/transactions/$transactionHash/operations';

      final transaction = await HttpUtil.fetchWithRetry(txUrl);
      final operations = await HttpUtil.fetchWithRetry(opUrl);
      final opRecords = operations['_embedded']?['records'] as List? ?? [];

      final formattedTransaction = {
        'id': transaction['id'],
        'hash': transaction['hash'],
        'ledger': transaction['ledger'],
        'created_at': transaction['created_at'],
        'source_account': transaction['source_account'],
        'source_account_sequence': transaction['source_account_sequence'],
        'fee_charged': transaction['fee_charged'],
        'operation_count': transaction['operation_count'],
        'memo': transaction['memo']?.toString() ?? '',
        'successful': transaction['successful'],
        'paging_token': transaction['paging_token'],
        'operations': <Map<String, dynamic>>[],
      };

      for (final op in opRecords) {
        if (op['type'] == 'payment') {
          final operation = {
            'id': op['id'],
            'type': 'payment',
            'created_at': op['created_at'],
            'transaction_hash': op['transaction_hash'],
            'source_account': op['source_account'],
            'from': op['from'],
            'to': op['to'],
            'amount': op['amount'],
            'asset_type': op['asset_type'],
            'asset_code': op['asset_code'],
            'asset_issuer': op['asset_issuer'],
          };
          
          (formattedTransaction['operations'] as List).add(operation);
        }
      }

      final sofizPayOperations = (formattedTransaction['operations'] as List).where((op) =>
        op['type'] == 'payment' &&
        op['asset_code'] == StellarConfig.assetCode &&
        op['asset_issuer'] == StellarConfig.assetIssuer
      ).toList();

      final primaryPaymentOperation = (formattedTransaction['operations'] as List).isNotEmpty 
          ? (formattedTransaction['operations'] as List).first 
          : null;
      
      if (primaryPaymentOperation != null) {
        formattedTransaction['amount'] = primaryPaymentOperation['amount'];
        formattedTransaction['from'] = primaryPaymentOperation['from'];
        formattedTransaction['to'] = primaryPaymentOperation['to'];
        formattedTransaction['asset_code'] = primaryPaymentOperation['asset_code'];
        formattedTransaction['asset_issuer'] = primaryPaymentOperation['asset_issuer'];
        formattedTransaction['operation_type'] = primaryPaymentOperation['type'];
      }

      return {
        'success': true,
        'found': true,
        'transaction': formattedTransaction,
        'has_operations': sofizPayOperations.isNotEmpty,
        'operations_count': sofizPayOperations.length,
        'payment_operations_count': (formattedTransaction['operations'] as List).length,
        'operations': sofizPayOperations,
        'hash': transactionHash,
        'message': 'Transaction found with ${(formattedTransaction['operations'] as List).length} payment operations (${sofizPayOperations.length} payments)',
      };

    } catch (error) {
      if (error.toString().contains('404')) {
        return {
          'success': true,
          'found': false,
          'message': 'Transaction not found on Stellar network',
          'hash': transactionHash,
          'error': 'Transaction does not exist',
        };
      }

      return {
        'success': false,
        'found': false,
        'message': 'Error while searching for transaction',
        'hash': transactionHash,
        'error': error.toString(),
      };
    }
  }
}
