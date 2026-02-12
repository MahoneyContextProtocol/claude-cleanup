#!/bin/bash
# ============================================================================
# Claude Context Window Cleanup Tool
# Automates: MCP config disable/restore, cache clearing, app restart
# Manual steps still needed: claude.ai web UI toggles (Web Search, Extended
# Thinking, Analysis, Code Execution)
# ============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="$SCRIPT_DIR/backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

# Detect OS
OS="unknown"
if [[ "$OSTYPE" == "darwin"* ]]; then
    OS="macos"
elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    OS="linux"
elif [[ "$OSTYPE" == "msys" || "$OSTYPE" == "cygwin" ]]; then
    OS="windows"
fi

# Config paths — auto-detect per OS
if [[ "$OS" == "macos" ]]; then
    CLAUDE_DESKTOP_CONFIG="$HOME/Library/Application Support/Claude/claude_desktop_config.json"
    CLAUDE_DESKTOP_CACHE="$HOME/Library/Caches/com.anthropic.claude"
    CLAUDE_DESKTOP_CACHE2="$HOME/Library/Application Support/Claude/Cache"
    CLAUDE_DESKTOP_GPU_CACHE="$HOME/Library/Application Support/Claude/GPUCache"
    CLAUDE_DESKTOP_SW_CACHE="$HOME/Library/Application Support/Claude/Service Worker"
    CLAUDE_DESKTOP_CODE_CACHE="$HOME/Library/Application Support/Claude/Code Cache"
    BROWSER_OPEN_CMD="open"
    APP_PATH="/Applications/Claude.app"
elif [[ "$OS" == "linux" ]]; then
    CLAUDE_DESKTOP_CONFIG="$HOME/.config/Claude/claude_desktop_config.json"
    CLAUDE_DESKTOP_CACHE="$HOME/.config/Claude/Cache"
    CLAUDE_DESKTOP_CACHE2=""
    CLAUDE_DESKTOP_GPU_CACHE="$HOME/.config/Claude/GPUCache"
    CLAUDE_DESKTOP_SW_CACHE="$HOME/.config/Claude/Service Worker"
    CLAUDE_DESKTOP_CODE_CACHE="$HOME/.config/Claude/Code Cache"
    BROWSER_OPEN_CMD="xdg-open"
    APP_PATH=""
else
    CLAUDE_DESKTOP_CONFIG="$HOME/.config/Claude/claude_desktop_config.json"
    CLAUDE_DESKTOP_CACHE="$HOME/.config/Claude/Cache"
    CLAUDE_DESKTOP_CACHE2=""
    CLAUDE_DESKTOP_GPU_CACHE="$HOME/.config/Claude/GPUCache"
    CLAUDE_DESKTOP_SW_CACHE="$HOME/.config/Claude/Service Worker"
    CLAUDE_DESKTOP_CODE_CACHE="$HOME/.config/Claude/Code Cache"
    BROWSER_OPEN_CMD="start"
    APP_PATH=""
fi

# Cross-platform config paths
CLAUDE_CODE_CONFIG="$HOME/.claude/settings.json"
CLAUDE_MCP_CONFIG="$HOME/.claude/mcp.json"

# Collect all config files that exist
get_all_configs() {
    ALL_CONFIGS=()
    for p in "$CLAUDE_DESKTOP_CONFIG" "$CLAUDE_CODE_CONFIG" "$CLAUDE_MCP_CONFIG"; do
        [[ -f "$p" ]] && ALL_CONFIGS+=("$p")
    done
}

print_header() {
    echo ""
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${CYAN}  Claude Context Window Cleanup Tool${NC}"
    echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
}

show_help() {
    print_header
    echo "Usage: ./claude-cleanup.sh [command] [flags]"
    echo ""
    echo "Commands:"
    echo "  status       Show config state, MCP count, and cache sizes"
    echo "  doctor       Estimate token usage per connector, recommend cuts"
    echo "  slim         Disable heaviest connectors, keep lightweight ones"
    echo "  disable      Backup configs, then disable all MCP servers"
    echo "  restore      Restore configs from most recent backup"
    echo "  cache        Clear Claude-related caches"
    echo "  nuke [-y]    Full cleanup: disable + cache + restart + open settings"
    echo "  manual       Show manual steps checklist (web UI toggles)"
    echo "  help         Show this help message"
    echo ""
    echo "Flags:"
    echo "  -y, --yes    Skip confirmation prompts (for nuke, slim)"
    echo ""
    echo "Examples:"
    echo "  ./claude-cleanup.sh doctor       # See what's eating your context"
    echo "  ./claude-cleanup.sh slim -y      # Cut the heavy stuff, keep the rest"
    echo "  ./claude-cleanup.sh nuke -y      # Nuclear option — disable everything"
    echo "  ./claude-cleanup.sh restore      # Bring it all back"
    echo ""
}

