"""Read-only CSV inventory for model provenance, without printing data rows."""
import argparse
import csv
import hashlib
import json
import math
from pathlib import Path


def inspect(path):
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    with path.open(encoding='utf-8-sig', newline='') as stream:
        reader = csv.DictReader(stream)
        columns = reader.fieldnames or []
        missing = dict.fromkeys(columns, 0)
        nonfinite = dict.fromkeys(columns, 0)
        group_column = 'trip_id' if 'trip_id' in columns else 'charge_id' if 'charge_id' in columns else None
        groups = set()
        seen = set()
        rows = duplicates = 0
        for row in reader:
            rows += 1
            if group_column:
                groups.add(row.get(group_column))
            signature = hashlib.sha256(json.dumps(row, sort_keys=True).encode()).digest()
            duplicates += signature in seen
            seen.add(signature)
            for column in columns:
                missing[column] += row.get(column, '').strip().lower() in {'', 'nan', 'null', 'none'}
                try:
                    nonfinite[column] += not math.isfinite(float(row[column]))
                except (ValueError, TypeError):
                    pass
    return {'file': path.name, 'sha256': digest.hexdigest(), 'rows': rows,
            'columns': columns, 'missing': missing, 'nonfinite': nonfinite,
            'duplicateRows': duplicates, 'groupColumn': group_column,
            'distinctGroups': len(groups),
            'provenanceVerified': False,
            'note': 'Schema/row inventory only; no origin, label truth or model quality certification.'}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('directories', nargs='+')
    args = parser.parse_args()
    result = [inspect(path) for directory in args.directories
              for path in sorted(Path(directory).glob('*.csv'))]
    print(json.dumps({'datasets': result}, ensure_ascii=False))


if __name__ == '__main__':
    main()
