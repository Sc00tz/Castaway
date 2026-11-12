# Contributing to Castaway

Thanks for your interest in Castaway.

- **Bugs and ideas:** open an issue at https://github.com/Sc00tz/Castaway/issues.
- **Code:** fork the repo, make your change on a branch, and open a pull request describing
  what it does and how you tested it.

## Development setup

The project has three main parts:

| Part | Folder | Stack |
|---|---|---|
| Server API | `rust-api/` | Rust (axum, sqlx) |
| Web app | `web/` | Rust compiled to WebAssembly (Yew), served by nginx |
| Mobile app | `mobile/` | Flutter |

Run the tests for the part you change:

- **Server:** `cargo test --lib` in `rust-api/`. The integration tests need Docker:
  `rust-api/scripts/integration-tests.sh` (see `rust-api/tests/README.md`).
- **Mobile:** `flutter test` in `mobile/`.
- **Full image:** `docker build -t castaway .` from the repo root.
