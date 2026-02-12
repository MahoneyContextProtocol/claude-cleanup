# Claude Context Window Cleanup Toolkit

> One-command fix when Claude's context window gets exhausted before conversations start.

## Architecture Overview

```mermaid
graph TD
    A[User runs claude-fix] --> B{Command}
    B -->|nuke -y| C[Full Cleanup Pipeline]
    B -->|status| D[Diagnostics]
    B -->|restore| E[Restore from Backup]
    B -->|disable| F[Disable MCP Only]
    B -->|cache| G[Clear Caches Only]
    B -->|manual| H[Print Manual Steps]

    C --> C1[Backup Configs]
    C1 --> C2[Disable MCP Servers]
    C2 --> C3[Clear All Caches]
    C3 --> C4[Restart Claude Desktop]
    C4 --> C5[Open Settings Page]
    C5 --> C6[Print Manual Checklist]

    E --> E1[Find Latest Backup]
    E1 --> E2[Restore Config Files]
    E2 --> E3[User Restarts Apps]

    style C fill:#ff6b6b,color:#fff
    style D fill:#4ecdc4,color:#fff
    style E fill:#45b7d1,color:#fff
```

## Problem

```mermaid
graph LR
    subgraph "200K Token Context Window"
        A[MCP Connectors<br/>~30-50K tokens] --> B[Web Search<br/>~5-10K tokens]
        B --> C[Extended Thinking<br/>~5-10K tokens]
        C --> D[Analysis Tool<br/>~10-20K tokens]
        D --> E[Code Execution<br/>~5-10K tokens]
        E --> F[Remaining for<br/>Conversation<br/>⚠️ Often Too Small]
    end

    style A fill:#ff6b6b,color:#fff
    style B fill:#ff9f43,color:#fff
    style C fill:#ff9f43,color:#fff
    style D fill:#ff6b6b,color:#fff
    style E fill:#ff9f43,color:#fff
    style F fill:#ee5a24,color:#fff
```

When many tools and MCP connectors are enabled, they consume the context window **before any conversation begins**. This causes file creation failures, broken conversations, and degraded performance.

## Repository Structure

```
claude-cleanup/
├── claude-cleanup.sh        # Main cleanup script (bash, cross-platform)
├── SKILL.md                 # Claude Skill — teaches Claude to fix context issues
├── README.md                # This file
├── LICENSE                  # MIT License
├── .gitignore               # Excludes backups/ and .DS_Store
├── docs/
│   ├── ARCHITECTURE.md      # Technical deep-dive
│   └── TROUBLESHOOTING.md   # Common issues and fixes
└── backups/                 # Auto-created by script (gitignored)
    └── *.bak                # Timestamped config backups
```

## Quickstart

```bash
# Clone and install
git clone https://github.com/MulticloudMahoney/claude-cleanup.git ~/claude-cleanup
chmod +x ~/claude-cleanup/claude-cleanup.sh

# Add alias (zsh — default on macOS)
echo 'alias claude-fix="$HOME/claude-cleanup/claude-cleanup.sh"' >> ~/.zshrc && source ~/.zshrc

# Or bash
echo 'alias claude-fix="$HOME/claude-cleanup/claude-cleanup.sh"' >> ~/.bashrc && source ~/.bashrc
```

## Usage

### When Context Window Breaks

```bash
claude-fix nuke -y
```

Then toggle off cloud-side tools in the browser tab that auto-opens.

### Check Current State

```bash
claude-fix status
```

### Restore Everything

```bash
claude-fix restore
```

## Command Reference

```mermaid
graph LR
    subgraph "Diagnostic Commands"
        S[status] -->|shows| S1[OS detection]
        S -->|shows| S2[Config files + MCP count]
        S -->|shows| S3[Cache sizes]
        S -->|shows| S4[Backup status]
        M[manual] -->|prints| M1[UI checklist]
    end

    subgraph "Action Commands"
        D[disable] -->|step 1| D1[Backup configs]
        D1 -->|step 2| D2[Empty MCP servers]
        R[restore] -->|step 1| R1[Find latest .bak]
        R1 -->|step 2| R2[Overwrite configs]
        C[cache] -->|clears| C1[Desktop + Code + GPU caches]
    end

    subgraph "Combined"
        N["nuke [-y]"] -->|runs| D
        N -->|runs| C
        N -->|then| N1[Restart Desktop App]
        N1 -->|then| N2[Open Settings Page]
        N2 -->|then| M
    end

    style N fill:#ff6b6b,color:#fff
    style D fill:#45b7d1,color:#fff
    style R fill:#4ecdc4,color:#fff
```

| Command | Description | Destructive | Auto-backup |
|---------|-------------|:-----------:|:-----------:|
| `status` | Show config state, MCP count, cache sizes | No | — |
| `disable` | Backup configs → disable all MCP servers | Yes | ✅ |
| `restore` | Restore configs from latest backup | Yes | — |
| `cache` | Clear all Claude-related caches | Yes | — |
| `nuke [-y]` | Full reset: disable + cache + restart + open settings | Yes | ✅ |
| `manual` | Print manual UI steps checklist | No | — |

| Flag | Description |
|------|-------------|
| `-y` / `--yes` | Skip confirmation prompts (for `nuke`) |

## Automation vs Manual Scope

