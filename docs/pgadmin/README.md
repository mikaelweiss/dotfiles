# pgAdmin SSH tunnel with a key and a password

Stock pgAdmin cannot open an SSH tunnel to a server that asks for a password after accepting the key, so the local pgAdmin install is patched. A pgAdmin update overwrites the patch.

## Symptom

"Failed to create the SSH tunnel. Possible causes: 1. Enter the correct tunnel password..." no matter which password you type.

## Causes

1. **pgAdmin never sends the password.** With an identity file, it uses the tunnel password only to unlock the key. The server accepts the key, then asks for a password that never comes.
2. **The server blocks your IP.** OpenSSH's `PerSourcePenalties` blocks an IP for a while after failed logins. When it opens, pgAdmin auto-reconnects your restored tabs at once, with no password. Each attempt is a failed login. Seconds later, your real password is refused before it is ever checked. The debug log shows `Banner: Not allowed at this time`.
3. **No tunnel password prompt.** pgAdmin only asks for the tunnel password when "Prompt for Password?" is on, and that flag gets reset.

The connect dialog can also ask for the `readonly` database password. That is a different password from the server's SSH password.

## Fix

`ssh-tunnel.patch` changes three files:

- `sshtunnel.py`: after the key is accepted, send the password once, then stop.
- `server_manager.py`: send the password to the server, not only to the key. Never open an identity-file tunnel without a password.
- `servers/__init__.py`: prompt for the tunnel password whenever none is saved.

Quit pgAdmin, then apply:

```bash
patch -p1 -d "/Applications/pgAdmin 4.app/Contents" < ~/code/dotfiles/docs/pgadmin/ssh-tunnel.patch
```

If a hunk fails, pgAdmin changed those files. Reapply the three changes above by hand.

Then open pgAdmin, connect to the server, enter both passwords, and check both Save boxes.

## If it still fails

- Check whether the server is blocking you: `nc -w 3 <host> 22 </dev/null`. An `SSH-2.0-OpenSSH...` reply means you are not blocked. No reply means wait a few minutes.
- Errors are in `~/.pgadmin/pgadmin4.log`. For step-by-step auth logs, create `/Applications/pgAdmin 4.app/Contents/Resources/web/config_local.py` with the snippet below and restart pgAdmin. Delete it when done.

```python
import logging as _logging

_handler = _logging.FileHandler('/tmp/pgadmin-tunnel-debug.log')
_handler.setFormatter(
    _logging.Formatter('%(asctime)s %(name)s %(levelname)s %(message)s'))
for _name in ('sshtunnel.SSHTunnelForwarder', 'paramiko.transport'):
    _logger = _logging.getLogger(_name)
    _logger.setLevel(_logging.DEBUG)
    _logger.addHandler(_handler)
```
