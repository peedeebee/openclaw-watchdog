#!/bin/bash
# OpenClaw Gateway Watchdog Script v2.0
# Smart restart with API rate limit awareness and exponential backoff
# Runs via cron every 5 minutes

set -euo pipefail

# Fix for cron environment
USER_ID=$(id -u 2>/dev/null || echo "1000")
if [[ -z "${DBUS_SESSION_BUS_ADDRESS:-}" ]]; then
    export DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/${USER_ID}/bus"
fi
if [[ -z "${XDG_RUNTIME_DIR:-}" ]]; then
    export XDG_RUNTIME_DIR="/run/user/${USER_ID}"
fi

# Configuration
SERVICE_NAME="openclaw-gateway"
LOG_FILE="$HOME/.openclaw/watchdog.log"
COOLDOWN_FILE="$HOME/.openclaw/.watchdog-cooldown"
BACKOFF_STATE_FILE="$HOME/.openclaw/.watchdog-backoff"
RATE_LIMIT_FILE="$HOME/.openclaw/.watchdog-rate-limited"
MEMORY_LIMIT_MB=8192
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-8379832070}"

# Backoff intervals (minutes): 10, 30, 60, 120, 240
BACKOFF_INTERVALS=(10 30 60 120 240)
MAX_BACKOFF_INDEX=4

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Get current backoff level
get_backoff_level() {
    if [[ -f "$BACKOFF_STATE_FILE" ]]; then
        cat "$BACKOFF_STATE_FILE" 2>/dev/null || echo "0"
    else
        echo "0"
    fi
}

# Set backoff level
set_backoff_level() {
    local level="$1"
    echo "$level" > "$BACKOFF_STATE_FILE"
}

# Reset backoff on success
reset_backoff() {
    rm -f "$BACKOFF_STATE_FILE"
    rm -f "$RATE_LIMIT_FILE"
}

# Get current cooldown minutes based on backoff level
get_cooldown_minutes() {
    local level
    level=$(get_backoff_level)
    if [[ "$level" -gt "$MAX_BACKOFF_INDEX" ]]; then
        level=$MAX_BACKOFF_INDEX
    fi
    echo "${BACKOFF_INTERVALS[$level]}"
}

# Check if we're in cooldown
check_cooldown() {
    if [[ -f "$COOLDOWN_FILE" ]]; then
        local last_restart
        last_restart=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || echo 0)
        local now
        now=$(date +%s)
        local elapsed=$(( (now - last_restart) / 60 ))
        local cooldown
        cooldown=$(get_cooldown_minutes)
        
        if [[ $elapsed -lt $cooldown ]]; then
            log "INFO: In cooldown period ($elapsed min < $cooldown min backoff), skipping checks"
            return 0  # In cooldown
        fi
    fi
    return 1  # Not in cooldown
}

# Set cooldown timestamp
set_cooldown() {
    touch "$COOLDOWN_FILE"
}

# Check if API rate limits are exhausted
check_rate_limited() {
    # Check recent logs for 429 errors or rate limit messages
    local since
    since=$(date -d '30 minutes ago' '+%Y-%m-%d %H:%M' 2>/dev/null || echo "")
    
    if [[ -z "$since" ]]; then
        return 1  # Can't check, assume not rate limited
    fi
    
    # Check journal for rate limit errors
    local rate_limit_count
    rate_limit_count=$(journalctl --user -u "$SERVICE_NAME" --since "$since" 2>/dev/null | \
        grep -cE "(429|rate.limit|RateLimit|too many requests)" 2>/dev/null || echo 0) || true
    rate_limit_count=$(echo "$rate_limit_count" | tr -d '\n' | grep -oE '^[0-9]+$' || echo 0)
    
    # Also check gateway log file
    local gateway_log_count=0
    if [[ -f "/tmp/openclaw/openclaw-$(date +%Y-%m-%d).log" ]]; then
        gateway_log_count=$(grep -cE "(429|rate.limit|RateLimit)" "/tmp/openclaw/openclaw-$(date +%Y-%m-%d).log" 2>/dev/null || echo 0) || true
        gateway_log_count=$(echo "$gateway_log_count" | tr -d '\n' | grep -oE '^[0-9]+$' || echo 0)
    fi
    
    local total_count=$((rate_limit_count + gateway_log_count))
    
    if [[ "$total_count" -gt 5 ]]; then
        log "WARNING: Rate limit errors detected ($total_count in last 30 min)"
        echo "$total_count"
        return 0  # Rate limited
    fi
    
    return 1  # Not rate limited
}

# Mark as rate limited
set_rate_limited() {
    local count="$1"
    echo "$count" > "$RATE_LIMIT_FILE"
    local backoff
    backoff=$(get_backoff_level)
    log "INFO: Rate limited - increasing backoff to level $((backoff + 1))"
    set_backoff_level "$((backoff + 1))"
}

# Check if gateway is actually responsive to commands
check_gateway_responsive() {
    # Try a simple openclaw status command
    local timeout=10
    if timeout "$timeout" openclaw gateway status >/dev/null 2>&1; then
        return 0  # Responsive
    fi
    
    # Try health endpoint
    local port
    port=$(grep -oP '"port":\s*\K[0-9]+' "$HOME/.openclaw/openclaw.json" 2>/dev/null || echo 18789)
    
    if curl -sf --max-time 5 "http://localhost:$port/api/health" >/dev/null 2>&1; then
        return 0  # Responsive
    fi
    
    return 1  # Not responsive
}