# ── STATUS ──────────────────────────────────────────────────────────────────

cmd_status() {
    echo -e "${CYAN}▸ Detected OS:${NC} $OS"
    echo ""
    echo -e "${CYAN}▸ Config File Status${NC}"
    echo ""

    for config_path in "$CLAUDE_DESKTOP_CONFIG" "$CLAUDE_CODE_CONFIG" "$CLAUDE_MCP_CONFIG"; do
        label=$(basename "$config_path")
        dir=$(dirname "$config_path")
        if [[ -f "$config_path" ]]; then
            server_count=$(python3 -c "
import json, sys
try:
    d = json.load(open('$config_path'))
    servers = d.get('mcpServers', d.get('mcp_servers', {}))
    print(len(servers))
except: print('?')
" 2>/dev/null || echo "?")
            size=$(du -h "$config_path" | cut -f1)
            echo -e "  ${GREEN}✓${NC} $config_path  (${size}, ${server_count} MCP servers)"
        else
            echo -e "  ${YELLOW}–${NC} $config_path  (not found)"
        fi
    done

    # Show total MCP server count across all configs
    total=$(python3 -c "
import json, os
total = 0
for p in ['$CLAUDE_DESKTOP_CONFIG', '$CLAUDE_CODE_CONFIG', '$CLAUDE_MCP_CONFIG']:
    if os.path.isfile(p):
        try:
            d = json.load(open(p))
            for k in ['mcpServers', 'mcp_servers']:
                if k in d: total += len(d[k])
        except: pass
print(total)
" 2>/dev/null)
    echo ""
    echo -e "  ${CYAN}Total MCP servers across all configs: ${total:-?}${NC}"

    echo ""
    echo -e "${CYAN}▸ Backup Status${NC}"
    if [[ -d "$BACKUP_DIR" ]]; then
        backup_count=$(ls -1 "$BACKUP_DIR" 2>/dev/null | wc -l)
        latest=$(ls -t "$BACKUP_DIR" 2>/dev/null | head -1)
        echo -e "  ${GREEN}✓${NC} $BACKUP_DIR  ($backup_count files, latest: $latest)"
    else
        echo -e "  ${YELLOW}–${NC} No backups yet"
    fi

    # Show cache sizes
    echo ""
    echo -e "${CYAN}▸ Cache Sizes${NC}"
    for cache_dir in "$CLAUDE_DESKTOP_CACHE" "$CLAUDE_DESKTOP_CACHE2" "$CLAUDE_DESKTOP_GPU_CACHE" \
                     "$CLAUDE_DESKTOP_SW_CACHE" "$CLAUDE_DESKTOP_CODE_CACHE" "$HOME/.cache/claude"; do
        [[ -z "$cache_dir" ]] && continue
        if [[ -d "$cache_dir" ]]; then
            size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
            echo -e "  ${YELLOW}●${NC} $(basename "$cache_dir"): $size"
        fi
    done
    echo ""
}

# ── DISABLE MCP ─────────────────────────────────────────────────────────────

cmd_disable() {
    mkdir -p "$BACKUP_DIR"
    echo -e "${CYAN}▸ Backing up and disabling MCP servers...${NC}"
    echo ""

    local found=false
    for config_path in "$CLAUDE_DESKTOP_CONFIG" "$CLAUDE_CODE_CONFIG" "$CLAUDE_MCP_CONFIG"; do
        if [[ -f "$config_path" ]]; then
            found=true
            label=$(basename "$config_path")
            backup_file="$BACKUP_DIR/${label}.${TIMESTAMP}.bak"
            cp "$config_path" "$backup_file"
            echo -e "  ${GREEN}✓${NC} Backed up: $label → $backup_file"

            # Remove MCP servers from config
            python3 -c "
import json, sys
try:
    with open('$config_path', 'r') as f:
        d = json.load(f)
    # Handle both key formats
    for key in ['mcpServers', 'mcp_servers']:
        if key in d:
            count = len(d[key])
            d[key] = {}
            print(f'  Disabled {count} MCP servers in $label')
    with open('$config_path', 'w') as f:
        json.dump(d, f, indent=2)
except Exception as e:
    print(f'  Warning: Could not process $label: {e}', file=sys.stderr)
" 2>&1
        fi
    done

    if ! $found; then
        echo -e "  ${YELLOW}No config files found to process.${NC}"
    fi

    echo ""
    echo -e "${GREEN}Done.${NC} MCP servers disabled. Run ${CYAN}./claude-cleanup.sh restore${NC} to undo."
    echo ""
}

# ── RESTORE ─────────────────────────────────────────────────────────────────

cmd_restore() {
    if [[ ! -d "$BACKUP_DIR" ]] || [[ -z "$(ls -A "$BACKUP_DIR" 2>/dev/null)" ]]; then
        echo -e "${RED}No backups found.${NC}"
        return 1
    fi

    echo -e "${CYAN}▸ Restoring from most recent backups...${NC}"
    echo ""

    for config_name in "claude_desktop_config.json" "settings.json" "mcp.json"; do
        latest=$(ls -t "$BACKUP_DIR/${config_name}."*.bak 2>/dev/null | head -1)
        if [[ -n "$latest" ]]; then
            case "$config_name" in
                claude_desktop_config.json) target="$CLAUDE_DESKTOP_CONFIG" ;;
                settings.json) target="$CLAUDE_CODE_CONFIG" ;;
                mcp.json) target="$CLAUDE_MCP_CONFIG" ;;
            esac
            cp "$latest" "$target"
            echo -e "  ${GREEN}✓${NC} Restored: $config_name from $(basename "$latest")"
        fi
    done

    echo ""
    echo -e "${GREEN}Done.${NC} Restart Claude Desktop / Claude Code for changes to take effect."
    echo ""
}

