#!/bin/bash
set -e  # Exit immediately if a command exits with a non-zero status

# Function to handle shutdown
shutdown() {
    echo "Shutting down..."
    pkill -TERM horust
    exit 0
}

# Set up signal handling
trap shutdown SIGTERM SIGINT

# Everything Castaway keeps (database, downloads, backups) lives under one folder, which
# should be a mounted volume. The server reads the same variable.
export CASTAWAY_DATA_DIR=${CASTAWAY_DATA_DIR:-/data}
DATA_DIR=$CASTAWAY_DATA_DIR

# Castaway runs on PostgreSQL only. With no DB_HOST it runs the PostgreSQL server built into
# this image, keeping its files in $DATA_DIR/postgres. Set DB_HOST (with DB_PORT, DB_USER,
# DB_PASSWORD and DB_NAME) to use a PostgreSQL server of your own instead.
if [[ -n "$DB_TYPE" && "$DB_TYPE" != "postgresql" && "$DB_TYPE" != "postgres" ]]; then
    echo "ERROR: DB_TYPE=$DB_TYPE isn't supported. Castaway uses PostgreSQL: leave DB_TYPE and DB_HOST"
    echo "unset to use the built-in database, or point DB_HOST at your own PostgreSQL server."
    exit 1
fi
DB_TYPE=postgresql
BUNDLED_DB=false
if [[ -z "$DB_HOST" ]]; then
    BUNDLED_DB=true
    DB_HOST=127.0.0.1
    DB_PORT=5432
    DB_USER=${DB_USER:-castaway}
    DB_NAME=${DB_NAME:-castaway}
fi

# Export all environment variables
export DB_USER=$DB_USER
export DB_PASSWORD=$DB_PASSWORD
export DB_HOST=$DB_HOST
export DB_NAME=$DB_NAME
export DB_PORT=$DB_PORT
export DB_TYPE=$DB_TYPE
export REVERSE_PROXY=$REVERSE_PROXY
export CASTAWAY_PORT=${CASTAWAY_PORT:-}
export PROXY_PROTOCOL=$PROXY_PROTOCOL
export DEBUG_MODE=${DEBUG_MODE:-'False'}
# Without any Valkey settings, the built-in database setup keeps that state in memory (one
# server process, so nothing else needs to share it), and installs pointed at their own
# database server look for a "valkey" host. VALKEY_MODE=memory or valkey picks explicitly.
valkey_mode=$(echo "$VALKEY_MODE" | tr '[:upper:]' '[:lower:]')
if [[ -z "$VALKEY_URL$REDIS_URL$VALKEY_HOST$REDIS_HOST" && -z "$valkey_mode" && "$BUNDLED_DB" == true ]]; then
    VALKEY_MODE=memory
elif [[ -z "$VALKEY_URL$REDIS_URL$VALKEY_HOST$REDIS_HOST" && "$valkey_mode" != "memory" ]]; then
    VALKEY_HOST=valkey
fi
export VALKEY_HOST=$VALKEY_HOST
export VALKEY_PORT=${VALKEY_PORT:-'6379'}
export VALKEY_MODE=$VALKEY_MODE
export DEFAULT_LANGUAGE=${DEFAULT_LANGUAGE:-'en'}
# Path to the self-updating yt-dlp binary (#793). Lives on the persistent downloads volume
# so `yt-dlp --update-to` survives container recreation; every yt-dlp caller resolves this.
export YTDLP_PATH=${YTDLP_PATH:-$DATA_DIR/downloads/.bin/yt-dlp}

# Fall back to HOSTNAME for SERVER_URL if SERVER_URL isn't already set.
# IMPORTANT: this must NOT unconditionally overwrite SERVER_URL. Some container
# runtimes/orchestration setups (e.g. rootless Podman under a systemd unit) set
# their own HOSTNAME (the container/pod name) in the environment, which can
# arrive *after* a user's `-e HOSTNAME=...` and win, or otherwise take
# precedence over it. When that happens this line used to clobber SERVER_URL
# with that runtime-assigned value every time, breaking RSS feed generation
# (absolute URLs for <link>/<guid>/<enclosure> end up using the container name
# instead of the configured domain - see #903). Setting SERVER_URL directly
# is not affected by that problem, so respect it if the user already set it.
export SERVER_URL=${SERVER_URL:-$HOSTNAME}