# Send Telegram notification
notify_telegram() {
    local message="$1"
    local priority="${2:-normal}"
    
    # Get bot token from environment or systemd
    local bot_token
    bot_token=$(systemctl --user show-environment 2>/dev/null | grep -oP 'TELEGRAM_BOT_TOKEN=\K[^[:space:]]+' || echo "")
    
    if [[ -z "$bot_token" ]]; then
        bot_token=$(grep -oP 'TELEGRAM_BOT_TOKEN=\K[^[:space:]]+' "$HOME/.config/systemd/user/openclaw-gateway.service" 2>/dev/null || echo "")
    fi
    
    if [[ -n "$bot_token" && -n "$TELEGRAM_CHAT_ID" ]]; then
        local response
        response=$(curl -sf -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d "chat_id=${TELEGRAM_CHAT_ID}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" 2>/dev/null || echo "")
        
        if [[ -n "$response" && "$response" == *'"ok":true'* ]]; then
            log "NOTIFY: Telegram message sent"
        else
            log "NOTIFY: Failed to send Telegram message"
        fi
    fi
}

# Check systemd service status
check_service_active() {
    systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null
}

# Check memory usage
check_memory() {
    local pid
    pid=$(systemctl --user show "$SERVICE_NAME" --property=MainPID --value 2>/dev/null || echo 0)
    
    if [[ "$pid" -eq 0 ]]; then
        return 0
    fi
    
    local rss_kb
    rss_kb=$(ps -p "$pid" -o rss= 2>/dev/null || echo 0)
    local rss_mb=$((rss_kb / 1024))
    
    if [[ $rss_mb -gt $MEMORY_LIMIT_MB ]]; then
        echo "memory_high:${rss_mb}MB"
        return 1
    fi
    return 0
}

# Restart gateway with backoff
restart_gateway() {
    local reason="$1"
    local pid
    pid=$(systemctl --user show "$SERVICE_NAME" --property=MainPID --value 2>/dev/null || echo "unknown")
    
    local backoff
    backoff=$(get_backoff_level)
    local cooldown
    cooldown=$(get_cooldown_minutes)
    
    log "WARNING: Restarting $SERVICE_NAME — $reason (PID: $pid, backoff level: $backoff, cooldown: ${cooldown}min)"
    
    if systemctl --user restart "$SERVICE_NAME" 2>/dev/null; then
        set_cooldown
        set_backoff_level "$((backoff + 1))"
        notify_telegram "⚠️ OpenClaw Gateway restarted — $reason (was PID $pid, cooldown: ${cooldown}min)"
        log "INFO: Restart successful, backoff increased to level $((backoff + 1))"
    else
        log "ERROR: Failed to restart $SERVICE_NAME"
        notify_telegram "❌ Failed to restart OpenClaw Gateway — $reason"
    fi
}

# Main execution
main() {
    log "INFO: Watchdog v2.0 check starting"
    
    # Check cooldown first
    if check_cooldown; then
        exit 0
    fi
    
    # Check if service is active
    if check_service_active; then
        # Service is running - check if it's responsive
        if check_gateway_responsive; then
            # Gateway is healthy - reset backoff
            if [[ -f "$BACKOFF_STATE_FILE" ]]; then
                log "INFO: Gateway healthy - resetting backoff"
                reset_backoff
            fi
            
            # Check memory
            local mem_check
            if ! mem_check=$(check_memory) && [[ -n "$mem_check" ]]; then
                log "WARNING: $mem_check"
                # Don't restart for high memory, just log it
            fi
            
            log "INFO: All health checks passed"
            exit 0
        fi
        
        # Service active but not responsive - check if rate limited
        local rate_limit_count
        if check_rate_limited; then
            rate_limit_count=$?
            set_rate_limited "$rate_limit_count"
            local cooldown
            cooldown=$(get_cooldown_minutes)
            log "INFO: Gateway unresponsive but rate limited - skipping restart (cooldown: ${cooldown}min)"
            notify_telegram "⏸️ OpenClaw rate limited - restart skipped (cooldown: ${cooldown}min)"
            set_cooldown  # Still set cooldown to prevent frequent checks
            exit 0
        fi
        
        # Not rate limited, restart needed
        restart_gateway "unresponsive to health checks"
    else
        # Service not active - check if rate limited before restarting
        local rate_limit_count
        if check_rate_limited; then
            rate_limit_count=$?
            set_rate_limited "$rate_limit_count"
            local cooldown
            cooldown=$(get_cooldown_minutes)
            log "INFO: Service inactive but rate limited - delaying restart (cooldown: ${cooldown}min)"
            notify_telegram "⏸️ OpenClaw inactive but rate limited - restart delayed (cooldown: ${cooldown}min)"
            set_cooldown
            exit 0
        fi
        
        # Actually crashed, restart it
        restart_gateway "service not active"
    fi
}

# Run main
main "$@"
