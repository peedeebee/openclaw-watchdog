# OpenClaw Watchdog Changelog

## 1.0.0 (2026-03-31)

### Features
- Automatic health monitoring for OpenClaw Gateway
- Four health checks: service status, liveness, memory, error storms
- Auto-restart on failure with cooldown protection
- Telegram notifications
- Cron-friendly environment handling

### Technical
- systemd user session integration
- DBUS_SESSION_BUS_ADDRESS auto-configuration
- Memory threshold: 8GB default
- 10-minute cooldown between restarts
