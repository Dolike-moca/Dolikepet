"""Prepare pinned Windows build dependencies; the Live2D SDK is supplied by you."""
from pathlib import Path
import argparse
import hashlib
import json
import shutil
import subprocess
import sys
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / '_tools/runtime/godot-build'
LOCK = json.loads((ROOT / 'Game/Godot/dependency-lock.json').read_text(encoding='utf-8'))


def run(*args, cwd=None):
    subprocess.run([str(a) for a in args], cwd=cwd or ROOT, check=True)


def extract(archive, destination):
    destination = destination.resolve()
    destination.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for info in z.infolist():
            target = (destination / info.filename).resolve()
            if not target.is_relative_to(destination) or (info.external_attr >> 16) & 0o170000 == 0o120000:
                raise ValueError('Unsafe archive entry')
        z.extractall(destination)


def download(url, destination):
    destination.parent.mkdir(parents=True, exist_ok=True)
    partial = destination.with_suffix(destination.suffix + '.part')
    print('Download:', url, flush=True)
    with urllib.request.urlopen(url, timeout=180) as response, partial.open('wb') as out:
        shutil.copyfileobj(response, out)
    partial.replace(destination)


def sha512(path):
    if not path.is_file():
        return None
    with path.open('rb') as f:
        return hashlib.file_digest(f, 'sha512').hexdigest()


def engine_download():
    version = LOCK['godot']['version']
    base = f'https://github.com/godotengine/godot-builds/releases/download/{version}'
    cache = BUILD / 'downloads'
    sums = cache / 'SHA512-SUMS.txt'
    download(base + '/SHA512-SUMS.txt', sums)
    hashes = {}
    for line in sums.read_text().splitlines():
        parts = line.split()
        if len(parts) >= 2 and len(parts[0]) == 128:
            hashes[parts[-1].lstrip('*')] = parts[0].lower()
    for name, destination in (
        (f'Godot_v{version}_win64.exe.zip', BUILD / 'godot'),
        (f'Godot_v{version}_export_templates.tpz', BUILD / 'template-archive'),
    ):
        if name not in hashes:
            raise ValueError('Missing official checksum: ' + name)
        archive = cache / name
        if sha512(archive) != hashes[name]:
            download(base + '/' + name, archive)
        if sha512(archive) != hashes[name]:
            raise ValueError('Checksum mismatch: ' + name)
        extract(archive, destination)
    copy_engine_templates(BUILD / 'godot', BUILD / 'template-archive/templates')


def copy_engine_templates(engine, templates):
    version = LOCK['godot']['version']
    sources = [(engine / f'Godot_v{version}_win64{suffix}.exe', BUILD / 'godot') for suffix in ('', '_console')]
    sources += [(templates / f'windows_{kind}_x86_64.exe', BUILD / 'export-templates') for kind in ('debug', 'release')]
    for source, directory in sources:
        if not source.is_file():
            raise FileNotFoundError(source)
        directory.mkdir(parents=True, exist_ok=True)
        target = directory / source.name
        if source.resolve() != target.resolve():
            shutil.copy2(source, target)


def checkout(name, destination):
    specification = LOCK[name]
    if not (destination / '.git').exists():
        if destination.exists() and any(destination.iterdir()):
            raise ValueError('Dependency destination is not an empty Git checkout: ' + str(destination))
        destination.mkdir(parents=True, exist_ok=True)
        run('git', 'init', destination)
        run('git', 'remote', 'add', 'origin', specification['source'], cwd=destination)
        run('git', 'fetch', '--depth=1', 'origin', specification['commit'], cwd=destination)
        run('git', 'checkout', '--detach', specification['commit'], cwd=destination)
    actual = subprocess.check_output(['git', '-C', str(destination), 'rev-parse', 'HEAD'], text=True).strip()
    if actual != specification['commit']:
        raise ValueError('Unexpected dependency revision: ' + name)


def main():
    p = argparse.ArgumentParser(description=__doc__)
    sdk = p.add_mutually_exclusive_group(required=True)
    sdk.add_argument('--sdk-zip', type=Path, help='Your official CubismSdkForNative-5-r.5.zip')
    sdk.add_argument('--sdk-dir', type=Path, help='Existing extracted CubismSdkForNative-5-r.5 directory')
    p.add_argument('--engine-dir', type=Path, help='Reuse your installed Godot 4.7.2 binaries (pair with --templates-dir)')
    p.add_argument('--templates-dir', type=Path, help='Reuse matching Windows export templates')
    args = p.parse_args()
    if bool(args.engine_dir) != bool(args.templates_dir):
        p.error('--engine-dir and --templates-dir must be supplied together')
    if sys.version_info < (3, 11):
        p.error('Python 3.11 or newer is required')
    BUILD.mkdir(parents=True, exist_ok=True)
    if args.sdk_zip:
        unpacked = BUILD / 'sdk-download'
        extract(args.sdk_zip, unpacked)
        matches = [x for x in unpacked.rglob('CubismSdkForNative-5-r.5') if (x / 'Core').is_dir()]
        if len(matches) != 1:
            raise ValueError('Expected exactly one CubismSdkForNative-5-r.5 directory')
        supplied_sdk = matches[0]
    else:
        supplied_sdk = args.sdk_dir.resolve()
    if supplied_sdk.name != 'CubismSdkForNative-5-r.5' or not all((supplied_sdk / x).is_dir() for x in ('Core', 'Framework')):
        raise ValueError('Supply the official Native 5-r.5 SDK containing Core and Framework')
    source = BUILD / 'gd_cubism'
    checkout('gd_cubism', source)
    checkout('godot_cpp', source / 'godot-cpp')
    target_sdk = source / 'thirdparty/CubismSdkForNative-5-r.5'
    if supplied_sdk.resolve() != target_sdk.resolve():
        shutil.copytree(supplied_sdk, target_sdk, dirs_exist_ok=True)
    # Do not initialize the older upstream Framework submodule; use Framework
    # from the same SDK as Core, as specified in dependency-lock.json.
    run(sys.executable, '-m', 'pip', 'install', '--target', BUILD / 'python', 'scons==' + LOCK['build']['scons'])
    if args.engine_dir:
        copy_engine_templates(args.engine_dir, args.templates_dir)
    else:
        engine_download()
    run(sys.executable, ROOT / 'Game/tools/manage.py', 'sync')
    print('Ready. Next: powershell -File tools/build.ps1 -Python <your-python.exe>')


if __name__ == '__main__':
    main()