# Export OIDC environment variables
export OIDC_DISABLE_STANDARD_LOGIN=${OIDC_DISABLE_STANDARD_LOGIN:-'false'}
export OIDC_PROVIDER_NAME=${OIDC_PROVIDER_NAME}
export OIDC_CLIENT_ID=${OIDC_CLIENT_ID}
export OIDC_CLIENT_SECRET=${OIDC_CLIENT_SECRET}
export OIDC_AUTHORIZATION_URL=${OIDC_AUTHORIZATION_URL}
export OIDC_TOKEN_URL=${OIDC_TOKEN_URL}
export OIDC_USER_INFO_URL=${OIDC_USER_INFO_URL}
export OIDC_DISCOVERY_URL=${OIDC_DISCOVERY_URL}
export OIDC_BUTTON_TEXT=${OIDC_BUTTON_TEXT}
export OIDC_SCOPE=${OIDC_SCOPE}
export OIDC_BUTTON_COLOR=${OIDC_BUTTON_COLOR}
export OIDC_BUTTON_TEXT_COLOR=${OIDC_BUTTON_TEXT_COLOR}
export OIDC_ICON_SVG=${OIDC_ICON_SVG}
export OIDC_NAME_CLAIM=${OIDC_NAME_CLAIM}
export OIDC_EMAIL_CLAIM=${OIDC_EMAIL_CLAIM}
export OIDC_USERNAME_CLAIM=${OIDC_USERNAME_CLAIM}
export OIDC_ROLES_CLAIM=${OIDC_ROLES_CLAIM}
export OIDC_USER_ROLE=${OIDC_USER_ROLE}
export OIDC_ADMIN_ROLE=${OIDC_ADMIN_ROLE}


