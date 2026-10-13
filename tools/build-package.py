"""Overlay tracked source files on the verified clean public distribution."""
from pathlib import Path, PurePosixPath
import argparse
import hashlib
import subprocess
import zipfile

ROOT = Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--base', type=Path, required=True, help='Clean MPV-1.0.1.zip release asset')
args = parser.parse_args()
base = args.base.resolve()
checksums = (ROOT / 'releases/1.0.1/SHA256SUMS.txt').read_text().splitlines()
expected = next(line.split()[0] for line in checksums if line.split()[-1] == 'MPV-1.0.1.zip')
if hashlib.sha256(base.read_bytes()).hexdigest() != expected:
    raise SystemExit('The base ZIP is not the verified public release')
version = (ROOT / 'VERSION').read_text().strip()
out = ROOT / 'dist' / f'MPV-{version}.zip'
if out.resolve() == base:
    raise SystemExit('Input and output must be different files')

tracked = subprocess.check_output(['git', '-C', str(ROOT), 'ls-files', '-z']).decode('utf-8').split('\0')
folders = {'portable_config', 'LICENSES', 'SOURCES', 'mpv'}
files = {}
with zipfile.ZipFile(base) as archive:
    for item in archive.infolist():
        path = PurePosixPath(item.filename)
        if item.is_dir():
            continue
        if path.is_absolute() or '..' in path.parts or ':' in item.filename or path.parts[0] != 'MPV-1.0.1':
            raise SystemExit('Unexpected archive entry')
        files[PurePosixPath(*path.parts[1:]).as_posix()] = archive.read(item)

for name in tracked:
    if not name:
        continue
    path = PurePosixPath(name)
    if path.parts[0] in folders or (len(path.parts) == 1 and path.suffix in {'.cmd', '.txt'}):
        files[name] = (ROOT / name).read_bytes()

# Public packages must never inherit personal server credentials.
ts = files['portable_config/script-opts/torrserver-loader.conf'].decode('utf-8-sig')
settings = {}
for line in ts.splitlines():
    if line.strip() and not line.lstrip().startswith('#') and '=' in line:
        key, value = line.split('=', 1)
        settings[key.strip()] = value.strip()
if settings.get('host') not in {'127.0.0.1', 'localhost'}:
    raise SystemExit('Use a localhost TorrServer configuration for public builds')
for key, value in settings.items():
    if any(word in key.lower() for word in ('user', 'login', 'pass', 'token', 'secret')) and value:
        raise SystemExit('Remove personal TorrServer credentials before packaging')
titles = files['portable_config/script-opts/readable_titles.conf'].decode('utf-8-sig')
for line in titles.splitlines():
    if line.strip().startswith('tmdb_api_key=') and line.split('=', 1)[1].strip():
        raise SystemExit('Remove the personal TMDB token before packaging')

out.parent.mkdir(exist_ok=True)
with zipfile.ZipFile(out, 'w', compression=zipfile.ZIP_DEFLATED, compresslevel=6) as archive:
    for name, content in sorted(files.items()):
        archive.writestr(f'MPV-{version}/{name}', content)
digest = hashlib.sha256(out.read_bytes()).hexdigest()
Path(str(out) + '.sha256').write_text(f'{digest}  {out.name}\n', encoding='ascii')
print(f'{out.name}: {len(files)} files, SHA-256 {digest}')
