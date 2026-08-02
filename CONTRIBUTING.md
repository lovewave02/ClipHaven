# Contributing

Thank you for considering a contribution. Keep changes focused, preserve ClipHaven's local-only clipboard privacy model, and do not add network, account, analytics, synchronization, or publishing behavior without an explicit project decision.

## Local checks

Run these commands from a repository checkout before proposing a change:

```sh
swift build
swift test
./scripts/verify-cleanroom-contract.sh
```

For changes that affect the history UI, shortcut, or automatic paste, also run:

```sh
./scripts/e2e-textedit-autopaste.sh
```

Do not include real clipboard data, credentials, or personal information in tests, fixtures, screenshots, or issue discussions. This project currently has no contributor license agreement and makes no ownership claim through this guide.
