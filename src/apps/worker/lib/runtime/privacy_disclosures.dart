abstract final class PrivacyDisclosures {
  static const resourceUse = '''
EdgeMint uses your device to run verified AI tasks while you are available.
Work runs in a visible foreground service with persistent status.
Inputs, checkpoints, and outputs are encrypted on device and deleted after submission.
''';

  static const rewardDisclosure = '''
Rewards accrue only after server verification. Estimated amounts are not guaranteed payouts.
''';

  static const dataHandling = '''
No raw private keys leave the device. Model artifacts are digest-pinned and signature verified before load.
''';

  static const all = [resourceUse, rewardDisclosure, dataHandling];
}