```mermaid
graph TB
    subgraph "✅ Automated by Script"
        A1[Local MCP config disable/restore]
        A2[Timestamped config backups]
        A3[Cache clearing — Desktop + Code + GPU]
        A4[Claude Desktop quit + relaunch]
        A5[Auto-open settings page in browser]
        A6[OS detection — macOS / Linux]
    end

    subgraph "❌ Manual — Web UI Only"
        M1[Cloud MCP connector toggles]
        M2[Web Search toggle]
        M3[Extended Thinking toggle]
        M4[Analysis tool toggle]
        M5[Code Execution toggle]
        M6[Browser cache — Cmd+Shift+Del]
    end

    style A1 fill:#4ecdc4,color:#fff
    style A2 fill:#4ecdc4,color:#fff
    style A3 fill:#4ecdc4,color:#fff
    style A4 fill:#4ecdc4,color:#fff
    style A5 fill:#4ecdc4,color:#fff
    style A6 fill:#4ecdc4,color:#fff
    style M1 fill:#ff6b6b,color:#fff
    style M2 fill:#ff6b6b,color:#fff
    style M3 fill:#ff6b6b,color:#fff
    style M4 fill:#ff6b6b,color:#fff
    style M5 fill:#ff6b6b,color:#fff
    style M6 fill:#ff6b6b,color:#fff
```

## Config File Locations

```mermaid
graph TD
    subgraph "macOS"
        MA["~/Library/Application Support/Claude/claude_desktop_config.json"]
        MB["~/.claude/settings.json"]
        MC["~/.claude/mcp.json"]
        MD["~/Library/Caches/com.anthropic.claude/"]
    end

    subgraph "Linux"
        LA["~/.config/Claude/claude_desktop_config.json"]
        LB["~/.claude/settings.json"]
        LC["~/.claude/mcp.json"]
        LD["~/.config/Claude/Cache/"]
    end

    style MA fill:#45b7d1,color:#fff
    style MB fill:#45b7d1,color:#fff
    style MC fill:#45b7d1,color:#fff
    style LA fill:#4ecdc4,color:#fff
    style LB fill:#4ecdc4,color:#fff
    style LC fill:#4ecdc4,color:#fff
```

## Data Flow

```mermaid
sequenceDiagram
    participant U as User
    participant S as claude-cleanup.sh
    participant FS as Filesystem
    participant CD as Claude Desktop
    participant BR as Browser

    U->>S: claude-fix nuke -y
    S->>FS: Backup config files → backups/*.bak
    S->>FS: Set mcpServers: {} in all configs
    S->>FS: rm -rf cache directories
    S->>CD: osascript quit / pkill
    S->>CD: open /Applications/Claude.app
    S->>BR: open claude.ai/settings/capabilities
    S->>U: Print manual steps checklist

    Note over U,BR: User toggles cloud settings manually

    U->>S: claude-fix restore
    S->>FS: Copy latest .bak → original config paths
    S->>U: Done — restart apps for changes
```

## Claude Skill

This repo includes a Claude Skill (`SKILL.md`) that teaches any Claude instance how to diagnose and fix context window exhaustion — no script install required.

### What the Skill Does

```mermaid
graph LR
    subgraph "Skill Capabilities"
        A[Diagnose] -->|identifies| A1[MCP server count]
        A -->|identifies| A2[Token-heavy features]
        B[Fix — Automated] -->|guides| B1[Script install + nuke]
        C[Fix — Manual] -->|walks through| C1[UI toggle checklist]
        D[Re-enable] -->|strategy| D1[One-at-a-time testing]
        E[Troubleshoot] -->|resolves| E1[Common post-fix issues]
    end

    style A fill:#4ecdc4,color:#fff
    style B fill:#45b7d1,color:#fff
    style C fill:#ff9f43,color:#fff
    style D fill:#4ecdc4,color:#fff
    style E fill:#ff6b6b,color:#fff
```

### Install as Custom Skill

**Option A — Claude Projects (claude.ai):**
1. Create a new Project (or open an existing one)
2. Add `SKILL.md` to Project Knowledge
3. Any conversation in that project now knows how to fix context issues

**Option B — Claude Code / Claude Desktop (local skill):**
```bash
# Create the skill directory
mkdir -p ~/.claude/skills/claude-context-cleanup

# Copy the skill file
cp ~/claude-cleanup/SKILL.md ~/.claude/skills/claude-context-cleanup/SKILL.md
```

**Option C — Share the `.skill` package:**

Download `claude-context-cleanup.skill` from [Releases](https://github.com/MahoneyContextProtocol/claude-cleanup/releases) and import it into any Claude instance that supports custom skills.

### Skill + Script Together

The skill knows about the script. If the script is installed, the skill guides users to run `claude-fix` commands. If not, it walks through manual diagnosis and fix steps. Either way works.

```mermaid
graph TD
    S[Skill detects context issue] --> Q{Script installed?}
    Q -->|Yes| A["Guide: claude-fix nuke -y"]
    Q -->|No| B[Walk through manual steps]
    A --> M[Remind: manual UI toggles]
    B --> M
    M --> T[Test in new chat]
    T --> R{Working?}
    R -->|Yes| E["Re-enable one at a time"]
    R -->|No| F[Escalate to Anthropic support]

    style A fill:#4ecdc4,color:#fff
    style B fill:#ff9f43,color:#fff
    style M fill:#ff6b6b,color:#fff
```

## Background

Built after experiencing persistent context window exhaustion with a large number of MCP connectors enabled. The Anthropic support team confirmed that enabled tools and features consume context window tokens before any conversation begins. This script streamlines the diagnostic and cleanup process.

Particularly useful for power users running many MCP integrations across Claude Desktop, Claude Code, and claude.ai simultaneously.

## Contributing

Issues and PRs welcome. The script is intentionally a single bash file with no dependencies beyond Python 3 (used for JSON parsing).

## License

[MIT](LICENSE)
