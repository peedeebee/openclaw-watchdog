# OpenClaw Watchdog

Automatic health monitoring and self-healing for OpenClaw Gateway.

## Purpose

Ensures your OpenClaw Gateway stays healthy by:
- Monitoring service status, memory, and responsiveness
- Automatically restarting on failure
- Sending notifications when action is taken

## Installation

```bash
# Clone and install
git clone https://github.com/philip-baron/openclaw-watchdog.git
cd openclaw-watchdog
./install.sh
```

Or manually:
```bash
cp openclaw-watchdog.sh ~/.openclaw/
chmod +x ~/.openclaw/openclaw-watchdog.sh

# Add to crontab (runs every 5 minutes)
echo "*/5 * * * * /home/$(whoami)/.openclaw/openclaw-watchdog.sh >> /tmp/openclaw-watchdog.log 2>&1" | crontab -
```

## Configuration

Edit the script or set environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `MEMORY_LIMIT_MB` | 8192 | RSS memory threshold (MB) |
| `COOLDOWN_MINUTES` | 10 | Minimum time between restarts |
| `TELEGRAM_BOT_TOKEN` | auto | From systemd env or service file |
| `TELEGRAM_CHAT_ID` | required | Your Telegram chat ID |

## Health Checks

1. **Service Active** — Is systemd unit running?
2. **Liveness** — Does gateway respond on HTTP port?
3. **Memory** — Is RSS below threshold?
4. **Error Storm** — Too many errors in recent logs?

## Notifications

Telegram messages sent on:
- ⚠️ Gateway restarted (with reason)
- ❌ Failed restart attempt

## Logs

```bash
tail -f ~/.openclaw/watchdog.log
```

## Uninstall

```bash
# Remove from crontab
crontab -l | grep -v openclaw-watchdog | crontab -

# Remove files
rm ~/.openclaw/openclaw-watchdog.sh
rm ~/.openclaw/watchdog.log
```

## License

MIT
