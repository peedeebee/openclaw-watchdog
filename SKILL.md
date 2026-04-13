# OpenClaw Watchdog v2.0

Smart health monitoring for OpenClaw Gateway with API rate limit awareness and exponential backoff.

## Purpose

Ensures your OpenClaw Gateway stays healthy without making API rate limit situations worse.

### Key Features

- **Smart Rate Limit Detection**: Detects 429 errors and skips restart when API limits are exhausted
- **Exponential Backoff**: Progressive cooldown (10min → 30min → 60min → 2hr → 4hr)
- **Gateway Responsiveness**: Tests actual command execution before declaring dead
- **Backoff Reset**: Returns to normal monitoring when gateway is healthy

## Installation

```bash
# Clone and install
git clone https://github.com/peedeebee/openclaw-watchdog.git
cd openclaw-watchdog
./install.sh
```

Or manually:
```bash
cp openclaw-watchdog.sh ~/.openclaw/
chmod +x ~/.openclaw/openclaw-watchdog.sh

# Add to crontab (runs every 5 minutes)
echo "*/5 * * * * /home/$(whoami)/.openclaw/openclaw-watchdog.sh >> /home/$(whoami)/.openclaw/watchdog.log 2>&1" | crontab -
```

## Configuration

Edit the script or set environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY_LIMIT_MB` | 8192 | RSS memory threshold (MB) |
| `TELEGRAM_CHAT_ID` | 8379832070 | Your Telegram chat ID |
| `BACKOFF_INTERVALS` | 10,30,60,120,240 | Cooldown minutes per level |

## How It Works

### Rate Limit Protection
When API rate limits are hit (detected via 429 errors in logs):
- ❌ Skips restart (restarting won't help)
- ⏸️ Extends cooldown exponentially
- 📱 Sends "rate limited" notification

### Health Check Flow
1. **Cooldown Check** — Are we in backoff period?
2. **Service Status** — Is systemd unit active?
3. **Responsiveness** — Does `openclaw gateway status` work?
4. **Rate Limit Check** — Any 429 errors in last 30 min?
5. **Decision** — Restart only if crashed (not rate limited)

### Backoff Levels
| Level | Cooldown | When Triggered |
|-------|----------|----------------|
| 0 | 10 min | Normal operation |
| 1 | 30 min | First restart |
| 2 | 60 min | Second restart |
| 3 | 2 hr | Third restart |
| 4 | 4 hr | Max backoff |

**Reset**: Backoff resets to 0 when gateway is healthy.

## Notifications

Telegram messages:
- ⚠️ Gateway restarted (with PID and cooldown)
- ⏸️ Rate limited — restart skipped
- ❌ Failed restart attempt

## Logs

```bash
# Watchdog logs
tail -f ~/.openclaw/watchdog.log

# State files
ls -la ~/.openclaw/.watchdog-*
```

## State Files

- `.watchdog-cooldown` — Last restart timestamp
- `.watchdog-backoff` — Current backoff level (0-4)
- `.watchdog-rate-limited` — Rate limit error count

## Upgrade from v1.0

```bash
# Replace script
cp openclaw-watchdog.sh ~/.openclaw/openclaw-watchdog.sh

# Clear old state
rm -f ~/.openclaw/.watchdog-cooldown

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

See [CHANGELOG.md](CHANGELOG.md)

## License

MIT
