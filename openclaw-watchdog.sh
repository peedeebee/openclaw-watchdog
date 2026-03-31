#!/bin/bash
# OpenClaw Gateway Watchdog Script
# Monitors gateway health and restarts if needed
# Runs via cron every 5 minutes

set -euo pipefail

# Fix for cron environment - ensure systemd user session is accessible
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
COOLDOWN_MINUTES=10
MEMORY_LIMIT_MB=8192  # 8GB RSS threshold
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Ensure log directory exists
mkdir -p "$(dirname "$LOG_FILE")"

# Logging function
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Check if we're in cooldown
check_cooldown() {
    if [[ -f "$COOLDOWN_FILE" ]]; then
        local last_restart
        last_restart=$(stat -c %Y "$COOLDOWN_FILE" 2>/dev/null || echo 0)
        local now
        now=$(date +%s)
        local elapsed=$(( (now - last_restart) / 60 ))
        
        if [[ $elapsed -lt $COOLDOWN_MINUTES ]]; then
            log "INFO: In cooldown period ($elapsed min < $COOLDOWN_MINUTES min), skipping checks"
            exit 0
        fi
    fi
}

# Set cooldown timestamp
set_cooldown() {
    touch "$COOLDOWN_FILE"
}

# Send Telegram notification
notify_telegram() {
    local message="$1"
    local bot_token
    bot_token=$(systemctl --user show-environment 2>/dev/null | grep -oP 'TELEGRAM_BOT_TOKEN=\K[^[:space:]]+' || echo "")
    
    if [[ -z "$bot_token" ]]; then
        # Try to get from systemd service file
        bot_token=$(grep -oP 'TELEGRAM_BOT_TOKEN=\K[^[:space:]]+' "$HOME/.config/systemd/user/openclaw-gateway.service" 2>/dev/null || echo "")
    fi
    
    # Get chat ID from environment or use empty (must be set by user)
    local chat_id="${TELEGRAM_CHAT_ID:-}"
    
    if [[ -n "$bot_token" && -n "$chat_id" ]]; then
        # Send via Telegram Bot API
        local response
        response=$(curl -sf -X POST "https://api.telegram.org/bot${bot_token}/sendMessage" \
            -d "chat_id=${chat_id}" \
            -d "text=${message}" \
            -d "parse_mode=HTML" 2>/dev/null || echo "")
        
        if [[ -n "$response" && "$response" == *'"ok":true'* ]]; then
            log "NOTIFY: Telegram message sent successfully"
        else
            log "NOTIFY: $message (Telegram API failed)"
        fi
    else
        log "NOTIFY: $message (bot token not found)"
    fi
}

# Check 1: Is systemd service active?
check_service_active() {
    if ! systemctl --user is-active --quiet "$SERVICE_NAME" 2>/dev/null; then
        echo "service_not_active"
        return 1
    fi
    return 0
}

# Check 2: Liveness probe - can gateway accept connections?
check_liveness() {
    # Get gateway port from config or use default
    local port
    port=$(grep -oP '"port":\s*\K[0-9]+' "$HOME/.openclaw/openclaw.json" 2>/dev/null || echo 8080)
    
    if ! curl -sf "http://localhost:$port/health" >/dev/null 2>&1; then
        # Try alternative endpoints
        if ! curl -sf "http://localhost:$port/status" >/dev/null 2>&1; then
            if ! curl -sf "http://localhost:$port" >/dev/null 2>&1; then
                echo "liveness_failed"
                return 1
            fi
        fi
    fi
    return 0
}

# Check 3: Memory usage
check_memory() {
    local pid
    pid=$(systemctl --user show "$SERVICE_NAME" --property=MainPID --value 2>/dev/null || echo 0)
    
    if [[ "$pid" -eq 0 ]]; then
        return 0  # Can't check, assume OK
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

# Check 4: Check for recent gateway errors in logs
check_recent_errors() {
    local since
    since=$(date -d '10 minutes ago' '+%Y-%m-%d %H:%M' 2>/dev/null || echo "")
    
    if [[ -z "$since" ]]; then
        return 0
    fi
    
    # Check journal for error patterns
    local error_count
    error_count=$(journalctl --user -u "$SERVICE_NAME" --since "$since" 2>/dev/null | \
        grep -cE "(ERROR|FATAL|panic|crash)" 2>/dev/null || echo 0) || true
    error_count=$(echo "$error_count" | tr -d '\n' | grep -oE '^[0-9]+$' || echo 0)
    
    if [[ "$error_count" -gt 10 ]]; then
        echo "error_storm:${error_count}"
        return 1
    fi
    return 0
}

# Restart gateway
restart_gateway() {
    local reason="$1"
    local pid
    pid=$(systemctl --user show "$SERVICE_NAME" --property=MainPID --value 2>/dev/null || echo "unknown")
    
    log "WARNING: Restarting $SERVICE_NAME — $reason (PID: $pid)"
    
    if systemctl --user restart "$SERVICE_NAME" 2>/dev/null; then
        set_cooldown
        notify_telegram "⚠️ OpenClaw Gateway restarted — $reason (was PID $pid)"
        log "INFO: Restart successful"
    else
        log "ERROR: Failed to restart $SERVICE_NAME"
        notify_telegram "❌ Failed to restart OpenClaw Gateway — $reason"
    fi
}

# Main execution
main() {
    log "INFO: Watchdog check starting"
    
    check_cooldown
    
    local failed_check=""
    local check_result
    
    # Run checks in order of severity
    if ! check_service_active; then
        failed_check="service not active"
    elif ! check_result=$(check_liveness) && [[ -n "$check_result" ]]; then
        failed_check="liveness probe failed"
    elif ! check_result=$(check_memory) && [[ -n "$check_result" ]]; then
        failed_check="high memory usage ($check_result)"
    elif ! check_result=$(check_recent_errors) && [[ -n "$check_result" ]]; then
        failed_check="error storm detected ($check_result)"
    fi
    
    if [[ -n "$failed_check" ]]; then
        restart_gateway "$failed_check"
    else
        log "INFO: All health checks passed"
    fi
}

# Run main
main "$@"
