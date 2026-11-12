<p align="center">
  <img width="240" src="./images/pinepods-logo.jpeg" alt="Castaway logo">
</p>

<h1 align="center">Castaway</h1>

<p align="center">
  <em>Self-hosted podcasts for your whole household.</em>
</p>

<p align="center">
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-GPLv3-blue" alt="License: GPL-3.0"></a>
</p>

---

## What is Castaway?

**Castaway is a self-hosted podcast manager.** You run one server, everyone in your
household connects to it, and each person's subscriptions, listening progress, queue and
downloads follow them between devices, because everything lives in your own database.
Listen in the browser, on the desktop, or on your phone.

- **Self-hosted and open source.** Your podcasts and listening data stay on your hardware.
- **Multi-user.** One server for the whole family, each person with their own library,
  stats and settings.
- **Apps everywhere.** Web, Linux, Windows, macOS, Android and iOS.
- **Bring your own apps.** A built-in gpodder-compatible sync server lets you keep using
  AntennaPod and similar apps alongside Castaway.
- **36 languages.**

Castaway is based on [PinePods](https://github.com/madeofpendletonwool/PinePods). See
[Credits & licensing](#credits--licensing).

## Highlights

| | |
|---|---|
| **Listen** | Audio **and video** podcasts, variable speed, chapters, transcripts, downloads, a persistent queue, serial auto-play and per-podcast auto-download. |
| **Organize** | Subscriptions, smart and manual playlists, saved episodes, favorites, full history, and podcasts from local files. |
| **Discover** | Search Podcast Index, iTunes and YouTube, search inside your own library, and follow podcast hosts. |
| **Sync & apps** | Built-in **gpodder server** (AntennaPod and others), OIDC single sign-on, MFA, and web, desktop and mobile apps with CarPlay and Android Auto. |
| **Make it yours** | Built-in themes plus a custom theme creator, listening stats, OPML import and export, and push notifications (ntfy or webhook). |

## Quick start

Castaway needs a database (PostgreSQL) and a Valkey or Redis server. The easiest way to run
it is Docker Compose.

**1. Build the image.** There's no published image yet, so build it from this repo:

```bash
git clone https://github.com/Sc00tz/Castaway.git
cd Castaway
docker build -t castaway .
```

**2. Create a `docker-compose.yml`:**

```yaml
services:
  db:
    image: postgres:18
    environment:
      POSTGRES_DB: pinepods_database
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: change-me
      PGDATA: /var/lib/pgdata/pgdata
    volumes:
      - /home/user/castaway/pgdata:/var/lib/pgdata
    restart: always

  valkey:
    image: valkey/valkey:8-alpine
    restart: always

  castaway:
    image: castaway:latest
    ports:
      - "8040:8040"
    environment:
      HOSTNAME: "http://localhost:8040"
      DB_TYPE: postgresql
      DB_HOST: db
      DB_PORT: 5432
      DB_USER: postgres
      DB_PASSWORD: change-me
      DB_NAME: pinepods_database
      VALKEY_HOST: valkey
      VALKEY_PORT: 6379
      # Run as your host user so downloads stay accessible (optional)
      PUID: ${UID:-911}
      PGID: ${GID:-911}
      TZ: "America/New_York"
    volumes:
      - /home/user/castaway/downloads:/opt/pinepods/downloads
      - /home/user/castaway/backups:/opt/pinepods/backups
    restart: always
    depends_on:
      - db
      - valkey
```

**3. Start it** with `docker compose up -d`, open `http://localhost:8040`, and create your
first admin account.

More complete examples, including SQLite, the optional AI sidecar, single sign-on settings
and allowing feeds hosted on your own network, are in
[`deployment/docker/compose-files`](deployment/docker/compose-files).

### Moving from PinePods

Castaway reads a PinePods database as-is. Point the `castaway` service at your existing
database and download folders, with the same `DB_NAME`, and it picks up where PinePods
left off. Some internal names, such as `pinepods_database` and the `/opt/pinepods` paths
inside the container, keep their PinePods names for exactly this reason. Back up your
database first.

## Apps

The web app is served by the server itself: browse to your server's address. The Android,
iOS and desktop apps aren't published to any store yet. Build them from
[`mobile/`](mobile) (Flutter) and [`web/src-tauri`](web/src-tauri) (Tauri).

## Contributing

Bug reports and ideas go in the
[issue tracker](https://github.com/Sc00tz/Castaway/issues). See
[CONTRIBUTING.md](CONTRIBUTING.md) for development setup.

## Credits & licensing

Castaway is licensed under the **GNU General Public License v3.0**. See [LICENSE](LICENSE).

Castaway is based on **[PinePods](https://github.com/madeofpendletonwool/PinePods)**,
© Gooseberry Development, also licensed under the GPL-3.0. Thank you to its author and
contributors for the foundation this project is built on.

The mobile app includes code adapted from the
[Anytime Podcast Player](https://github.com/amugofjava/anytime_podcast_player),
© 2020 Ben Hills and contributors, licensed under the BSD 3-Clause License. Affected files
keep their original license and attribution; see the license files in
[`mobile/`](mobile).
