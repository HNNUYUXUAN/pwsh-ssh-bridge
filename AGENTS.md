# Working on PowerShell SSH Bridge

This checkout is the complete development workspace. Runtime helpers live in
`scripts/`; agent guidance lives in `SKILL.md` and `references/`. Read
`docs/development.md` (or `docs/development.zh-CN.md`) before changing behavior.

- Check the actual shell, PowerShell, Python and OpenSSH available on this machine.
  Use explicit executable arguments at shell boundaries. Run remote shell text via stdin.
- Keep public docs in English and Chinese synchronized. Preserve the distinction
  between verified behavior and adaptation guidance for other harnesses.
- Run `python dev/build.py --check`, `python -m unittest discover -s dev -p 'test_*.py'`,
  then the local PowerShell suite for runtime changes. A build-only change requires
  packaging/install tests. Record versions and results rather than claiming universal support.
- Live tests require a user-approved target and reviewed SSH profile. Read
  `tests/Test-Live.ps1` first. Do not run them automatically from CI or build steps.
- Keep credentials, target addresses, private connection notes and test captures
  outside this checkout. Use temporary fixture keys only in private scratch space.
- Retain strict host verification, bounded process output, explicit file destinations
  and no automatic replay of remote mutations. Test any change to these invariants.
- Build releases from this source with `python dev/build.py`. Update `VERSION` and
  release notes for a new release. Build and install are local operations; publishing
  to a repository or release follows the user's task authorization.
