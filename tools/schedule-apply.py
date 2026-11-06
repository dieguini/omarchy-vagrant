#!/usr/bin/env python3
"""schedule-apply: keep systemd user timers' times in one TOML file.

  schedule-apply [schedule.toml] [--check] [--reload]

Default file: ~/.config/omarchy-schedule.toml. For each [timers.<name>] it rewrites only the
Description= and OnCalendar= lines of that .timer file; everything else in it is kept. Each
OnCalendar gets the TOML's IANA timezone appended, so systemd itself follows daylight saving
instead of a UTC time that drifts by an hour twice a year.

  timezone = "America/Los_Angeles"
  [workday]                      # optional: writes schedule.env next to the TOML with
  start = "06:00"                # WORK_TZ / WORK_START / WORK_END, for scripts that guard
  end   = "17:00"                # their own hours
  [timers.backup]
  file        = "systemd/user/backup.timer"   # relative to the TOML's directory
  description = "Nightly backup"
  on          = ["*-*-* 02:30:00"]

  --check   change nothing; exit 1 when a file differs from the TOML
  --reload  run `systemctl --user daemon-reload` after writing (otherwise it is printed)

Files are written with LF. Exit code: 0 done or nothing to do, 1 --check found differences,
2 bad input (missing file, no OnCalendar line, invalid time or timezone).
"""
import argparse
import os
import re
import shutil
import subprocess
import sys
import tomllib
from pathlib import Path

DEFAULT = Path.home() / ".config" / "omarchy-schedule.toml"
HHMM = re.compile(r"^([01]\d|2[0-3]):[0-5]\d$")


class Bad(Exception):
    pass


def render_timer(text, description, on, tz):
    lines = text.replace('\r\n', '\n').split('\n')
    out, placed = [], False
    for line in lines:
        if line.startswith('Description='):
            out.append(f'Description={description}')
        elif line.startswith('OnCalendar='):
            # every OnCalendar line is replaced by the TOML's list, placed where the first was
            if not placed:
                out += [f'OnCalendar={spec} {tz}' for spec in on]
                placed = True
        else:
            out.append(line)
    if not placed:
        raise ValueError('no OnCalendar line to replace')
    return '\n'.join(out)


def check_tz(tz):
    if not isinstance(tz, str) or not re.fullmatch(r"[A-Za-z0-9_+\-]+(/[A-Za-z0-9_+\-]+)*", tz):
        raise Bad(f'timezone must be an IANA name such as "America/Los_Angeles", got {tz!r}')
    zoneinfo = Path('/usr/share/zoneinfo')
    # Only where the tz database is there to ask (not on a host without it, e.g. Windows).
    if zoneinfo.is_dir() and not (zoneinfo / tz).is_file():
        raise Bad(f'unknown timezone {tz!r} (not in {zoneinfo})')


def check_calendar(spec):
    # systemd is the authority on OnCalendar syntax; ask it when it is there.
    if shutil.which('systemd-analyze'):
        r = subprocess.run(['systemd-analyze', 'calendar', spec], capture_output=True, text=True)
        if r.returncode != 0:
            raise Bad(f'invalid OnCalendar {spec!r}: {(r.stderr or r.stdout).strip()}')


def load(path):
    try:
        with open(path, 'rb') as f:
            data = tomllib.load(f)
    except FileNotFoundError:
        raise Bad(f'{path}: not found (start from examples/schedule.toml)')
    except tomllib.TOMLDecodeError as e:
        raise Bad(f'{path}: {e}')
    tz = data.get('timezone')
    check_tz(tz)
    timers = data.get('timers') or {}
    if not isinstance(timers, dict) or not timers:
        raise Bad(f'{path}: no [timers.<name>] tables')
    plan = []
    for name, t in timers.items():
        if not isinstance(t, dict):
            raise Bad(f'timers.{name}: must be a table')
        for key in ('file', 'description', 'on'):
            if key not in t:
                raise Bad(f'timers.{name}: missing "{key}"')
        on = t['on']
        if not isinstance(on, list) or not on or not all(isinstance(s, str) and s.strip() for s in on):
            raise Bad(f'timers.{name}: "on" must be a non-empty list of OnCalendar strings')
        if '\n' in t['description']:
            raise Bad(f'timers.{name}: description must be one line')
        for spec in on:
            check_calendar(f'{spec} {tz}')
        file = Path(os.path.expanduser(t['file']))
        if not file.is_absolute():
            file = path.parent / file
        plan.append((name, file, t['description'], [s.strip() for s in on]))
    workday = data.get('workday')
    if workday is not None:
        if not isinstance(workday, dict) or not all(HHMM.match(str(workday.get(k, ''))) for k in ('start', 'end')):
            raise Bad('[workday] needs start and end as "HH:MM"')
    return tz, plan, workday


def read(file):
    try:
        with open(file, encoding='utf-8', newline='') as f:
            return f.read()
    except FileNotFoundError:
        return None


def main():
    ap = argparse.ArgumentParser(prog='schedule-apply', description=__doc__.split('\n')[0],
                                 epilog='See the header of schedule-apply.py or docs/helper-tools.md.')
    ap.add_argument('toml', nargs='?', default=str(DEFAULT), help=f'schedule file (default {DEFAULT})')
    ap.add_argument('--check', action='store_true', help='change nothing; exit 1 when something differs')
    ap.add_argument('--reload', action='store_true', help='run systemctl --user daemon-reload after writing')
    a = ap.parse_args()
    path = Path(os.path.expanduser(a.toml)).resolve()

    try:
        tz, plan, workday = load(path)
        writes = []
        for name, file, description, on in plan:
            old = read(file)
            if old is None:
                raise Bad(f'timers.{name}: {file} does not exist')
            try:
                new = render_timer(old, description, on, tz)
            except ValueError as e:
                raise Bad(f'timers.{name}: {file}: {e}')
            writes.append((file, old, new))
        if workday is not None:
            env = path.parent / 'schedule.env'
            new = (f'# Generated by schedule-apply from {path.name}: edit that file, not this one.\n'
                   f'WORK_TZ={tz}\nWORK_START={workday["start"]}\nWORK_END={workday["end"]}\n')
            writes.append((env, read(env), new))
    except Bad as e:
        print(f'schedule-apply: {e}', file=sys.stderr)
        return 2

    changed = [(f, new) for f, old, new in writes if old != new]
    for f, old, new in writes:
        state = 'unchanged' if old == new else ('would change' if a.check else 'changed')
        print(f'{state:12} {f}')
    if a.check:
        return 1 if changed else 0
    for f, new in changed:
        tmp = f.with_name(f'.{f.name}.schedule-apply')
        with open(tmp, 'w', encoding='utf-8', newline='\n') as out:
            out.write(new)
        os.replace(tmp, f)
    if not changed:
        print('Nothing to do.')
    elif a.reload:
        subprocess.run(['systemctl', '--user', 'daemon-reload'], check=True)
        print(f'{len(changed)} file(s) changed; systemd user units reloaded.')
    else:
        print(f'{len(changed)} file(s) changed. Apply with: systemctl --user daemon-reload')
    return 0


if __name__ == '__main__':
    sys.exit(main())
