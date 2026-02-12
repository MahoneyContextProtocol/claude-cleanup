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
    echo "  disable      Backup configs, then disable all MCP servers"
    echo "  restore      Restore configs from most recent backup"
    echo "  cache        Clear Claude-related caches"
    echo "  nuke [-y]    Full cleanup: disable + cache + restart + open settings"
    echo "  manual       Show manual steps checklist (web UI toggles)"
    echo "  help         Show this help message"
    echo ""
    echo "Flags:"
    echo "  -y, --yes    Skip confirmation prompts (for nuke)"
    echo ""
    echo "Examples:"
    echo "  ./claude-cleanup.sh nuke -y    # One-shot full cleanup, no prompts"
    echo "  ./claude-cleanup.sh status     # Check current state"
    echo "  ./claude-cleanup.sh restore    # Undo after testing"
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

# ── MAIN ────────────────────────────────────────────────────────────────────

print_header

case "${1:-help}" in
    status)  cmd_status ;;
    disable) cmd_disable ;;
    restore) cmd_restore ;;
    cache)   cmd_cache ;;
    nuke)    cmd_nuke "$@" ;;
    manual)  cmd_manual ;;
    help|*)  show_help ;;
esac
