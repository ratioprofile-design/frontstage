#!/usr/bin/env python3
"""Validate and copy a stopped server's store; never replace an existing destination."""
import argparse
import json
import os
from pathlib import Path


def transfer(source, destination, restore=False):
    data = source.read_bytes()
    state = json.loads(data)
    if state.get('version') != 1 or not all(isinstance(state.get(key), dict) for key in ('accounts', 'sessions', 'projects')):
        raise ValueError('Unsupported or invalid Frontstage server store')
    if restore:
        # Restoring a backup must not revive previously revoked sessions.
        state['sessions'] = {}
        data = json.dumps(state, ensure_ascii=False, separators=(',', ':')).encode()
    fd = os.open(destination, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
    try:
        with os.fdopen(fd, 'wb') as output:
            output.write(data)
            output.flush()
            os.fsync(output.fileno())
    except BaseException:
        destination.unlink(missing_ok=True)
        raise


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=['backup', 'restore'])
    parser.add_argument('source', type=Path)
    parser.add_argument('destination', type=Path)
    parser.add_argument('--server-stopped', action='store_true', required=True,
                        help='Confirm the service is stopped before copying/restoring its store')
    args = parser.parse_args()
    transfer(args.source, args.destination, args.action == 'restore')
    print('Validated copy created; existing files were not overwritten.')


if __name__ == '__main__':
    main()
