# Changelog

## 1.2.0 - 2026-10-19

### Added
- 🎉 Updated official repository links to SofizPay organization (`SofizPay/sofizpay-dart-sdk`).
- ✅ Stellar utilities and transaction builder for payment processing.
- ✅ CIB and Edahabiya banking deposit integration.
- ✅ Support for latest Dart 3.x environment.

## 1.0.0 - 2025-01-16

### Added
- 🎉 Initial release of SofizPay SDK for Dart
- ✅ Payment submission functionality
- ✅ DZT balance checking
- ✅ Transaction history retrieval
- ✅ Real-time transaction monitoring with stream support
- ✅ Transaction search by memo
- ✅ Transaction lookup by hash
- ✅ Public key extraction from secret key
- ✅ Stream status monitoring
- ✅ Comprehensive error handling and validation
- ✅ Arabic documentation and examples
- ✅ Complete test suite with 17 passing tests
- ✅ Example application demonstrating all features

### Features
- **Stellar Integration**: Full integration with Stellar blockchain network
- **DZT Token Support**: Specialized support for DZT token transactions
- **Real-time Monitoring**: Background transaction monitoring with callbacks
- **Type Safety**: Strongly typed models and responses
- **Error Handling**: Comprehensive error handling with detailed messages
- **Documentation**: Extensive Arabic documentation with code examples

### Technical Details
- Dart SDK compatibility: ^3.4.4
- HTTP client with retry mechanism for reliability
- Streaming support for real-time transaction monitoring
- Mock implementations for testing and development
- Modular architecture with separate utilities and models

### API Methods
- `submit()` - Send payment transactions
- `getTransactions()` - Retrieve transaction history
- `getBalance()` - Get DZT token balance
- `getPublicKey()` - Extract public key from secret
- `searchTransactionsByMemo()` - Search transactions by memo
- `getTransactionByHash()` - Get transaction details by hash
- `startTransactionStream()` - Start real-time monitoring
- `stopTransactionStream()` - Stop real-time monitoring
- `getStreamStatus()` - Check monitoring status
- `getVersion()` - Get SDK version

### Dependencies
- `http: ^1.1.0` - HTTP client for Stellar API communication
- `crypto: ^3.0.3` - Cryptographic utilities
- `convert: ^3.1.1` - Data conversion utilities

### Development
- Comprehensive test suite
- Example application
- Arabic documentation
- MIT License
