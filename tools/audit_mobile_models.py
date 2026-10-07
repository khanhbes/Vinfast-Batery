"""Inspect committed model bytes without executing pickle deserialization."""
import hashlib
import json
import pickletools
from pathlib import Path


def audit(path):
    payload = path.read_bytes()
    symbols = set()
    previous = []
    try:
        for opcode, argument, _ in pickletools.genops(payload):
            if opcode.name in ('GLOBAL',):
                symbols.add(str(argument))
            if opcode.name in ('SHORT_BINUNICODE', 'BINUNICODE', 'UNICODE'):
                previous.append(str(argument))
                previous = previous[-2:]
            if opcode.name == 'STACK_GLOBAL' and len(previous) == 2:
                symbols.add('.'.join(previous))
        format_status = 'pickle_opcodes_readable'
    except (ValueError, OSError):
        format_status = 'unrecognized_or_compressed_pickle'
    # Never expose array values or arbitrary strings from the artifact.
    classes = sorted(s for s in symbols if s.startswith(('sklearn.', 'numpy.', 'sklearn ', 'numpy ')))
    return {'artifact': str(path.relative_to(ROOT)), 'sha256': hashlib.sha256(payload).hexdigest(),
            'bytes': len(payload), 'formatStatus': format_status, 'librarySymbols': classes,
            'provenanceVerified': False, 'mobileCompatible': False,
            'reason': 'Requires trusted training metadata, mobile export and held-out parity/quality tests.'}


ROOT = Path(__file__).resolve().parents[1]
if __name__ == '__main__':
    artifacts = [ROOT / 'ev_soc_pipeline.pkl', ROOT / 'app/assets/models/ev_soc_pipeline.pkl',
                 ROOT / 'web/models/soc/v_legacy-1.pkl']
    print(json.dumps([audit(p) for p in artifacts if p.is_file()], ensure_ascii=False, indent=2))
