# One version's section of CHANGELOG.md, for a release's notes (the
# packager posts it to CurseForge). Prints it; exits 1 if the version has
# no section.
# Usage: python3 -I tools/release_notes.py <version> [CHANGELOG.md]
import sys

version = sys.argv[1].lstrip('v')
path = sys.argv[2] if len(sys.argv) > 2 else 'CHANGELOG.md'
lines = open(path, encoding='utf-8').read().splitlines()

out, inside = [], False
for line in lines:
    if line.startswith('## '):
        if inside:
            break
        inside = line[3:].strip() == version
        if inside:
            out.append('# Watching Machine ' + version)
        continue
    if inside:
        if line.strip() == '---':
            break
        out.append(line)

if not inside and not out:
    sys.exit('CHANGELOG.md has no "## %s" section' % version)
while out and not out[-1].strip():
    out.pop()
print('\n'.join(out))
