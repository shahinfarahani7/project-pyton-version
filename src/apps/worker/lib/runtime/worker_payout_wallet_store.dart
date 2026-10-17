import 'dart:convert';

import 'encrypted_store.dart';

const _storageKey = 'worker_payout_wallets_v1';

enum WorkerPayoutWalletKind { cryptoUsdtTrc20, ibanEur, other }

extension WorkerPayoutWalletKindLabels on WorkerPayoutWalletKind {
  String get label => switch (this) {
    WorkerPayoutWalletKind.cryptoUsdtTrc20 => 'USDT (TRC20)',
    WorkerPayoutWalletKind.ibanEur => 'Bank account (IBAN)',
    WorkerPayoutWalletKind.other => 'Other payout destination',
  };
}

class WorkerPayoutWalletRecord {
  const WorkerPayoutWalletRecord({
    required this.id,
    required this.kind,
    required this.label,
    required this.destination,
    required this.savedAtUtc,
  });

  factory WorkerPayoutWalletRecord.fromJson(Map<String, dynamic> json) {
    return WorkerPayoutWalletRecord(
      id: json['id'] as String,
      kind: WorkerPayoutWalletKind.values.byName(json['kind'] as String),
      label: json['label'] as String,
      destination: json['destination'] as String,
      savedAtUtc: DateTime.parse(json['savedAtUtc'] as String),
    );
  }

  final String id;
  final WorkerPayoutWalletKind kind;
  final String label;
  final String destination;
  final DateTime savedAtUtc;

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind.name,
    'label': label,
    'destination': destination,
    'savedAtUtc': savedAtUtc.toUtc().toIso8601String(),
  };

  String get maskedDestination {
    final trimmed = destination.trim();
    if (trimmed.length <= 8) {
      return '••••';
    }
    return '${trimmed.substring(0, 4)}…${trimmed.substring(trimmed.length - 4)}';
  }
}

class WorkerPayoutWalletStore {
  WorkerPayoutWalletStore(this._store);

  final EncryptedStore _store;

  Future<List<WorkerPayoutWalletRecord>> readAll() async {
    final bytes = await _store.read(_storageKey);
    if (bytes == null || bytes.isEmpty) {
      return [];
    }
    final decoded = jsonDecode(utf8.decode(bytes));
    if (decoded is! List) {
      return [];
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) =>
              WorkerPayoutWalletRecord.fromJson(item.cast<String, dynamic>()),
        )
        .toList();
  }

  Future<void> writeAll(List<WorkerPayoutWalletRecord> wallets) async {
    final encoded = jsonEncode(wallets.map((w) => w.toJson()).toList());
    await _store.write(_storageKey, utf8.encode(encoded));
  }
}
