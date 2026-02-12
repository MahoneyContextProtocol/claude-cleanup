name: Config Bloat Monitor

on:
  # Run weekly on Mondays at 9am UTC
  schedule:
    - cron: '0 9 * * 1'
  # Manual trigger
  workflow_dispatch:
    inputs:
      threshold:
        description: 'Max MCP servers before warning'
        required: false
        default: '15'

jobs:
  check-config-bloat:
    runs-on: ubuntu-latest
    steps:
      - name: Check Claude configs
        id: check
        run: |
          THRESHOLD="${{ github.event.inputs.threshold || '15' }}"
          TOTAL=0
          REPORT=""
          CONFIGS_FOUND=0

          # Check all known config locations
          for CONFIG_PATH in \
            "$HOME/Library/Application Support/Claude/claude_desktop_config.json" \
            "$HOME/.config/Claude/claude_desktop_config.json" \
            "$HOME/.claude/settings.json" \
            "$HOME/.claude/mcp.json"; do

            if [ -f "$CONFIG_PATH" ]; then
              CONFIGS_FOUND=$((CONFIGS_FOUND + 1))
              COUNT=$(python3 -c "
          import json
          try:
              d = json.load(open('$CONFIG_PATH'))
              total = 0
              for k in ['mcpServers', 'mcp_servers']:
                  if k in d: total += len(d[k])
              print(total)
          except: print(0)
          " 2>/dev/null)
              TOTAL=$((TOTAL + COUNT))
              REPORT="${REPORT}\n  $(basename $CONFIG_PATH): ${COUNT} servers"
            fi
          done

          echo "total=$TOTAL" >> $GITHUB_OUTPUT
          echo "threshold=$THRESHOLD" >> $GITHUB_OUTPUT
          echo "configs_found=$CONFIGS_FOUND" >> $GITHUB_OUTPUT

          if [ $CONFIGS_FOUND -eq 0 ]; then
            echo "status=no_configs" >> $GITHUB_OUTPUT
            echo "No Claude config files found."
            exit 0
          fi

          echo -e "Config Bloat Report:$REPORT"
          echo -e "\nTotal MCP servers: $TOTAL (threshold: $THRESHOLD)"

          if [ $TOTAL -gt $THRESHOLD ]; then
            echo "status=bloated" >> $GITHUB_OUTPUT
            echo "⚠️ WARNING: $TOTAL MCP servers exceeds threshold of $THRESHOLD"
          else
            echo "status=ok" >> $GITHUB_OUTPUT
            echo "✅ MCP server count ($TOTAL) is within threshold ($THRESHOLD)"
          fi

      - name: Estimate token impact
        if: steps.check.outputs.status == 'bloated'
        run: |
          TOTAL=${{ steps.check.outputs.total }}
          # Conservative estimate: 3000 tokens per MCP server average
          ESTIMATED_TOKENS=$((TOTAL * 3000))
          PCT=$((ESTIMATED_TOKENS * 100 / 200000))
          REMAINING=$((200000 - ESTIMATED_TOKENS))

          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "  Token Impact Estimate"
          echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
          echo "  MCP servers: $TOTAL"
          echo "  Estimated token cost: ~${ESTIMATED_TOKENS} tokens (${PCT}% of 200K)"
          echo "  Remaining for conversation: ~${REMAINING} tokens"
          echo ""

          if [ $PCT -gt 50 ]; then
            echo "  🔴 CRITICAL: MCP servers consuming >50% of context window"
            echo "  Action: Run 'claude-fix slim -y' or 'claude-fix nuke -y'"
          elif [ $PCT -gt 30 ]; then
            echo "  🟡 WARNING: MCP servers consuming >30% of context window"
            echo "  Action: Run 'claude-fix doctor' to identify heaviest connectors"
          fi

      - name: Create issue if bloated
        if: steps.check.outputs.status == 'bloated'
        uses: actions/github-script@v7
        with:
          script: |
            const total = '${{ steps.check.outputs.total }}';
            const threshold = '${{ steps.check.outputs.threshold }}';
            const estimated = total * 3000;
            const pct = Math.round(estimated / 2000);

            // Check if there's already an open issue
            const issues = await github.rest.issues.listForRepo({
              owner: context.repo.owner,
              repo: context.repo.repo,
              state: 'open',
              labels: 'config-bloat'
            });

            if (issues.data.length > 0) {
              // Update existing issue
              await github.rest.issues.createComment({
                owner: context.repo.owner,
                repo: context.repo.repo,
                issue_number: issues.data[0].number,
                body: `**Weekly check:** Still at ${total} MCP servers (~${estimated.toLocaleString()} tokens, ${pct}% of context). Threshold: ${threshold}.`
              });
            } else {
              // Create new issue
              await github.rest.issues.create({
                owner: context.repo.owner,
                repo: context.repo.repo,
                title: `⚠️ Config Bloat: ${total} MCP servers detected`,
                body: `## Config Bloat Alert\n\n**MCP servers:** ${total} (threshold: ${threshold})\n**Estimated token cost:** ~${estimated.toLocaleString()} tokens (${pct}% of 200K context window)\n\n### Recommended Actions\n\n1. Run \`claude-fix doctor\` to see per-connector breakdown\n2. Run \`claude-fix slim -y\` to disable heavy connectors\n3. Or run \`claude-fix nuke -y\` for full cleanup\n\n*This issue was auto-generated by the Config Bloat Monitor workflow.*`,
                labels: ['config-bloat']
              });
            }
