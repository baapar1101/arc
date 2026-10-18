# Hesabix ChatGPT MCP plugin

This package declares the Hesabix remote MCP server and its OAuth connection. The canonical MCP endpoint is `https://hsxn.hesabix.ir/api/v1/ai/mcp`; OAuth uses discovery and prefers Client Identifier Metadata Documents (CIMD), with Dynamic Client Registration supported by the server as a fallback.

## Connect directly in ChatGPT

In ChatGPT web, open **Plugins**, choose **Add custom MCP server**, and enter the canonical endpoint above. Continue through OAuth, sign in to Hesabix, select a business, and approve only the requested scopes. Read access is the default; write access requires explicit owner consent in Hesabix.

## Build the plugin ZIP

From the repository root, run:

```sh
python3 extraScripts/build_mcp_plugins.py
```

The ChatGPT release ZIP is `plugin-1.0.1.zip` in this directory. The old `plugin-1.0.0.zip` path is kept as a compatibility download alias and contains the same 1.0.1 package so the currently deployed connector page continues to serve the fixed configuration. Both use the portable Agent Plugins manifest and MCP configuration format and contain no credentials. Public publication still requires completing OpenAI's MCP connection, domain verification, scan, and review steps.

The WordPress connector page source is in `wordpress-page/`. Its download link is intended for plugin publishers; end users should use **Add custom MCP server** instead of uploading the ZIP as a way to create a personal connection.
