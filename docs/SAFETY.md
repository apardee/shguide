# shguide safety policy

shguide hides commands that can delete data or modify system state by default. The policy is enforced in Swift, not just in the model prompt, because the on-device model cannot be relied on to follow a "do not suggest X" instruction.

## Two-layer check

`Sources/ShguideCore/Environment/DestructivePolicy.swift` defines:

1. **Dangerous binaries** — any pipeline segment whose first token is one of these is treated as destructive:
   `rm`, `dd`, `shred`, `mkfs`/`mkfs.*`, `diskutil`, `fdisk`, `parted`, `newfs`/`newfs_apfs`/`newfs_hfs`, `shutdown`, `reboot`, `halt`, `poweroff`, `kill`, `pkill`, `killall`.

2. **Dangerous substring patterns** — flagged regardless of leading binary:
   `rm -rf /`, `rm -rf ~`, `rm -rf $HOME`, the bash fork bomb, `> /dev/sd*`, `> /etc/*`, `of=/dev/sd*`, `of=/dev/disk*`, `chmod -R 777`, `chown -R`, `xargs rm`, `xargs -I`, `| rm`.

The patterns catch destructive idioms that hide behind a safe-looking leading binary (`ls | xargs rm`, `find … | xargs rm`).

## Behaviour

| Mode | Default | `--include-destructive` |
|---|---|---|
| Forward (`shguide <goal>`) | Drop destructive suggestions silently | Show them, colored red, with a `[destructive]` tag |
| Reverse (`shguide --describe <cmd>`) | Always show the explanation, banner in red if destructive | Same |

`Explanation.containsDestructive` from the model is *OR*-ed with our own check — we trust the model to flag, never to clear.

## What the policy does *not* catch

- Arbitrary shell expansions that resolve to a destructive command at runtime (`$(echo rm) -rf /`). Treat any command before running it.
- Commands that are reversible but cost money or time (e.g. `terraform apply`).
- File-overwriting redirects to user-owned files (`> ~/.zshrc`) — left to the user's judgement so we don't filter legitimate writes.

If you find a false positive or a missed case, add it to `dangerousBinaries` / `dangerousPatterns` with a test in `Tests/ShguideCoreTests/DestructivePolicyTests.swift`.