# ── CACHE CLEAR ─────────────────────────────────────────────────────────────

cmd_cache() {
    echo -e "${CYAN}▸ Clearing Claude-related caches...${NC}"
    echo ""

    local cleared=0

    # All cache directories to clear (OS-aware, set at top of script)
    for cache_dir in "$CLAUDE_DESKTOP_CACHE" "$CLAUDE_DESKTOP_CACHE2" "$CLAUDE_DESKTOP_GPU_CACHE" \
                     "$CLAUDE_DESKTOP_SW_CACHE" "$CLAUDE_DESKTOP_CODE_CACHE" "$HOME/.cache/claude"; do
        [[ -z "$cache_dir" ]] && continue
        if [[ -d "$cache_dir" ]]; then
            local size=$(du -sh "$cache_dir" 2>/dev/null | cut -f1)
            rm -rf "$cache_dir"
            echo -e "  ${GREEN}✓${NC} Cleared $(basename "$cache_dir") ($size)"
            ((cleared++))
        fi
    done

    # Chrome/Brave/Edge Claude-specific localStorage & cookies (best-effort)
    if [[ "$OS" == "macos" ]]; then
        for browser_dir in \
            "$HOME/Library/Application Support/Google/Chrome" \
            "$HOME/Library/Application Support/BraveSoftware/Brave-Browser" \
            "$HOME/Library/Application Support/Microsoft Edge"; do
            if [[ -d "$browser_dir" ]]; then
                echo -e "  ${YELLOW}ℹ${NC} Found $(basename "$(dirname "$browser_dir")")/$(basename "$browser_dir") — browser cache must be cleared manually (Cmd+Shift+Del)"
            fi
        done
    fi

    if [[ $cleared -eq 0 ]]; then
        echo -e "  ${YELLOW}No caches found to clear.${NC}"
    fi

    echo ""
    echo -e "${GREEN}Done.${NC}"
    echo ""
}

# ── NUKE (FULL CLEANUP) ────────────────────────────────────────────────────

