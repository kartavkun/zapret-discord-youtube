"""Integration checks in /tmp with stub nfqws and init service; no router writes."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='zapret-test-') as tmp:
    root = Path(tmp)
    project = root / 'project'
    project.mkdir()
    for name in ('install.sh', 'utils-zapret.sh', 'configs', 'hostlists', 'openwrt'):
        src = source / name
        if src.is_dir():
            shutil.copytree(src, project / name)
        else:
            shutil.copy2(src, project / name)
    target = root / 'zapret'
    (target / 'nfq').mkdir(parents=True)
    service = root / 'service'
    service.write_text('#!/bin/sh\n[ ! -e "' + str(root / 'reject-restart') + '" ]\n')
    service.chmod(0o755)
    nfqws = target / 'nfq/nfqws'
    nfqws.write_text('#!/bin/sh\n[ "$1" = --dry-run ] && [ "$2" = "--qnum=${EXPECTED_QNUM:-200}" ] && [ ! -e "' + str(root / 'reject-config') + '" ]\n')
    nfqws.chmod(0o755)
    common = project / 'openwrt/common.sh'
    common.write_text(common.read_text().replace('ZAPRET_DIR=/opt/zapret', f'ZAPRET_DIR={target}').replace('SERVICE=/etc/init.d/zapret', f'SERVICE={service}') + '\nrequire_router() { :; }\nfetch() { echo fake > "$2"; }\n')
    # Rewrite fixture paths, including the payload discovery pattern.
    for path in [project / 'install.sh', *list((project / 'configs').rglob('*'))]:
        if path.is_file():
            path.write_text(path.read_text().replace('/opt/zapret', str(target)))
    def run(*args, ok=True):
        result = subprocess.run(['sh', str(project / 'install.sh'), *args], capture_output=True, text=True)
        assert (result.returncode == 0) == ok, result.stdout + result.stderr
    (target / 'config').write_text('# original\n')
    (target / 'config.router').write_text('OPENWRT_LAN="lan guest"\n')
    (target / 'hostlists').mkdir()
    user = target / 'hostlists/list-general-user.txt'
    user.write_text('my.example\n')
    run('general (SIMPLE FAKE)')
    assert user.read_text() == 'my.example\n'
    assert (target / 'config.backup').read_text() == '# original\n'
    config = (target / 'config').read_text()
    assert 'OPENWRT_LAN="lan guest"' in config
    # Match the upstream service queue default and honour a router override.
    (target / 'config.router').write_text('OPENWRT_LAN="lan guest"\nQNUM=321\n')
    os.environ['EXPECTED_QNUM'] = '321'
    run('general')
    config = (target / 'config').read_text()
    (root / 'reject-config').touch()
    run('general', ok=False)
    assert (target / 'config').read_text() == config
    (root / 'reject-config').unlink()
    (root / 'reject-restart').touch()
    run('general', ok=False)
    assert (target / 'config').read_text() == config
    (root / 'reject-restart').unlink()
    run('../general', ok=False)
    for strategy in (project / 'configs').iterdir():
        if strategy.is_file() and strategy.name != 'config.base':
            run(strategy.name)
    print('PASS: all current strategies render; user lists, overrides, validation failure and restart rollback')
