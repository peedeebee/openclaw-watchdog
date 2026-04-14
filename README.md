# OpenClaw Watchdog

Smart health monitoring and self-healing for OpenClaw Gateway with API rate limit awareness.

## Overview

OpenClaw Watchdog monitors your OpenClaw Gateway and automatically restarts it when unhealthy — but unlike simple watchdogs, it's smart enough to **avoid making API rate limit situations worse**.

## Key Features

| Feature | Description |
|---------|-------------|
| **Rate Limit Detection** | Detects HTTP 429 errors and skips restart when API limits are exhausted |
| **Exponential Backoff** | Progressive cooldown: 10min → 30min → 60min → 2hr → 4hr |
| **Smart Responsiveness** | Tests actual gateway commands before declaring it dead |
| **Backoff Reset** | Returns to normal monitoring when gateway is healthy |
| **Differentiated Alerts** | Separate notifications for "rate limited" vs "crashed" |

## Installation

```bash
# Clone the repository
git clone https://github.com/peedeebee/openclaw-watchdog.git
cd openclaw-watchdog

# Run installer
./install.sh
```

Or manually:

```bash
# Copy script to OpenClaw directory
cp openclaw-watchdog.sh ~/.openclaw/
chmod +x ~/.openclaw/openclaw-watchdog.sh

# Add to crontab (runs every 5 minutes)
echo "*/5 * * * * /home/$(whoami)/.openclaw/openclaw-watchdog.sh >> /home/$(whoami)/.openclaw/watchdog.log 2>&1" | crontab -
```

## Configuration

Edit the script or set environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY_LIMIT_MB` | 8192 | RSS memory threshold in MB |
| `TELEGRAM_CHAT_ID` | 8379832070 | Telegram chat ID for notifications |
| `BACKOFF_INTERVALS` | 10,30,60,120,240 | Cooldown minutes per backoff level |

## How It Works

### Health Check Flow

1. **Cooldown Check** — Are we in a backoff period?
2. **Service Status** — Is the systemd unit active?
3. **Responsiveness Test** — Does `openclaw gateway status` work?
4. **Rate Limit Check** — Any 429 errors in the last 30 minutes?
5. **Decision** — Restart only if crashed (not rate limited)

### Rate Limit Protection

When API rate limits are detected:
- ❌ **Skips restart** (restarting won't help)
- ⏸️ **Extends cooldown** exponentially
- 📱 **Sends notification** — "rate limited, restart skipped"

### Exponential Backoff Levels

| Level | Cooldown | Trigger |
|-------|----------|---------|
| 0 | 10 min | Normal operation |
| 1 | 30 min | First restart |
| 2 | 60 min | Second restart |
| 3 | 2 hours | Third restart |
| 4 | 4 hours | Maximum backoff |

**Reset:** Backoff returns to level 0 when the gateway is healthy.

## Notifications

Telegram messages are sent for:

- ⚠️ **Gateway restarted** — includes PID and cooldown duration
- ⏸️ **Rate limited** — restart skipped, cooldown extended
- ❌ **Failed restart** — restart attempt failed

## Logs & State

```bash
# Watchdog logs
tail -f ~/.openclaw/watchdog.log

# State files (auto-managed)
ls -la ~/.openclaw/.watchdog-*
```

### State Files

- `.watchdog-cooldown` — Timestamp of last restart
- `.watchdog-backoff` — Current backoff level (0-4)
- `.watchdog-rate-limited` — Rate limit error count

## Upgrade from v1.0

```bash
# Replace the script
cp openclaw-watchdog.sh ~/.openclaw/openclaw-watchdog.sh

# Clear old state files
rm -f ~/.openclaw/.watchdog-cooldown
rm -f ~/.openclaw/.watchdog-backoff

# Done — new backoff logic takes effect immediately
```

## Uninstall

```bash
# Remove from crontab
crontab -l | grep -v openclaw-watchdog | crontab -

# Remove files
rm ~/.openclaw/openclaw-watchdog.sh
rm ~/.openclaw/watchdog.log
rm -f ~/.openclaw/.watchdog-*
```

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT
