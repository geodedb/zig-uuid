# Requirements

Last updated: 2026-03-21

## Scope

This repository owns the reusable UUID core extracted from Geode. It does not own Geode graph-registry persistence, graph-store file naming, or other product-specific UUID consumers.

## Functional Requirements

| ID | Requirement | Geode evidence |
|---|---|---|
| UUID-REQ-001 | The library SHALL expose UUIDv7 generation. | `src/uuid.zig:5`, `:11` |
| UUID-REQ-002 | The library SHALL expose parsing from bytes and canonical string form. | `src/uuid.zig:38`, `:43` |
| UUID-REQ-003 | The library SHALL expose canonical string formatting. | `src/uuid.zig:73`, `:85`, `:134` |
| UUID-REQ-004 | The library SHALL expose ordering, equality, timestamp extraction, and hashing helpers. | `src/uuid.zig:96`, `:101`, `:106`, `:116` |
| UUID-REQ-005 | The library SHALL NOT embed Geode graph-registry or graph-store persistence behavior. | `src/graph_registry.zig:24`, `src/graph_store.zig:625`, `:4018` stay in Geode |

## Test Requirements

| ID | Requirement | Geode evidence |
|---|---|---|
| UUID-TEST-001 | Preserve direct UUID generation/format/order unit tests. | `src/uuid.zig:141`, `:157`, `:172` |
| UUID-TEST-002 | Preserve representative Geode integration coverage. | `src/graph_registry.zig:223`, `:271`, `:299`, `:322`, `:338`, `:360`, `src/graph_store.zig:5065` |

## Documentation Requirements

- Document the UUID version supported by the library.
- Document string and byte conversions.
- Document that graph-registry and graph-store usage remain external consumers.

## Migration Requirements

1. Geode should keep consuming this repo for the UUID core.
2. No Geode registry or graph-store file logic should be moved into this library.
