"""Check package-manager bootstrap with an isolated PATH and fake commands."""
from pathlib import Path
import os
import subprocess
import tempfile

common = Path(__file__).resolve().parents[1] / 'openwrt/common.sh'
with tempfile.TemporaryDirectory(prefix='zapret-bootstrap-') as tmp:
    root = Path(tmp)
    for manager in ('opkg', 'apk'):
        bindir = root / manager
        bindir.mkdir()
        log = root / (manager + '.log')
        program = bindir / manager
        program.write_text('#!/bin/sh\necho "$*" >> "$CALL_LOG"\nexit "${PKG_EXIT:-0}"\n')
        program.chmod(0o755)
        # Source only the helper definitions, without entry-point path discovery.
        script = common.read_text().split('fail()', 1)[1]
        script = 'fail()' + script + '\nprepare_downloads\n'
        env = dict(os.environ, PATH=str(bindir), CALL_LOG=str(log))
        result = subprocess.run(['/bin/sh', '-c', script], env=env, capture_output=True)
        assert result.returncode == 0, result.stderr
        install = 'install' if manager == 'opkg' else 'add'
        assert log.read_text().splitlines() == ['update', install + ' ca-bundle curl']
        log.write_text('')
        result = subprocess.run(['/bin/sh', '-c', script], env=dict(env, PKG_EXIT='1'), capture_output=True)
        assert result.returncode != 0
        assert log.read_text().splitlines() == ['update']
    print('PASS: opkg/apk bootstrap and abort on index update failure')
