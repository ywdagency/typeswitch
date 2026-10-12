# TypeSwitch contributor instructions

TypeSwitch is an experimental, local-only macOS keyboard-layout utility. Read README.md and docs/architecture.md before changing behavior; docs/privacy.md and docs/compatibility.md describe privacy boundaries and verification limits.

Keep permission handling, event delivery, inference, context safety, rewrite, and UI separate. Preserve secure-input, password, terminal, ignored-app, stale-event, and ambiguous-token refusal paths. Accessibility is the primary rewrite mechanism; the existing bounded physical fallback must never become an unbounded or speculative rewrite path.

Do not add networking, telemetry, OCR, screen recording, clipboard-based text collection, or automatic learning without an explicit product decision. Never log raw typed text, replacement text, or learned words. Keep dictionary source attribution and source-specific licenses intact.

Use public Apple APIs. Verify platform-sensitive API changes against current Apple documentation. Run swift test after meaningful code changes and add focused tests for changed deterministic behavior. Automated tests do not substitute for the manual compatibility matrix. Do not claim a real-app result unless it was observed.

Keep local signing material, environment files, diagnostics, learned words, app bundles, and build outputs out of Git. Preserve unrelated working-tree changes. Documentation and code comments use English.