cmd_nuke() {
    local skip_confirm=false
    [[ "${2:-}" == "-y" || "${2:-}" == "--yes" ]] && skip_confirm=true

    echo -e "${RED}▸ FULL CLEANUP — disable MCP + clear cache + restart + open settings${NC}"
    echo ""

    if ! $skip_confirm; then
        read -p "This will disable all MCP servers and clear caches. Continue? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Aborted."
            return 0
        fi
    fi

    cmd_disable
    cmd_cache

    # Kill and restart Claude Desktop
    echo -e "${CYAN}▸ Restarting Claude Desktop...${NC}"
    if [[ "$OS" == "macos" ]]; then
        if pgrep -x "Claude" > /dev/null 2>&1; then
            osascript -e 'tell application "Claude" to quit' 2>/dev/null || pkill -x "Claude" 2>/dev/null
            echo -e "  ${GREEN}✓${NC} Quit Claude Desktop"
            sleep 2
        fi
        if [[ -d "$APP_PATH" ]]; then
            open "$APP_PATH" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Relaunched Claude Desktop"
        fi
    elif [[ "$OS" == "linux" ]]; then
        if pgrep -f "claude-desktop" > /dev/null 2>&1; then
            pkill -f "claude-desktop" 2>/dev/null && echo -e "  ${GREEN}✓${NC} Killed Claude Desktop"
            sleep 2
        fi
        if command -v claude-desktop &>/dev/null; then
            nohup claude-desktop &>/dev/null &
            echo -e "  ${GREEN}✓${NC} Relaunched Claude Desktop"
        fi
    fi

    # Auto-open settings page in default browser
    echo ""
    echo -e "${CYAN}▸ Opening claude.ai settings in your browser...${NC}"
    if $BROWSER_OPEN_CMD "https://claude.ai/settings/capabilities" 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} Opened claude.ai/settings/capabilities"
    else
        echo -e "  ${YELLOW}–${NC} Could not auto-open. Go to: https://claude.ai/settings/capabilities"
    fi

    echo ""
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${GREEN}  Automated cleanup complete${NC}"
    echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo ""
    cmd_manual
}

# ── MANUAL STEPS ────────────────────────────────────────────────────────────

cmd_manual() {
    echo -e "${YELLOW}▸ MANUAL STEPS (must be done in browser/app UI):${NC}"
    echo ""
    echo "  1. Open claude.ai/settings/capabilities"
    echo "  2. Toggle OFF:"
    echo "     □ Web Search"
    echo "     □ Extended Thinking"
    echo "     □ Analysis tool"
    echo "     □ All MCP connectors (cloud-side)"
    echo "  3. In any open chat, toggle OFF:"
    echo "     □ Web Search (chat-level toggle)"
    echo "     □ Extended Thinking (chat-level toggle)"
    echo "  4. Clear browser cache (Ctrl+Shift+Del)"
    echo "  5. Open a NEW chat and test file creation"
    echo ""
    echo "  After testing, re-enable tools ONE AT A TIME."
    echo ""
}

# ── DOCTOR ───────────────────────────────────────────────────────────────────

