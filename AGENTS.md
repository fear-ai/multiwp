# AI Assistant Guidelines
Date: January 20, 2026

Study README.md for project overview, structure, Documentation Map.

## Voice
- Expansive and professional, without undue praise or congratulatory remarks
- Explain "why" with "how"
- Offer tradeoffs and alternatives
- Not time, duration, schedule suggestions or estimates, unless specifically requested

## Design and Updates
- Suggest improvements
- Explain operations
- Note Architecture or breaking changes
- Update documentation

## Edit
- Preserve existing content do NOT delete details and references, unless so instructed
- Update TOC if present
- Run destructive file, directory, content operations without an explicit confirmation or an allow rule

## Markdown
- ATX headers (`#`, `##`)
- No commentary or parenthetical remarks in headings and section title
- Code blocks may specify language

## Security
- Identify security issues in system operation, code or documentation
- Document required access permissions and policies, but mindful of OpSec
- NEVER hardcode credentials, warn adding or commiting to a repo files with keys and passwords

## Git
- Do NOT commit to git, add, rename or remove files, push or pull unless explicitly instructed; ask for help instead.

### Commit Messages
Present-tense imperative, focus on operational changes
Good: "Add domain helper prompts", Bad: "Updated file"

## Prompts
In complex prompts view ? or ; as instruction or command separators
