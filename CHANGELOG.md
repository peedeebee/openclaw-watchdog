# OpenClaw Watchdog Changelog

## 2.0.0 (2026-04-13)

### Features
- **Smart Rate Limit Detection**: Detects API 429 errors and skips restart when rate limited
- **Exponential Backoff**: 10min → 30min → 60min → 2hr → 4hr cooldown progression
- **Gateway Responsiveness Check**: Tests actual command responsiveness before declaring dead
- **Backoff Reset on Success**: Resets to level 0 when gateway is healthy
- **Differentiated Notifications**: Separate messages for "rate limited" vs "crashed"

### Improvements
- Checks logs for rate limit errors (429, rate.limit, RateLimit) in last 30 minutes
- Only restarts for actual crashes, not API exhaustion
- Prevents restart loops during API cooldown periods
- More intelligent health checking with `openclaw gateway status`

### Technical
- New state files: `.watchdog-backoff`, `.watchdog-rate-limited`
- Backoff level persisted across checks
- Rate limit detection from both journalctl and gateway logs
- Maintains all v1.0 features (memory checks, Telegram notifications)

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
