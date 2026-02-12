#!/bin/bash
# ============================================================================
# Setup a local cron job to monitor Claude config bloat
# Runs weekly and logs warnings to ~/claude-cleanup/monitor.log
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CLEANUP_SCRIPT="$SCRIPT_DIR/claude-cleanup.sh"
LOG_FILE="$SCRIPT_DIR/monitor.log"
THRESHOLD="${1:-15}"

CYAN='\033[0;36m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${CYAN}▸ Claude Config Bloat Monitor — Cron Setup${NC}"
echo ""

# Create the monitor script
MONITOR_SCRIPT="$SCRIPT_DIR/monitor-check.sh"
cat > "$MONITOR_SCRIPT" << MONEOF
#!/bin/bash
# Auto-generated monitor script — checks MCP server count weekly
THRESHOLD=$THRESHOLD
LOG="$LOG_FILE"
TIMESTAMP=\$(date "+%Y-%m-%d %H:%M:%S")

TOTAL=\$(python3 -c "
import json, os
total = 0
for p in [
    os.path.expanduser('~/Library/Application Support/Claude/claude_desktop_config.json'),
    os.path.expanduser('~/.config/Claude/claude_desktop_config.json'),
    os.path.expanduser('~/.claude/settings.json'),
    os.path.expanduser('~/.claude/mcp.json')
]:
    if os.path.isfile(p):
        try:
            d = json.load(open(p))
            for k in ['mcpServers', 'mcp_servers']:
                if k in d: total += len(d[k])
        except: pass
print(total)
" 2>/dev/null)

ESTIMATED=\$((TOTAL * 3000))
PCT=\$((ESTIMATED * 100 / 200000))

if [ \$TOTAL -gt \$THRESHOLD ]; then
    echo "[\$TIMESTAMP] ⚠️  BLOAT: \$TOTAL MCP servers (~\${ESTIMATED} tokens, \${PCT}% of context). Threshold: \$THRESHOLD" >> "\$LOG"
    # macOS notification
    if command -v osascript &>/dev/null; then
        osascript -e "display notification \"\\$TOTAL MCP servers using ~\${PCT}% context. Run: claude-fix doctor\" with title \"Claude Config Bloat\" subtitle \"\\$TOTAL servers (threshold: \\$THRESHOLD)\""
    fi
    # Linux notification
    if command -v notify-send &>/dev/null; then
        notify-send "Claude Config Bloat" "\$TOTAL MCP servers using ~\${PCT}% context. Run: claude-fix doctor"
    fi
else
    echo "[\$TIMESTAMP] ✅  OK: \$TOTAL MCP servers (~\${ESTIMATED} tokens, \${PCT}% of context)" >> "\$LOG"
fi
MONEOF

chmod +x "$MONITOR_SCRIPT"
echo -e "  ${GREEN}✓${NC} Created monitor script: $MONITOR_SCRIPT"

# Check if cron job already exists
if crontab -l 2>/dev/null | grep -q "monitor-check.sh"; then
    echo -e "  ${YELLOW}ℹ${NC} Cron job already exists — skipping"
else
    # Add weekly cron job (Monday 9am)
    (crontab -l 2>/dev/null; echo "0 9 * * 1 $MONITOR_SCRIPT") | crontab -
    echo -e "  ${GREEN}✓${NC} Added cron job: every Monday at 9am"
fi

echo -e "  ${GREEN}✓${NC} Threshold: $THRESHOLD MCP servers"
echo -e "  ${GREEN}✓${NC} Log file: $LOG_FILE"
echo ""
echo -e "  ${CYAN}To change threshold:${NC} $0 <number>"
echo -e "  ${CYAN}To remove cron job:${NC} crontab -e (delete the monitor-check.sh line)"
echo -e "  ${CYAN}To view log:${NC} cat $LOG_FILE"
echo ""

# Run it once now
echo -e "${CYAN}▸ Running initial check...${NC}"
bash "$MONITOR_SCRIPT"
tail -1 "$LOG_FILE"
echo ""