# Print the Castaway banner
cat << "EOF"

   ____          _
  / ___|__ _ ___| |_ __ ___      ____ _ _   _
 | |   / _` / __| __/ _` \ \ /\ / / _` | | | |
 | |__| (_| \__ \ || (_| |\ V  V / (_| | |_| |
  \____\__,_|___/\__\__,_| \_/\_/ \__,_|\__, |
                                        |___/
  Self-hosted podcasts. Based on PinePods (GPL-3.0).
EOF

# Print version beneath the banner
VERSION_DISPLAY="$(cat /castaway/current_version 2>/dev/null || echo 'dev')"
echo ""
echo "  Castaway ${VERSION_DISPLAY}"
echo ""

# Configure timezone based on TZ environment variable
if [ -n "$TZ" ]; then
    echo "Setting timezone to $TZ"
    # For Alpine, we need to copy the zoneinfo file
    if [ -f "/usr/share/zoneinfo/$TZ" ]; then
        # Check if /etc/localtime is a mounted volume
        if [ -f "/etc/localtime" ] && ! [ -L "/etc/localtime" ]; then
            echo "Using mounted timezone file from host"
        else
            # If it's not mounted or is a symlink, we can modify it
            cp /usr/share/zoneinfo/$TZ /etc/localtime
            echo "$TZ" > /etc/timezone
        fi
    else
        echo "Timezone $TZ not found, using UTC"
        # Only modify if not mounted
        if ! [ -f "/etc/localtime" ] || [ -L "/etc/localtime" ]; then
            cp /usr/share/zoneinfo/UTC /etc/localtime
            echo "UTC" > /etc/timezone
        fi
    fi
else
    echo "No timezone specified, using UTC"
    # Only modify if not mounted
    if ! [ -f "/etc/localtime" ] || [ -L "/etc/localtime" ]; then
        cp /usr/share/zoneinfo/UTC /etc/localtime
        echo "UTC" > /etc/timezone
    fi
fi

# Export TZ to the environment for all child processes
export TZ

# Create required directories
echo "Creating required directories..."
mkdir -p /castaway/cache
mkdir -p $DATA_DIR/backups
mkdir -p $DATA_DIR/downloads
mkdir -p $DATA_DIR/certs
mkdir -p $DATA_DIR/local-media  # User-mounted media library; app writes artwork here
mkdir -p /var/log/castaway  # Make sure log directory exists

# Seed the persistent, self-updating yt-dlp binary (#793). yt-dlp updates itself at runtime
# (yt-dlp --update-to), so it must live on a persistent, user-writable path rather than the
# root-owned image layer. Seed from the baked-in binary on first boot; later boots keep whatever
# the self-updater has fetched. Chown to the runtime user so --update-to can replace it in place,
# even on existing installs where the one-time recursive perms migration already ran.
YTDLP_BIN_DIR=$(dirname "$YTDLP_PATH")
mkdir -p "$YTDLP_BIN_DIR"
if [ ! -x "$YTDLP_PATH" ] && [ -x /usr/local/bin/yt-dlp ]; then
    echo "Seeding managed yt-dlp binary from image..."
    cp /usr/local/bin/yt-dlp "$YTDLP_PATH" && chmod +x "$YTDLP_PATH"
fi
if [ -n "${PUID}" ] && [ -n "${PGID}" ]; then
    chown -R "${PUID}:${PGID}" "$YTDLP_BIN_DIR" 2>/dev/null || true
fi

# Built-in PostgreSQL. It runs as the 'castaway' user (PostgreSQL refuses to run as root),
# which is remapped to PUID/PGID so the database files belong to the host user like the rest.
PG_BIN=/usr/libexec/postgresql18
PG_MAJOR=18
PG_ROOT=$DATA_DIR/postgres
PG_SOCKETS=/run/postgresql
# Horust runs as PUID when both IDs are set and PUID isn't root (see the end of this script);
# otherwise it runs as root and has to switch to 'castaway' to start PostgreSQL.
if [[ -n "$PUID" && -n "$PGID" && ! "$PUID" =~ ^0+$ ]]; then
    groupmod -o -g "$PGID" castaway 2>/dev/null || true
    usermod -o -u "$PUID" -g "$PGID" castaway 2>/dev/null || true
    pg_service_cmd="$PG_BIN/postgres"
else
    pg_service_cmd="su-exec castaway $PG_BIN/postgres"
fi
pg() { su-exec castaway "$@"; }

if [[ "$BUNDLED_DB" == true ]]; then
    export PGDATA=$PG_ROOT/data
    pw_file=$PG_ROOT/password
    mkdir -p "$PG_ROOT" "$PG_SOCKETS"
    chown castaway:castaway "$PG_ROOT" "$PG_SOCKETS"
    chmod 700 "$PG_ROOT"

    if [[ ! -s "$PGDATA/PG_VERSION" ]]; then
        echo "Creating the built-in PostgreSQL database in $PGDATA..."
        # The password never needs typing: Castaway reads it from this file. DB_PASSWORD, if
        # set on the first start, is used instead of a generated one.
        if [[ ! -s "$pw_file" ]]; then
            (umask 077; if [[ -n "$DB_PASSWORD" ]]; then printf '%s' "$DB_PASSWORD"; else openssl rand -hex 24; fi > "$pw_file")
        fi
        chown castaway:castaway "$pw_file"
        pg "$PG_BIN/initdb" -D "$PGDATA" -U "$DB_USER" --pwfile="$pw_file" \
            --auth=scram-sha-256 --encoding=UTF8 --locale=C.UTF-8 >/dev/null
    fi

    data_major=$(cat "$PGDATA/PG_VERSION")
    if [[ "$data_major" != "$PG_MAJOR" ]]; then
        echo "ERROR: $PGDATA was created by PostgreSQL $data_major, but this image runs PostgreSQL $PG_MAJOR."
        echo "Run the previous image, make a backup in Castaway's settings, then restore it into a fresh database."
        exit 1
    fi
    if [[ ! -s "$pw_file" ]]; then
        echo "ERROR: $pw_file is missing, so Castaway can't log in to its database."
        exit 1
    fi
    export DB_PASSWORD=$(cat "$pw_file")

    # If PUID changed since the database was created, hand its files to the new owner. Checked
    # as that user: some mounts (Docker Desktop's) report a different owner to root.
    if ! pg test -O "$PGDATA"; then
        echo "Updating database file ownership for the new PUID..."
        chown -R castaway:castaway "$PGDATA" "$pw_file"
    fi
    # The Castaway server creates its database and schema itself when it starts.
fi

# Set up environment variables for Horust logging modes
if [[ $DEBUG_MODE == "true" ]]; then
    export HORUST_STDOUT_MODE="STDOUT"
    export HORUST_STDERR_MODE="STDERR"
    echo "Starting Horust in debug mode (logs to stdout)..."
else
    export HORUST_STDOUT_MODE="/var/log/castaway/service.log"
    export HORUST_STDERR_MODE="/var/log/castaway/service.log"
    echo "Starting Horust in production mode (logs to files)..."
fi

# Copy service configurations to Horust directory
cp /castaway/startup/services/*.toml /etc/horust/services/
if [[ "$BUNDLED_DB" == true ]]; then
    # SIGINT is PostgreSQL's "fast" shutdown: it disconnects clients and stops cleanly.
    cat > /etc/horust/services/postgres.toml <<EOF
command = "$pg_service_cmd -D $PGDATA -c listen_addresses=127.0.0.1 -k $PG_SOCKETS"
stdout = "\${HORUST_STDOUT_MODE}"
stderr = "\${HORUST_STDERR_MODE}"

[restart]
strategy = "always"
backoff = "1s"
attempts = 0

[environment]
keep-env = true

[termination]
signal = "INT"
wait = "30s"
EOF
    sed -i '1i start-after = ["postgres.toml"]' /etc/horust/services/castaway.toml
fi

# Ensure runtime directories exist and are writable when running non-root.
# Horust creates a unix-domain-socket folder at /var/run/horust; nginx needs its own dirs.
mkdir -p /run/nginx /var/lib/nginx/tmp /var/log/nginx /var/run/horust

# nginx's own directories belong to whoever its worker processes end up running
# as, which is not always PUID. This image replaces the packaged nginx.conf,
# and ours carries no 'user' directive, so nginx falls back to its compile-time
# default (--user=nginx): a master started as root drops its workers to the
# 'nginx' user. Handing /var/lib/nginx/tmp to anyone else (mode 0700) leaves
# those workers unable to create proxy temp files, and nginx then truncates any
# upstream response too large for its in-memory buffers instead of failing.
# The client just gets malformed JSON; the only trace is a
# "[crit] ... (13: Permission denied) while reading upstream" line in
# /var/log/nginx/error.log, which nothing surfaces because horust captures only
# nginx's stdout/stderr (startup/services/nginx.toml).
#
# The condition mirrors the privilege-drop guard below on purpose: privileges
# are only dropped when BOTH PUID and PGID are set, so PUID alone still leaves
# a root master whose workers are 'nginx'. Testing PUID by itself here would
# hand the dirs to PUID while nginx ran as 'nginx' — the same bug, reintroduced.
# The zero test matches any all-zero spelling, not just the string "0":
# chown and su-exec both parse "00" and "000" as uid 0, so a plain string
# compare would hand the dirs to root while the master stayed root and its
# workers dropped to 'nginx' -- the same bug, in the one case this guard exists
# to catch.
if [[ -n "$PUID" && -n "$PGID" && ! "$PUID" =~ ^0+$ ]]; then
    nginx_owner="${PUID}:${PGID}"
else
    nginx_owner="nginx:nginx"
fi
chown -R "$nginx_owner" /run/nginx /var/lib/nginx /var/log/nginx 2>/dev/null || true

# When PUID/PGID are set, drop privileges and run the whole stack as that user so files
# are created with correct ownership natively (no per-file chown needed). Otherwise run as root.
if [[ -n "$PUID" && -n "$PGID" ]]; then
    echo "Configuring non-root execution as ${PUID}:${PGID}..."

    # Remap the runtime user/group to the requested IDs (-o allows duplicate IDs).
    # This gives the dropped-privilege process a valid passwd entry and HOME (/castaway).
    groupmod -o -g "$PGID" castaway 2>/dev/null || true
    usermod -o -u "$PUID" -g "$PGID" castaway 2>/dev/null || true

    # Cheap, non-recursive ownership of the dirs the app writes to.
    # Note: local-media is intentionally chowned non-recursively — it's often a large
    # pre-existing library; the app only needs to write artwork into a subdir.
    # nginx's dirs are deliberately absent here — they are set above to the user
    # nginx actually runs its workers as, which is not PUID when the master is root.
    chown "${PUID}:${PGID}" /castaway/cache /var/log/castaway $DATA_DIR/certs \
                            $DATA_DIR/downloads $DATA_DIR/backups \
                            $DATA_DIR/local-media \
                            /var/run/horust 2>/dev/null || true

    # One-time recursive migration of pre-existing root-owned content, gated by a marker
    # on the persisted downloads volume. Non-fatal so an NFS/read-only mount can't block startup.
    if [ ! -f $DATA_DIR/downloads/.perms-migrated ]; then
        echo "One-time permission migration (only happens once; future boots are instant)..."
        if chown -R "${PUID}:${PGID}" $DATA_DIR/downloads $DATA_DIR/backups 2>/dev/null; then
            touch $DATA_DIR/downloads/.perms-migrated 2>/dev/null || true
        else
            echo "Skipped recursive chown (read-only/NFS mount) — new files will be owned by ${PUID}:${PGID} as they are written."
        fi
    fi

    echo "Starting services as ${PUID}:${PGID} with Horust..."
    echo "Castaway startup complete, running Horust in foreground..."
    exec su-exec "${PUID}:${PGID}" horust --services-path /etc/horust/services/
else
    echo "PUID/PGID not set — running as root (legacy mode)."
    echo "Starting services with Horust..."
    echo "Castaway startup complete, running Horust in foreground..."
    exec horust --services-path /etc/horust/services/
fi

