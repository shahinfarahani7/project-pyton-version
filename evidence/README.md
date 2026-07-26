# Release Evidence

`templates/` contains schema-valid examples only. They are intentionally expired and reference files that do not exist, so the production gate cannot accept them.

`actual/` is populated only by protected CI jobs, approved providers, tests, authorized signers, and controlled deployment workflows. The production gate rejects missing, placeholder, unsigned, expired, stale, out-of-order, hash-mismatched, wrong-commit, or wrong-release evidence.

The release manifest signature is anchored outside the manifest itself. The trusted public key SHA-256 value must come from the protected production CI environment as `COSIGN_TRUSTED_PUBLIC_KEY_SHA256`; it must match both the supplied public-key file and the signed `trustedRoots` attestation. A caller-supplied key cannot establish trust by itself.