cmd_doctor() {
    echo -e "${CYAN}▸ Context Window Doctor${NC}"
    echo -e "  Estimating token usage across all configs..."
    echo ""

    python3 << 'PYEOF'
import json, os, sys

CONTEXT_WINDOW = 200000

# Token cost estimates per tool definition complexity
# Based on typical MCP server schema sizes
HEAVY_KEYWORDS = {
    "playwright": 8000, "browser": 7000, "puppeteer": 7000,
    "selenium": 7000, "brightdata": 6000, "hyperbrowser": 6000,
    "cloudflare": 5000, "supabase": 5000, "firebase": 5000,
    "notion": 4000, "github": 4000, "gitlab": 4000,
    "jira": 4000, "atlassian": 4000, "clickup": 4000,
    "salesforce": 5000, "hubspot": 4000, "airtable": 3500,
    "zapier": 4000, "n8n": 4000, "pipedream": 4000,
    "slack": 3500, "discord": 3500, "telegram": 3000,
    "gmail": 3500, "outlook": 3500, "email": 3000,
    "figma": 4000, "canva": 3500, "miro": 3500,
    "youtube": 3000, "twitter": 3000, "linkedin": 3000,
    "search": 3000, "exa": 3000, "tavily": 3000, "kagi": 3000,
    "context7": 2500, "memory": 2000, "supermemory": 2500,
}

DEFAULT_ESTIMATE = 3000  # tokens per unknown MCP server
LIGHTWEIGHT_THRESHOLD = 3000  # tokens — below this is "lightweight"

# Fixed feature costs (cloud-side, not in configs but for the report)
CLOUD_FEATURES = {
    "Web Search": 8000,
    "Extended Thinking": 8000,
    "Analysis Tool": 15000,
    "Code Execution": 8000,
    "Artifacts": 3000,
}

configs = [
    os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json"),
    os.path.expanduser("~/.config/Claude/claude_desktop_config.json"),
    os.path.expanduser("~/.claude/settings.json"),
    os.path.expanduser("~/.claude/mcp.json"),
]

all_servers = {}  # name -> {path, estimated_tokens, heavy}

for config_path in configs:
    if not os.path.isfile(config_path):
        continue
    try:
        with open(config_path) as f:
            data = json.load(f)
        for key in ["mcpServers", "mcp_servers"]:
            if key in data:
                for name, conf in data[key].items():
                    # Estimate tokens based on server name/type
                    tokens = DEFAULT_ESTIMATE
                    name_lower = name.lower()
                    for keyword, cost in HEAVY_KEYWORDS.items():
                        if keyword in name_lower:
                            tokens = cost
                            break
                    # Check if config has many tools defined (heavier)
                    if isinstance(conf, dict):
                        tools = conf.get("tools", [])
                        if len(tools) > 5:
                            tokens = int(tokens * 1.5)
                    all_servers[name] = {
                        "path": os.path.basename(config_path),
                        "tokens": tokens,
                        "heavy": tokens >= LIGHTWEIGHT_THRESHOLD,
                    }
    except Exception:
        pass

if not all_servers:
    print("  No MCP servers found in any config files.")
    print("  Your local configs are clean — check cloud connectors at claude.ai/settings/capabilities")
    sys.exit(0)

# Sort by token cost descending
sorted_servers = sorted(all_servers.items(), key=lambda x: x[1]["tokens"], reverse=True)

total_mcp_tokens = sum(s["tokens"] for _, s in sorted_servers)
heavy_servers = [(n, s) for n, s in sorted_servers if s["heavy"]]
light_servers = [(n, s) for n, s in sorted_servers if not s["heavy"]]

# Cloud features estimate
total_cloud = sum(CLOUD_FEATURES.values())

# Print report
print("\033[0;36m  ┌─────────────────────────────────────────────────────────────┐\033[0m")
print("\033[0;36m  │            CONTEXT WINDOW USAGE ESTIMATE                    │\033[0m")
print("\033[0;36m  └─────────────────────────────────────────────────────────────┘\033[0m")
print()

# Bar chart
mcp_pct = (total_mcp_tokens / CONTEXT_WINDOW) * 100
cloud_pct = (total_cloud / CONTEXT_WINDOW) * 100
remaining_pct = max(0, 100 - mcp_pct - cloud_pct)
remaining_tokens = max(0, CONTEXT_WINDOW - total_mcp_tokens - total_cloud)

bar_width = 50
mcp_bars = int(bar_width * mcp_pct / 100)
cloud_bars = int(bar_width * cloud_pct / 100)
remaining_bars = bar_width - mcp_bars - cloud_bars

print(f"  200K Context Window:")
print(f"  \033[0;31m{'█' * mcp_bars}\033[0;33m{'█' * cloud_bars}\033[0;32m{'░' * remaining_bars}\033[0m")
print(f"  \033[0;31m■\033[0m MCP Servers: ~{total_mcp_tokens:,} tokens ({mcp_pct:.0f}%)")
print(f"  \033[0;33m■\033[0m Cloud Features*: ~{total_cloud:,} tokens ({cloud_pct:.0f}%)")
print(f"  \033[0;32m░\033[0m Available: ~{remaining_tokens:,} tokens ({remaining_pct:.0f}%)")
print(f"  \033[0;90m  *if all enabled — Web Search, Thinking, Analysis, Code Exec, Artifacts\033[0m")
print()

if remaining_pct < 25:
    print(f"  \033[0;31m⚠ CRITICAL: Less than 25% context remaining for conversation!\033[0m")
elif remaining_pct < 50:
    print(f"  \033[1;33m⚠ WARNING: Less than 50% context available.\033[0m")
else:
    print(f"  \033[0;32m✓ Context usage looks manageable.\033[0m")
print()

# Per-server breakdown
print(f"\033[0;36m  ▸ MCP Servers ({len(all_servers)} total, ~{total_mcp_tokens:,} tokens)\033[0m")
print()

if heavy_servers:
    print(f"  \033[0;31m  Heavy (>{LIGHTWEIGHT_THRESHOLD} tokens each):\033[0m")
    for name, info in heavy_servers:
        bar = "█" * min(20, info["tokens"] // 500)
        print(f"    \033[0;31m{bar}\033[0m {info['tokens']:>5,}t  {name} ({info['path']})")
    print()

if light_servers:
    print(f"  \033[0;32m  Lightweight (<={LIGHTWEIGHT_THRESHOLD} tokens each):\033[0m")
    for name, info in light_servers:
        bar = "░" * min(20, info["tokens"] // 500)
        print(f"    \033[0;32m{bar}\033[0m {info['tokens']:>5,}t  {name} ({info['path']})")
    print()

# Recommendations
print(f"\033[0;36m  ▸ Recommendations\033[0m")
print()

if len(heavy_servers) > 0 and remaining_pct < 50:
    savings = sum(s["tokens"] for _, s in heavy_servers)
    new_remaining = remaining_tokens + savings
    new_pct = (new_remaining / CONTEXT_WINDOW) * 100
    print(f"  1. Disable {len(heavy_servers)} heavy server(s) to free ~{savings:,} tokens")
    print(f"     → Context available would increase from {remaining_pct:.0f}% to {new_pct:.0f}%")
    print(f"     Run: \033[0;36mclaude-fix slim -y\033[0m")
    print()

if len(all_servers) > 10:
    print(f"  2. You have {len(all_servers)} MCP servers — consider keeping only daily-use ones")
    print(f"     Enable others on-demand when needed")
    print()

print(f"  3. Check cloud connectors at claude.ai/settings/capabilities")
print(f"     Those add tokens too but aren't in local config files")
print()

PYEOF

    echo ""
}

# ── SLIM ────────────────────────────────────────────────────────────────────

cmd_slim() {
    local skip_confirm=false
    [[ "${2:-}" == "-y" || "${2:-}" == "--yes" ]] && skip_confirm=true

    echo -e "${CYAN}▸ Slim Mode — disable heavy connectors, keep lightweight ones${NC}"
    echo ""

    # First show what will happen
    python3 << 'PYEOF'
import json, os, sys

HEAVY_KEYWORDS = {
    "playwright": 8000, "browser": 7000, "puppeteer": 7000,
    "selenium": 7000, "brightdata": 6000, "hyperbrowser": 6000,
    "cloudflare": 5000, "supabase": 5000, "firebase": 5000,
    "notion": 4000, "github": 4000, "gitlab": 4000,
    "jira": 4000, "atlassian": 4000, "clickup": 4000,
    "salesforce": 5000, "hubspot": 4000, "airtable": 3500,
    "zapier": 4000, "n8n": 4000, "pipedream": 4000,
    "slack": 3500, "discord": 3500, "telegram": 3000,
    "gmail": 3500, "outlook": 3500, "email": 3000,
    "figma": 4000, "canva": 3500, "miro": 3500,
    "youtube": 3000, "twitter": 3000, "linkedin": 3000,
    "search": 3000, "exa": 3000, "tavily": 3000, "kagi": 3000,
    "context7": 2500, "memory": 2000, "supermemory": 2500,
}
DEFAULT_ESTIMATE = 3000
LIGHTWEIGHT_THRESHOLD = 3000

configs = [
    os.path.expanduser("~/Library/Application Support/Claude/claude_desktop_config.json"),
    os.path.expanduser("~/.config/Claude/claude_desktop_config.json"),
    os.path.expanduser("~/.claude/settings.json"),
    os.path.expanduser("~/.claude/mcp.json"),
]

heavy_count = 0
light_count = 0
heavy_names = []

for config_path in configs:
    if not os.path.isfile(config_path):
        continue
    try:
        with open(config_path) as f:
            data = json.load(f)
        for key in ["mcpServers", "mcp_servers"]:
            if key in data:
                for name in data[key]:
                    tokens = DEFAULT_ESTIMATE
                    name_lower = name.lower()
                    for keyword, cost in HEAVY_KEYWORDS.items():
                        if keyword in name_lower:
                            tokens = cost
                            break
                    if tokens >= LIGHTWEIGHT_THRESHOLD:
                        heavy_count += 1
                        heavy_names.append(name)
                    else:
                        light_count += 1
    except Exception:
        pass

if heavy_count == 0:
    print("  No heavy connectors found — your config is already slim.")
    sys.exit(1)

print(f"  Will DISABLE {heavy_count} heavy connector(s): {', '.join(heavy_names)}")
print(f"  Will KEEP {light_count} lightweight connector(s)")
PYEOF

    local preview_exit=$?
    if [[ $preview_exit -eq 1 ]]; then
        return 0
    fi

    echo ""

    if ! $skip_confirm; then
        read -p "  Proceed? [y/N] " -n 1 -r
        echo ""
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "  Aborted."
            return 0
        fi
    fi

    # Backup first
    mkdir -p "$BACKUP_DIR"

    for config_path in "$CLAUDE_DESKTOP_CONFIG" "$CLAUDE_CODE_CONFIG" "$CLAUDE_MCP_CONFIG"; do
        if [[ -f "$config_path" ]]; then
            label=$(basename "$config_path")
            backup_file="$BACKUP_DIR/${label}.${TIMESTAMP}.bak"
            cp "$config_path" "$backup_file"
            echo -e "  ${GREEN}✓${NC} Backed up: $label"

            python3 -c "
import json, sys

HEAVY_KEYWORDS = {
    'playwright': 8000, 'browser': 7000, 'puppeteer': 7000,
    'selenium': 7000, 'brightdata': 6000, 'hyperbrowser': 6000,
    'cloudflare': 5000, 'supabase': 5000, 'firebase': 5000,
    'notion': 4000, 'github': 4000, 'gitlab': 4000,
    'jira': 4000, 'atlassian': 4000, 'clickup': 4000,
    'salesforce': 5000, 'hubspot': 4000, 'airtable': 3500,
    'zapier': 4000, 'n8n': 4000, 'pipedream': 4000,
    'slack': 3500, 'discord': 3500, 'telegram': 3000,
    'gmail': 3500, 'outlook': 3500, 'email': 3000,
    'figma': 4000, 'canva': 3500, 'miro': 3500,
    'youtube': 3000, 'twitter': 3000, 'linkedin': 3000,
    'search': 3000, 'exa': 3000, 'tavily': 3000, 'kagi': 3000,
    'context7': 2500, 'memory': 2000, 'supermemory': 2500,
}
DEFAULT_ESTIMATE = 3000
LIGHTWEIGHT_THRESHOLD = 3000

try:
    with open('$config_path', 'r') as f:
        d = json.load(f)
    for key in ['mcpServers', 'mcp_servers']:
        if key in d:
            keep = {}
            removed = []
            for name, conf in d[key].items():
                tokens = DEFAULT_ESTIMATE
                name_lower = name.lower()
                for keyword, cost in HEAVY_KEYWORDS.items():
                    if keyword in name_lower:
                        tokens = cost
                        break
                if tokens < LIGHTWEIGHT_THRESHOLD:
                    keep[name] = conf
                else:
                    removed.append(name)
            d[key] = keep
            if removed:
                print(f'    Removed {len(removed)}: {', '.join(removed)}')
            if keep:
                print(f'    Kept {len(keep)}: {', '.join(keep.keys())}')
    with open('$config_path', 'w') as f:
        json.dump(d, f, indent=2)
except Exception as e:
    print(f'    Warning: {e}', file=sys.stderr)
" 2>&1
        fi
    done

    echo ""
    echo -e "${GREEN}Done.${NC} Heavy connectors disabled, lightweight ones preserved."
    echo -e "  Run ${CYAN}claude-fix restore${NC} to bring everything back."
    echo -e "  Run ${CYAN}claude-fix doctor${NC} to verify the improvement."
    echo ""
}

# ── MAIN ────────────────────────────────────────────────────────────────────

print_header

case "${1:-help}" in
    status)  cmd_status ;;
    doctor)  cmd_doctor ;;
    slim)    cmd_slim "$@" ;;
    disable) cmd_disable ;;
    restore) cmd_restore ;;
    cache)   cmd_cache ;;
    nuke)    cmd_nuke "$@" ;;
    manual)  cmd_manual ;;
    help|*)  show_help ;;
esac
