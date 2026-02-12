# Architecture

## System Context

```mermaid
graph TB
    subgraph "User Environment"
        U[User Terminal]
        CD[Claude Desktop App]
        CB[Browser — claude.ai]
    end

    subgraph "claude-cleanup.sh"
        MAIN[Main Entrypoint] --> DETECT[OS Detection]
        DETECT --> PATHS[Config Path Resolution]
        PATHS --> CMD{Command Router}

        CMD --> STATUS[cmd_status]
        CMD --> DISABLE[cmd_disable]
        CMD --> RESTORE[cmd_restore]
        CMD --> CACHE[cmd_cache]
        CMD --> NUKE[cmd_nuke]
        CMD --> MANUAL[cmd_manual]
    end

    subgraph "Filesystem Targets"
        CFG1["Claude Desktop Config<br/>claude_desktop_config.json"]
        CFG2["Claude Code Settings<br/>settings.json"]
        CFG3["Claude Code MCP<br/>mcp.json"]
        CACHES["Cache Directories<br/>Cache/ GPUCache/ Code Cache/"]
        BACKUPS["Backups Directory<br/>backups/*.bak"]
    end

    U --> MAIN
    NUKE --> CD
    NUKE --> CB
    DISABLE --> CFG1
    DISABLE --> CFG2
    DISABLE --> CFG3
    DISABLE --> BACKUPS
    CACHE --> CACHES
    RESTORE --> BACKUPS
    RESTORE --> CFG1
    RESTORE --> CFG2
    RESTORE --> CFG3
```

## OS Detection Logic

```mermaid
flowchart TD
    A["$OSTYPE"] --> B{darwin*?}
    B -->|Yes| C[macOS paths]
    B -->|No| D{linux-gnu*?}
    D -->|Yes| E[Linux paths]
    D -->|No| F{msys/cygwin?}
    F -->|Yes| G[Windows paths]
    F -->|No| H[Fallback to Linux paths]

    C --> C1["~/Library/Application Support/Claude/"]
    C --> C2["open command for browser"]
    C --> C3["osascript for app control"]

    E --> E1["~/.config/Claude/"]
    E --> E2["xdg-open for browser"]
    E --> E3["pkill for app control"]
```

## Config File Schema

The script handles two JSON key formats for MCP servers:

```json
// Format 1: Claude Desktop
{
  "mcpServers": {
    "server-name": {
      "command": "...",
      "args": ["..."]
    }
  }
}

// Format 2: Claude Code
{
  "mcp_servers": {
    "server-name": {
      "url": "..."
    }
  }
}
```

The `disable` command sets both keys to `{}`. The `restore` command overwrites the entire file from backup.

## Backup Strategy

```mermaid
graph LR
    A[Original Config] -->|cp| B["backups/{filename}.{YYYYMMDD_HHMMSS}.bak"]
    B -->|restore: latest| A
    B -->|accumulates| C[Multiple Timestamped Backups]

    style B fill:#4ecdc4,color:#fff
```

Backups are timestamped to the second. The `restore` command always picks the most recent backup per config file using `ls -t | head -1`.

## Nuke Pipeline

```mermaid
stateDiagram-v2
    [*] --> CheckConfirmation
    CheckConfirmation --> Disable: -y flag or user confirms
    CheckConfirmation --> [*]: User declines

    Disable --> BackupConfigs
    BackupConfigs --> EmptyMCPServers
    EmptyMCPServers --> ClearCaches

    ClearCaches --> ClearDesktopCache
    ClearDesktopCache --> ClearGPUCache
    ClearGPUCache --> ClearCodeCache
    ClearCodeCache --> ClearServiceWorker

    ClearServiceWorker --> RestartApp
    RestartApp --> QuitClaude: macOS: osascript
    RestartApp --> KillClaude: Linux: pkill
    QuitClaude --> RelaunchClaude
    KillClaude --> RelaunchClaude

    RelaunchClaude --> OpenBrowser
    OpenBrowser --> PrintManualSteps
    PrintManualSteps --> [*]
```

## Dependencies

| Dependency | Purpose | Required |
|-----------|---------|:--------:|
| bash | Script runtime | ✅ |
| python3 | JSON parsing | ✅ |
| osascript | macOS app control | macOS only |
| pkill/pgrep | Process management | ✅ |
| open/xdg-open | Browser launch | Optional |
| du | Cache size reporting | ✅ |

## Security Considerations

The script operates only on local config files and caches. It never transmits data, accesses credentials, or modifies anything outside of Claude's config directories and the backup folder. Config backups may contain MCP server URLs and authentication tokens — the `backups/` directory is gitignored by default.
