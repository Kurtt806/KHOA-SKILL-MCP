# KHOA-SKILL-MCP — Agent Skills

Kho skill dùng chung cho coding agent. Mỗi skill nằm trong một thư mục có file `SKILL.md` theo chuẩn Agent Skills.

| Skill | Mô tả | Đường dẫn |
|---|---|---|
| devops | Chuẩn tách container, Dockerfile, docker-compose runtime, CI build/push GHCR, VPS chỉ pull + up | `devops/SKILL.md` |

## Cài vào dự án của bạn

### Cách 1 — script 1 lệnh (khuyên dùng)

**Linux / macOS:**
```bash
curl -fsSL https://raw.githubusercontent.com/Kurtt806/KHOA-SKILL-MCP/main/install.sh | bash
```

**Windows (PowerShell):**
```powershell
irm https://raw.githubusercontent.com/Kurtt806/KHOA-SKILL-MCP/main/install.ps1 | iex
```

Script tự cài vào `.opencode/skills/devops` của dự án hiện tại. Muốn cài thêm cho Claude/Codex:

```bash
curl -fsSL https://raw.githubusercontent.com/Kurtt806/KHOA-SKILL-MCP/main/install.sh | bash -s -- --all
```

### Cách 2 — clone rồi copy tay

**Linux / macOS:**
```bash
git clone https://github.com/Kurtt806/KHOA-SKILL-MCP.git /tmp/khoa-skills
mkdir -p .opencode/skills
cp -r /tmp/khoa-skills/devops .opencode/skills/devops
```

**Windows (PowerShell):**
```powershell
git clone https://github.com/Kurtt806/KHOA-SKILL-MCP.git $env:TEMP\khoa-skills
New-Item -ItemType Directory -Force .opencode\skills | Out-Null
Copy-Item -Recurse -Force $env:TEMP\khoa-skills\devops .opencode\skills\devops
```

### Cài cho agent khác

| Agent | Thư mục đích | Lệnh copy |
|---|---|---|
| OpenCode (project) | `.opencode/skills/devops` | `cp -r devops .opencode/skills/devops` |
| OpenCode (global) | `~/.config/opencode/skills/devops` | `cp -r devops ~/.config/opencode/skills/devops` |
| Claude Code (project) | `.claude/skills/devops` | `cp -r devops .claude/skills/devops` |
| Claude Code (global) | `~/.claude/skills/devops` | `cp -r devops ~/.claude/skills/devops` |
| Codex / generic | `.agents/skills/devops` | `cp -r devops .agents/skills/devops` |

## Kiểm tra sau khi cài

```bash
ls .opencode/skills/devops/SKILL.md
head -5 .opencode/skills/devops/SKILL.md
```

Mở `SKILL.md` thấy `name: devops` là cài thành công.

## Thêm skill mới

1. Tạo thư mục `<ten-skill>/SKILL.md` với frontmatter `name` + `description`.
2. Gửi PR. Không commit secret, file `.env`, hay binary lớn.
