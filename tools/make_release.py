# Build a tester zip of Watching Machine: only what the game loads (the toc,
# the files it lists, Bindings.xml, Media), from the committed files.
# Usage: python -I tools/make_release.py .   (writes release/WatchingMachine-<version>.zip)
import os, re, subprocess, sys, zipfile

repo = sys.argv[1]
os.chdir(repo)

def show(path):
    return subprocess.check_output(['git', 'show', 'HEAD:' + path])

toc = show('WatchingMachine.toc').decode('utf-8')
version = re.search(r'^## Version:\s*(\S+)', toc, re.M).group(1)
files = ['WatchingMachine.toc']
for line in toc.splitlines():
    line = line.strip()
    if line and not line.startswith('#'):
        files.append(line.replace('\\', '/'))
tracked = subprocess.check_output(['git', 'ls-files']).decode('utf-8').split()
files.append('Bindings.xml')
files += [f for f in tracked if f.startswith('Media/')]
missing = [f for f in files if f not in tracked]
if missing:
    sys.exit('missing from git: ' + ', '.join(missing))

os.makedirs('release', exist_ok=True)
out = os.path.join('release', 'WatchingMachine-%s.zip' % version)
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as z:
    for f in files:
        z.writestr('WatchingMachine/' + f, show(f))
print(out, len(files), 'files')
