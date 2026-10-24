import re
src = open('README.md', encoding='utf-8').read().split('\n')
# Split into level-2 sections and numbered module sections
def section(title_re, level='## '):
    start = None
    for i, l in enumerate(src):
        if start is None and re.match(re.escape(level) + title_re, l): start = i
        elif start is not None and (l.startswith('## ') or (level == '### ' and re.match(r'### \d+\. ', l))):
            return src[start:i]
    return src[start:] if start is not None else None
mods = {}
cur = None
for l in src[src.index('## Modules') + 1:]:
    if l.startswith('## '): break
    m = re.match(r'### (\d+)\. (.*)', l)
    if m: cur = int(m.group(1)); mods[cur] = ['### ' + m.group(2)]; continue
    if cur: mods[cur].append(l)
def mod(n, sub=False):
    lines = mods[n][:]
    if sub:
        lines[0] = '#### ' + lines[0][4:].replace('Class — ', '')
        lines = [ ('#' + x) if x.startswith('### ') and i else x for i, x in enumerate(lines)]
    while lines and lines[-1] == '': lines.pop()
    return '\n'.join(lines) + '\n'
GROUPS = [
    ('Raid', [10, 7, (13, [14, 15, 16, 17, 18]), 12, 11, 22, 23, 24, 25, 26, 28, 29]),
    ('Guild & Social', [6, 9, 8, 30, 2, 4, 5]),
    ('Logging', [1, 3, 19, 21, 20, 27]),
    ('Interface', [31]),
]
out = []
out.append('Post Issues here - https://github.com/netwalker0099/watchingmachine/issues\nPlease include your full LUA error output.\n')
out.append('\n'.join(src[0:6]))
out.append('\n'.join(section('Overview')).rstrip() + '\n')
setup = section('Setup and characters')
setup[0] = '## Getting started: setup and characters'
out.append('\n'.join(setup).rstrip() + '\n')
for title, items in GROUPS:
    out.append('## ' + title + '\n')
    for it in items:
        if isinstance(it, tuple):
            out.append(mod(it[0]).replace('\n### Flyout buttons', '\n#### Flyout buttons'))
            for sub in it[1]: out.append(mod(sub, True))
        else:
            out.append(mod(it))
for name in ('Usage', 'Global Theme System', 'Error Logging', 'Installation', 'Saved Variables'):
    sec = section(name)
    out.append('\n'.join(sec).rstrip() + '\n')
text = '\n'.join(out)
text = re.sub(r'\n{3,}', '\n\n', text)
open('docs/CURSEFORGE-DESCRIPTION.md', 'w', encoding='utf-8').write(text)
print(len(text.split('\n')), 'lines')
