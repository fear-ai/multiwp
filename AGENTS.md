# AI Assistant Guidelines
Date: January 5, 2026

*Instructions for AI assistants working with this repository.*

## Project Type

WordPress multisite hosting project. Read README.md first for project overview and structure.

## Documentation Philosophy

Use the Documentation Map in `README.md` for authoritative sources, and do not duplicate content.

## Shell Script Conventions

See `scripts/Shell.md` for detailed conventions. Key points:
- Use `common.sh` library functions
- Run as ubuntu with sudo (never as root)
- 4-space indent, quote variables
- Scripts in kebab-case, functions in lowercase_with_underscores

## Documentation Style

### Markdown
- ATX headers (`#`, `##`)
- No commentary in headings
- Code blocks specify language

### Voice
- Expansive and professional
- Explain "why" with "how"
- Document tradeoffs and alternatives

### Updates
- Read current file first
- Preserve existing content unless changing
- Update TOC if present
- Don't delete material unless instructed

## Security

- Validate inputs before system operations
- Never hardcode credentials
- Document required permissions (e.g., ssl-cert group)

## Git Behavior

Do not run git commands or update repositories unless explicitly instructed; ask for help instead.

## Commit Messages

Present-tense imperative, focused on operational changes:
- Good: "Add domain helper prompts"
- Bad: "Updated file"

## AI Boundaries

### Do
- Suggest improvements
- Identify security issues
- Update documentation
- Explain operations

### Ask About
- Architecture changes
- Operational procedure modifications
- Breaking changes

### Never Do Automatically
- Commit to git
- Run destructive operations
- Modify production configs
- Change DNS/Cloudflare
- Alter database (unless documented procedure)
