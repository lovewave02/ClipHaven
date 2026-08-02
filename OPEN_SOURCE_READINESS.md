# Open-source readiness

ClipHaven is licensed under `LGPL-2.1-only`. The owner must still review the staged files and complete the required checks before each public release.

## Dependency and secret review

- The Swift package declares no third-party Swift package dependencies.
- Only local, standard secret-pattern scanning has been performed. It is not a guarantee that secrets, sensitive data, or clipboard content are absent.
- The application intentionally stores supported clipboard entries and source-app identifiers in an unencrypted local JSON file. A public release must keep this limitation accurately disclosed in the README and security policy.

## Required pre-release checks

Before any public release, inspect the staged files and run the following from the repository checkout:

```sh
swift build
swift test
./scripts/e2e-textedit-autopaste.sh
./scripts/verify-cleanroom-contract.sh
```

Review the results and staged-file list before proceeding. Keep the root `LICENSE` file unchanged unless the owner makes a new license decision.
