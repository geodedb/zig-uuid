# uuid Documentation

## Overview

A fully RFC-9562-compliant UUID library for Zig. Supports V1, V3, V4, V5, V6, V7, V8
with an injectable generator, cross-platform MAC resolution, and multiple parse/format modes.

## Quick Links

- [Installation](../README.md#installation)
- [Quick Start](../README.md#quick-start)
- [Gap Analyses](GAP_ANALYSIS.md) — RFC-9562, security, performance, and quality reviews
- [AppSec Review 2026-06-11](APPSEC_REVIEW_2026-06-11.md) — OWASP 2025 + CIS v8.1.2 defensive code review
- [Security Review Notes](SECURITY_REVIEW_NOTES.md) — running ledger of all security review cycles
- [Contributing](../CONTRIBUTING.md)
- [Security](../SECURITY.md)
- [Changelog](../CHANGELOG.md)

## API Overview

See `src/root.zig` for all public exports. Key entry points:

- `uuid.newV7()` — recommended: k-sortable timestamp UUID
- `uuid.newV4()` — random UUID
- `uuid.newV1()` / `uuid.newV6()` — legacy timestamp UUIDs
- `uuid.UUID.fromString(s)` — parse any supported format
- `uuid.Generator` — injectable generator for testing and custom node IDs
