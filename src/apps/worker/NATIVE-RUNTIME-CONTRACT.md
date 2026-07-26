# Native Runtime Contract

Android implementation uses an isolated foreground service, Android Keystore device key, Play Integrity verdict, encrypted checkpoint storage, WorkManager only for eligible scheduling, and a persistent user-visible notification. iOS uses Secure Enclave/App Attest and foreground or OS-granted BGProcessingTask. The Dart layer never receives raw private keys. Native inference adapters must verify model digest and signature before loading.
