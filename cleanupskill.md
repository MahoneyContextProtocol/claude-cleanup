---
name: claude-context-cleanup
description: Diagnose and fix Claude context window exhaustion caused by too many enabled tools, MCP connectors, and features. Use when conversations fail before starting, file creation breaks, or context window is full. Guides users through automated MCP config disable/restore, cache clearing, and manual UI toggles. Works on macOS and Linux.
---

# Claude Context Window Cleanup

A skill for diagnosing and fixing context window exhaustion in Claude Desktop, Claude Code, and claude.ai.

## When to Use This Skill

Use this skill when the user reports any of:
- "Context window is full/exhausted"
- "File creation is broken/failing"
- "Claude can't create files"
- "Conversation breaks before it starts"
- "Too many tokens used before I type anything"
- "MCP connectors are eating my context"
- General performance degradation with many tools enabled

## Root Cause

Claude's 200K token context window is shared between system prompts, tool definitions, and conversation content. Each enabled feature consumes tokens before the user types anything:

| Feature | Approximate Token Cost |
|---------|----------------------|
| MCP Connectors (each) | 2-5K tokens |
| Web Search | 5-10K tokens |
| Extended Thinking | 5-10K tokens |
| Analysis Tool | 10-20K tokens |
| Code Execution | 5-10K tokens |

With many MCP connectors (20+), the context window can be mostly consumed before any conversation begins.

## Diagnosis

### Step 1: Check Current State

Ask the user to run (or run for them if you have terminal access):

```bash
# If the cleanup script is installed:
claude-fix status

# If not installed, check manually:
# macOS:
python3 -c "
import json
for p in ['$HOME/Library/Application Support/Claude/claude_desktop_config.json', '$HOME/.claude/settings.json', '$HOME/.claude/mcp.json']:
    try:
        d = json.load(open(p))
        for k in ['mcpServers', 'mcp_servers']:
            if k in d: print(f'{p}: {len(d[k])} MCP servers')
    except: pass
"

# Linux:
python3 -c "
import json
for p in ['$HOME/.config/Claude/claude_desktop_config.json', '$HOME/.claude/settings.json', '$HOME/.claude/mcp.json']:
    try:
        d = json.load(open(p))
        for k in ['mcpServers', 'mcp_servers']:
            if k in d: print(f'{p}: {len(d[k])} MCP servers')
    except: pass
"
```

### Step 2: Identify Token Hogs

The biggest offenders in order:
1. **Cloud MCP connectors** (claude.ai/settings/capabilities) — each one adds tool definitions
2. **Analysis tool** — large system prompt overhead
3. **Extended Thinking** — reserves context space
4. **Web Search** — tool definitions + result handling
5. **Code Execution** — tool definitions + sandbox overhead

## Fix — Automated (Script)

If the user has the cleanup script installed (`~/claude-cleanup/claude-cleanup.sh`), guide them:

```bash
# Full cleanup — one command
claude-fix nuke -y

# This automatically:
# 1. Backs up all MCP configs (timestamped)
# 2. Disables all local MCP servers
# 3. Clears all Claude caches
# 4. Restarts Claude Desktop
# 5. Opens claude.ai/settings/capabilities in browser
```

Then remind them of the manual steps (see below).

To restore after testing:
```bash
claude-fix restore
```

### Installing the Script

If the user doesn't have the script, help them install it:

```bash
git clone https://github.com/MahoneyContextProtocol/claude-cleanup.git ~/claude-cleanup
chmod +x ~/claude-cleanup/claude-cleanup.sh
echo 'alias claude-fix="$HOME/claude-cleanup/claude-cleanup.sh"' >> ~/.zshrc  # or ~/.bashrc
source ~/.zshrc
```

## Fix — Manual Steps

These MUST be done in the web UI regardless of whether the script is used:

### In claude.ai/settings/capabilities:
1. Toggle **OFF** all MCP connectors
2. Toggle **OFF** Analysis tool
3. Toggle **OFF** Web Search (if not needed)
4. Toggle **OFF** Extended Thinking (if not needed)
5. Toggle **OFF** Code Execution (if not needed)

### In any open chat:
1. Toggle **OFF** Web Search (chat-level)
2. Toggle **OFF** Extended Thinking (chat-level)

### Browser cleanup:
1. Clear browser cache (Cmd+Shift+Del / Ctrl+Shift+Del)
2. Open a **completely new chat** (old chats retain old context)

### In Claude Desktop app:
1. Quit and reopen the app
2. Check the same settings

## Re-enabling Tools

After confirming the fix works:
1. Re-enable tools **one at a time**
2. Test in a **new chat** after each
3. When it breaks again, the last tool enabled is the culprit
4. Keep that tool disabled, continue enabling others

## Script Command Reference

| Command | Description |
|---------|-------------|
| `claude-fix status` | Show config files, MCP count, cache sizes |
| `claude-fix disable` | Backup configs → disable all MCP servers |
| `claude-fix restore` | Restore configs from latest backup |
| `claude-fix cache` | Clear all Claude-related caches |
| `claude-fix nuke [-y]` | Full reset: disable + cache + restart + open settings |
| `claude-fix manual` | Print manual UI steps checklist |

## Config File Locations

### macOS
| Config | Path |
|--------|------|
| Claude Desktop | `~/Library/Application Support/Claude/claude_desktop_config.json` |
| Claude Code settings | `~/.claude/settings.json` |
| Claude Code MCP | `~/.claude/mcp.json` |
| Desktop cache | `~/Library/Caches/com.anthropic.claude/` |
| Desktop app cache | `~/Library/Application Support/Claude/Cache/` |

### Linux
| Config | Path |
|--------|------|
| Claude Desktop | `~/.config/Claude/claude_desktop_config.json` |
| Claude Code settings | `~/.claude/settings.json` |
| Claude Code MCP | `~/.claude/mcp.json` |
| Desktop cache | `~/.config/Claude/Cache/` |

## Troubleshooting

### "I disabled everything but it's still broken"
- Make sure you're in a **new chat** — old chats retain their context allocation
- Check if the Claude Desktop app was restarted (not just the browser)
- Clear browser cache completely

### "claude-fix command not found"
- Open a new terminal tab (aliases load on startup)
- Or run: `source ~/.zshrc`
- Check: `grep claude-fix ~/.zshrc`

### "Restore didn't bring back all my servers"
- Check backups: `ls -la ~/claude-cleanup/backups/`
- The restore command picks the most recent backup per file
- For a specific backup: `cp ~/claude-cleanup/backups/filename.TIMESTAMP.bak /original/path/`

### "python3 not found"
- macOS: `xcode-select --install`
- Linux: `sudo apt install python3`
