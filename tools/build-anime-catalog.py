"""Build compact title/year/season mappings from two downloaded JSON snapshots.

Sources and attribution: SOURCES.txt. No network requests or personal data.
"""
from pathlib import Path
import argparse
import json

p = argparse.ArgumentParser(description=__doc__)
p.add_argument('--database', type=Path, required=True)
p.add_argument('--mapping', type=Path, required=True)
p.add_argument('--output', type=Path, default=Path(__file__).resolve().parents[1] / 'portable_config/data/anime-catalog.json')
args = p.parse_args()
catalog = {}
for row in json.loads(args.database.read_bytes())['data']:
    ids = [s.rsplit('/', 1)[-1] for s in row['sources'] if s.startswith('https://myanimelist.net/anime/')]
    if ids:
        catalog[ids[0]] = {'title': row['title'], 'year': row.get('animeSeason', {}).get('year'), 'type': row['type']}
for row in json.loads(args.mapping.read_bytes()):
    item = catalog.get(str(row.get('mal_id', '')))
    if not item:
        continue
    mapping = row.get('themoviedb_id', {})
    tv, movies = mapping.get('tv'), mapping.get('movie', [])
    if tv and isinstance(tv, int):
        item.update(tmdb_id=tv, kind='tv')
    elif len(movies) == 1 and isinstance(movies[0], int):
        item.update(tmdb_id=movies[0], kind='movie')
    else:
        continue
    for field, source in [('season', 'season'), ('offset', 'episode_offset')]:
        value = row.get(source, {}).get('tmdb')
        if isinstance(value, int):
            item[field] = value
args.output.parent.mkdir(parents=True, exist_ok=True)
args.output.write_text(json.dumps(catalog, ensure_ascii=False, separators=(',', ':')), encoding='utf-8')
print(f'{len(catalog)} anime records')
