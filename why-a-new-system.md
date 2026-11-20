# Why I want a new system

## What I run today

| Machine | What it does |
|---|---|
| MacBook Air | Daily machine |
| MacBook Pro | Work machine |
| wolf (Mac mini) | Server for agents: the claude proxy every machine uses, the one Codex login, CI runners |
| elm | Jellyfin with GPU transcoding, ilovemywife, Home Cloud, Aspen CI runners and machine host, DVD ripping |
| sparrow | Minecraft servers (The Shire, play, skyblock), my websites, the Cloudflare tunnel, DVD ripping |
| oak | Backups for every machine, the Status monitor, Home Cloud's backup keeper, pip's Postgres backups |
| pika (Raspberry Pi) | Pi-hole, a Gitea runner, dynamic DNS |

I'll keep adding machines.

One Nix flake in this repo describes every machine. The Macs run nix-darwin, with Homebrew for most apps. The Linux machines run NixOS. I change a file, then run `nix-rebuild` on each machine. Whatever Nix can't do lives in runbooks, scripts, and steps I do by hand.

## Where it falls short

**Security fixes arrive late.** Stable packages lag behind new vulnerabilities. Getting a fix the day it lands means unstable packages, which means building from source. Building from source is slow, and once it used up all of a machine's memory. The machine restarted into a broken state, and I had to plug it into a screen and boot an older generation.

**Exact sameness costs more than it's worth to me.** Every package is pinned so every machine builds the same thing. Most of the time I'd rather have the newest version and fix what breaks. Meanwhile, old generations pile up on every disk.

**One change means visiting every machine.** A change to anything shared means running a rebuild on each machine, one at a time.

**Moving a service is a project.** Each service is wired into the config of the machine it runs on: its data, its secrets, its address, and everything that points at it. Sparrow's services use a fraction of the machine, and moving them to a new box means installing an OS and reconfiguring everything by hand. Replacing wolf means updating several other machines too.

**Setting up a machine is a long manual checklist.** Installers, logins, keys, secrets, runner tokens, and trust between machines, in a specific order. Scripts help, but they keep growing.

**I can't tell what's on a machine.** Between what's in config, what a script did once, and what I patched by hand, I lose track of what's installed and why. On Fedora it was worse: pages of commands and settings to run by hand, with no way to know whether a machine matched them.

**Linux system files are fragile.** Mounting a disk means editing fstab, and a mistake there can stop the machine from booting until I fix it from recovery mode.

**Services aren't isolated.** If the Minecraft server gets hacked, it shares a machine and a network with everything else.

**Local development doesn't match production.** Several agents work in parallel worktrees on one machine, and they can't each run their own copy of a site without fighting over ports. Docker Desktop runs in the background on my Macs all the time.

**I can't easily test a copy of a service.** I'd like to start a copy of Strive and hammer it to see how it performs, without touching the real one.

**Everything gets the same ceremony.** Some things deserve a written history of every change. Others, like an app that installs its own server over SSH, just need to run. Today both go through the same files and the same rebuild on every machine.

**The repo has grown into a pile.** It's hard to see what matters and what's left over.

## What I need

- Security fixes the same day they're published, without compiling anything.
- An update never takes a machine down, and getting back to the last working state is easy.
- Move a service to another machine quickly, with its data, without reconfiguring either machine, and without changing anything that points at it.
- A compromised service can't reach other services, the machine it runs on, or my home network.
- Each service can use as much of a machine's memory and CPU as it needs, but no service can starve the others or overwhelm the machine.
- A bare machine becomes ready with as few manual steps as possible, so adding machines is routine.
- One place describes every machine and every service, across macOS and Linux. Some services run on Macs.
- Anything that matters is written down in files, with a history of what changed.
- I can always see what's installed and what's running on every machine.
- No system file can keep a machine from booting.

## What I want

- Changing where a service runs is as simple as picking a machine, from one central place.
- The newest versions by default. I'll fix what breaks.
- A change made once reaches every machine without me visiting each one.
- Things that need a history get one, and things that just need to run don't need the ceremony.
- Start a throwaway copy of a service to test it or load test it.
- Each agent's worktree runs its own copy of a site, close to production, side by side on one machine.
- Nothing heavy runs in the background on my Macs unless I'm using it.
- Old versions don't fill up disks.
