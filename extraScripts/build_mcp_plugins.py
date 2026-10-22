#!/usr/bin/env python3
"""Build the distributable ChatGPT and Claude Code MCP plugin archives."""

from __future__ import annotations

from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile


ROOT = Path(__file__).resolve().parent


def add_tree(archive: ZipFile, folder: Path, relative: Path) -> None:
    for path in sorted(folder.rglob("*")):
        if path.is_file():
            archive.write(path, (relative / path.relative_to(folder)).as_posix())


def build_chatgpt() -> None:
    folder = ROOT / "chatgptPlugin"
    output = folder / "plugin-1.0.1.zip"
    package_files = ("plugin.json", "mcp.json", ".mcp.json")
    for target in (output, folder / "plugin-1.0.0.zip"):
        with ZipFile(target, "w", ZIP_DEFLATED) as archive:
            for name in package_files:
                archive.write(folder / name, name)
            add_tree(archive, folder / ".codex-plugin", Path(".codex-plugin"))
            add_tree(archive, folder / "assets", Path("assets"))
        print(target)


def build_claude() -> None:
    folder = ROOT / "claudeCodePlugin"
    output = folder / "claude-plugin-1.0.1.zip"
    with ZipFile(output, "w", ZIP_DEFLATED) as archive:
        for name in (".mcp.json", "README.md"):
            archive.write(folder / name, name)
        for name in (".claude-plugin", "agents", "docs", "scripts", "skills"):
            add_tree(archive, folder / name, Path(name))
    distribution = ROOT / "hesabix-claude-code-1.0.1.zip"
    distribution.write_bytes(output.read_bytes())
    print(output)
    print(distribution)


if __name__ == "__main__":
    build_chatgpt()
    build_claude()
