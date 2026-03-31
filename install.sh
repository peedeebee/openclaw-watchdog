#!/bin/bash
# OpenClaw Gateway Watchdog - Installation Script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET_DIR="$HOME/.openclaw"
SCRIPT_NAME="openclaw-watchdog.sh"

echo "🔧 OpenClaw Watchdog Installer"
echo "==============================="
echo ""

# Check dependencies
if ! command -v systemctl &> /dev/null; then
    echo "❌ Error: systemd required but not found"
    exit 1
fi

if ! command -v crontab &> /dev/null; then
    echo "❌ Error: cron required but not found"
    exit 1
fi

# Create target directory
mkdir -p "$TARGET_DIR"
echo "✓ Created $TARGET_DIR"

# Copy script
cp "$SCRIPT_DIR/$SCRIPT_NAME" "$TARGET_DIR/"
chmod +x "$TARGET_DIR/$SCRIPT_NAME"
echo "✓ Installed $SCRIPT_NAME"

# Check if already in crontab
if crontab -l 2>/dev/null | grep -q "$SCRIPT_NAME"; then
    echo "⚠️  Watchdog already in crontab, skipping"
else
    # Add to crontab
    (crontab -l 2>/dev/null || echo "") | \
        { cat; echo ""; echo "# OpenClaw Gateway Watchdog - every 5 minutes"; echo "*/5 * * * * $TARGET_DIR/$SCRIPT_NAME >> /tmp/openclaw-watchdog.log 2>&1"; } | \
        crontab -
    echo "✓ Added to crontab (runs every 5 minutes)"
fi

# Test run
echo ""
echo "🧪 Testing watchdog..."
if "$TARGET_DIR/$SCRIPT_NAME" 2>&1 | grep -q "All health checks passed"; then
    echo "✓ Test passed"
else
    echo "⚠️  Test had issues, check logs"
fi

echo ""
echo "✅ Installation complete!"
echo ""
echo "Logs: tail -f ~/.openclaw/watchdog.log"
echo "Config: Edit $TARGET_DIR/$SCRIPT_NAME"
echo ""
echo "To get Telegram notifications:"
echo "  1. Set TELEGRAM_CHAT_ID in the script or your environment"
echo "  2. Ensure TELEGRAM_BOT_TOKEN is in your systemd environment"
