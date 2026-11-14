"""Exercise the standalone downloader using local archives and fake networking."""
from pathlib import Path
import os
import subprocess
import tarfile
import tempfile

source = Path(__file__).resolve().parents[1]
with tempfile.TemporaryDirectory(prefix='zapret-download-') as tmp:
    root = Path(tmp)
    router = root / 'router'
    router.mkdir()
    project = router / 'zapret-configs'
    project.mkdir()
    (project / 'keep').write_text('old checkout')
    fixture = root / 'zapret-discord-youtube-openwrt'
    (fixture / 'openwrt').mkdir(parents=True)
    (fixture / 'configs').mkdir()
    for name in ('install.sh', 'utils-zapret.sh', 'openwrt/common.sh', 'configs/config.base'):
        (fixture / name).touch()
    (fixture / 'setup.sh').write_text('read -r answer\nprintf "%s:%s" "$answer" "$1" > "' + str(root / 'result') + '"\n')
    archive = root / 'archive.tar.gz'
    with tarfile.open(archive, 'w:gz') as tar:
        tar.add(fixture, arcname=fixture.name)
    bindir = root / 'bin'
    bindir.mkdir()
    for name, content in {
        'apk': 'exit 0',
        'curl': 'while [ "$1" != -o ]; do shift; done\ncp "$ARCHIVE" "$2"',
    }.items():
        cmd = bindir / name
        cmd.write_text('#!/bin/sh\n' + content + '\n')
        cmd.chmod(0o755)
    terminal = root / 'tty'
    terminal.write_text('yes\n')
    script = (source / 'bootstrap.sh').read_text().replace('[ -f /etc/openwrt_release ]', 'true').replace('[ "$(id -u)" = 0 ]', 'true').replace('/root/', str(router) + '/').replace('/dev/tty', str(terminal))
    # Feed the loader on stdin just as curl | sh would; installer uses tty.
    result = subprocess.run(['sh', '-s', '--', '/mnt/usb/zapret'], input=script, text=True, capture_output=True, env=dict(os.environ, PATH=str(bindir) + ':' + os.environ['PATH'], ARCHIVE=str(archive)))
    assert result.returncode == 0, result.stderr
    assert (root / 'result').read_text() == 'yes:/mnt/usb/zapret'
    assert len(list(router.glob('zapret-configs.backup.*/project/keep'))) == 1
    assert (project / 'setup.sh').exists()
    assert not list(router.glob('.zapret-configs.*'))
    print('PASS: standalone download, project backup, terminal input and argument forwarding')
