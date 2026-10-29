#!/bin/bash
GIT_SPEC="git+https://github.com/Horace-Maxwell/horosa-skill.git#subdirectory=horosa-skill"
UV_BIN="$(which uv 2>/dev/null || echo "$HOME/.local/bin/uv")"

if [ -x "$UV_BIN" ] && [ -n "$HOROSA_SKILL_DIR" ] && [ -d "$HOROSA_SKILL_DIR" ]; then
    "$UV_BIN" --directory "$HOROSA_SKILL_DIR" run horosa-skill tool run "$1" --stdin
elif which horosa-skill >/dev/null 2>&1; then
    horosa-skill tool run "$1" --stdin
elif [ -x "$UV_BIN" ]; then
    # 自动拉取 Git 源码运行
    "$UV_BIN" tool run --from "$GIT_SPEC" horosa-skill tool run "$1" --stdin
else
    echo '{"ok": false, "error": "请先安装 uv 或 horosa-skill: curl -LsSf https://astral.sh/uv/install.sh | sh"}'
    exit 1
fi
