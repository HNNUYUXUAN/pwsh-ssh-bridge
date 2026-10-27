"""Validate and package the source workspace using Python's standard library."""
import argparse
import hashlib
import json
from pathlib import Path
import re
import zipfile

ROOT = Path(__file__).resolve().parents[1]
RUNTIME_FILES = ('SKILL.md', 'README.md', 'README.zh-CN.md', 'LICENSE', 'VERSION')
RUNTIME_DIRS = ('scripts', 'references', 'agents')
WORKSPACE_FILES = ('AGENTS.md', '.gitignore', '.gitattributes')
WORKSPACE_DIRS = ('dev', 'docs', 'tests', '.github')
SUFFIXES = {'.md', '.ps1', '.psm1', '.py', '.yaml', '.yml'}


def inventory(root=ROOT, workspace=False):
    names = list(RUNTIME_FILES) + (list(WORKSPACE_FILES) if workspace else [])
    for directory in RUNTIME_DIRS + (WORKSPACE_DIRS if workspace else ()):
        base = root / directory
        if not base.is_dir() or base.is_symlink():
            raise ValueError(f'Missing or symlink source directory: {directory}')
        for path in base.rglob('*'):
            if path.is_symlink():
                raise ValueError('Symlink in source: ' + path.relative_to(root).as_posix())
            if path.is_file() and '__pycache__' not in path.parts:
                if path.suffix not in SUFFIXES:
                    raise ValueError('Unexpected source file: ' + path.relative_to(root).as_posix())
                names.append(path.relative_to(root).as_posix())
    result = {}
    for name in sorted(names):
        path = root / name
        if path.is_symlink() or not path.is_file():
            raise ValueError('Missing or symlink source file: ' + name)
        raw = path.read_bytes()
        text = raw.decode('utf-8')
        if re.search(r'-----BEGIN (?:OPENSSH |RSA |EC |DSA )?PRIVATE KEY-----', text):
            raise ValueError('Private key content in: ' + name)
        # Git checkouts may have CRLF. Artifacts have normalized UTF-8/LF content.
        result[name] = text.replace('\r\n', '\n').encode('utf-8')
    return result


def validate(files):
    skill = files['SKILL.md'].decode()
    if not skill.startswith('---\n') or '\nname: pwsh-ssh-bridge\n' not in skill:
        raise ValueError('Invalid skill name/frontmatter')
    if not re.search(r'^description: .+', skill, re.M):
        raise ValueError('Missing skill description')
    if not re.fullmatch(r'\d+\.\d+\.\d+', files['VERSION'].decode().strip()):
        raise ValueError('VERSION must be X.Y.Z')
    for name, raw in files.items():
        if not name.endswith('.md'):
            continue
        for target in re.findall(r'\]\(([^)]+)\)', raw.decode()):
            if target.startswith(('https:', 'http:', 'mailto:', '#')):
                continue
            # Normalize relative links without accessing files outside the package.
            import posixpath
            normalized = posixpath.normpath(posixpath.join(posixpath.dirname(name), target.split('#')[0]))
            if normalized not in files:
                raise ValueError(f'Broken package link in {name}: {target}')


def write_zip(path, files):
    # Fixed timestamps/order/permissions and stored bytes make builds reproducible
    # without depending on the machine's zlib version.
    with zipfile.ZipFile(path, 'w', compression=zipfile.ZIP_STORED) as archive:
        for name, data in sorted(files.items()):
            entry = zipfile.ZipInfo('pwsh-ssh-bridge/' + name, (2020, 1, 1, 0, 0, 0))
            entry.create_system = 3
            entry.external_attr = 0o100644 << 16
            archive.writestr(entry, data)
    with zipfile.ZipFile(path) as archive:
        if archive.testzip() is not None or len(archive.namelist()) != len(files):
            raise ValueError('Archive readback failed')
        for name, data in files.items():
            if archive.read('pwsh-ssh-bridge/' + name) != data:
                raise ValueError('Archive content mismatch')


def build(output_dir, root=ROOT):
    runtime = inventory(root)
    workspace = inventory(root, workspace=True)
    validate(runtime)
    validate(workspace)
    version = runtime['VERSION'].decode().strip()
    output_dir.mkdir(parents=True, exist_ok=True)
    hashes = {}
    for kind, files in (('skill', runtime), ('workspace', workspace)):
        name = f'pwsh-ssh-bridge-{version}-{kind}.zip'
        destination = output_dir / name
        write_zip(destination, files)
        hashes[name] = hashlib.sha256(destination.read_bytes()).hexdigest()
    manifest = {'name': 'pwsh-ssh-bridge', 'version': version, 'archives': hashes,
                'sourceFiles': {name: hashlib.sha256(data).hexdigest() for name, data in workspace.items()}}
    (output_dir / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8')
    (output_dir / 'SHA256SUMS').write_text(''.join(f'{digest}  {name}\n' for name, digest in hashes.items()), encoding='utf-8')
    return manifest


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='validate both inventories without writing packages')
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'dist')
    args = parser.parse_args()
    if args.check:
        for is_workspace in (False, True):
            validate(inventory(workspace=is_workspace))
        print('Runtime and development workspace validation passed.')
    else:
        result = build(args.output_dir)
        print(json.dumps({'version': result['version'], 'archives': result['archives']}, indent=2))
