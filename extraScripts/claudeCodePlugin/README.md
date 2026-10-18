# Hesabix for Claude Code

Hesabix is a Claude Code plugin that connects to the remote Hesabix MCP server and adds accounting workflows, reusable skills, and focused analysis agents.

## Requirements

- Claude Code with remote HTTP MCP and OAuth support.
- A Hesabix account with access to at least one business.
- Network access to `https://hsxn.hesabix.ir`.

The plugin contains no API key, access token, or password. Claude Code performs OAuth when the user authenticates the MCP server.

## Install for local development

From the repository root:

```powershell
claude --plugin-dir .\extraScripts\claudeCodePlugin
```

For a packaged release, extract the ZIP first, then point Claude Code at the extracted plugin directory:

```powershell
Expand-Archive .\extraScripts\hesabix-claude-code-1.0.1.zip .\hesabix-claude-code
claude --plugin-dir .\hesabix-claude-code
```

`--plugin-dir` takes a plugin directory, so do not pass the ZIP file directly. The archive extracts the plugin root (`.claude-plugin/`, `.mcp.json`, `skills/`, and `agents/`) into the target directory. For persistent installations and managed updates, use a Git marketplace.

In the Claude Code session:

1. Run `/mcp` and authenticate with Hesabix in the browser.
2. Sign in, select the intended business, and review the requested permissions on Hesabix's consent screen.
3. Confirm `/mcp` shows the Hesabix server connected.
4. Try `/hesabix:business-summary` or ask Claude to analyze a Hesabix report.

Claude Code supports project, local, and user plugin-install scopes. For an individual development session, `--plugin-dir` is convenient; for team use, publish the plugin via a Git marketplace and have each teammate install it.

## OAuth and permissions

The configured MCP URL is `https://hsxn.hesabix.ir/api/v1/ai/mcp`. Use this canonical URL in the plugin configuration. The legacy `arc.hesabix.ir` hostname is not used because it advertises `hsxn.hesabix.ir` as its OAuth issuer and resource, which can fail strict resource matching in OAuth clients.

The server uses OAuth authorization code with PKCE and Dynamic Client Registration. Its current OAuth metadata advertises public clients (`token_endpoint_auth_methods_supported: ["none"]`), PKCE `S256`, and the Hesabix scopes. The authenticated connection is pinned to the business selected during consent; the model cannot choose another tenant by passing an argument.

Read access is the normal starting point. Hesabix write operations require the separate `ai:tools:write` grant and owner consent in Hesabix. Claude's tool approval prompt is an additional client-side confirmation; it does not grant Hesabix write scope. A prompt from the model or a tool argument cannot elevate permissions.

For least privilege, approve read access unless a workflow truly needs a write action. If write access is granted, inspect the proposed action and its arguments in Claude Code before approving it. Revoke the Hesabix connection from Hesabix if access should end.

## Included components

- `skills/`: accounting analysis and task-specific workflows.
- `agents/`: business analysis and operation guidance.
- `.mcp.json`: remote Hesabix MCP endpoint using OAuth discovery.
- `.claude-plugin/plugin.json`: plugin metadata.

Skills cover business summaries, sales, inventory, receivables/payables, formal reports, CRM, workflows, external integrations, and user-confirmed operations. MCP prompts and the business overview resource are transcribed in `docs/mcp-prompts.md`.

The MCP tool list is dynamic. Hesabix filters it for the authenticated user, business, and granted scopes. Skills therefore guide Claude to discover current tools at runtime rather than assuming every account has the same tools.

For the checked-in source-level inventory of registered tools, per-tool Hesabix permissions, role declarations, read/write MCP scope classification, and the exact current MCP prompt/resource interface, see [`docs/registry-catalog.md`](docs/registry-catalog.md), [`docs/registry-catalog.json`](docs/registry-catalog.json), and [`docs/mcp-prompts.md`](docs/mcp-prompts.md). Regenerate the registry catalog after changing the API registry or Tool Manifest:

```powershell
python .\extraScripts\claudeCodePlugin\scripts\generate_registry_catalog.py
```

The catalog is an audit of source declarations. A live `tools/list` after OAuth is still needed to establish what a particular user can invoke.

## Validate and try changes

```powershell
claude plugin validate .\extraScripts\claudeCodePlugin --strict
claude --plugin-dir .\extraScripts\claudeCodePlugin
```

In the session, use `/mcp` to inspect the connection and `/reload-plugins` after editing plugin files. For the live MCP API behavior and deployment notes, see [`../../docs/AI_MCP_EXTERNAL_SERVER.md`](../../docs/AI_MCP_EXTERNAL_SERVER.md).

## Marketplace distribution

The `.claude-plugin/marketplace.json` in this folder is a starter catalog entry for a repository-local marketplace. For public or team distribution, host a marketplace repository and update its plugin source to this repository and subdirectory, then tag releases with matching semantic versions. The included relative source is suitable only when the marketplace file and plugin directory are hosted together in a layout that the Claude Code marketplace resolver supports.

Before public release, confirm the official product URL, support contact, license, hosting repository, and release process.
