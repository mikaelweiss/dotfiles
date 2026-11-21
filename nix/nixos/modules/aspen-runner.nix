# GitHub Actions runners for Aspen Grove's Linux release builds. Only jobs
# that ask for the aspen-linux label run here: without the default labels,
# the Mac runners' `runs-on: self-hosted` jobs never land on this machine.
# Two runners let the x86_64 and aarch64 builds run side by side. The
# aarch64 build bundles its AppImage in an emulated container, since Tauri
# can't cross-compile one.
#
# A runner registers with the token in tokenFile when its settings change.
# Registration tokens last an hour, so write a fresh one before changing them:
#   gh api -X POST repos/mikaelweiss/aspen-grove/actions/runners/registration-token --jq .token | tr -d '\n' \
#     | ssh elm 'sudo install -m 600 -o aspen-runner -g aspen-runner /dev/stdin /var/lib/aspen-runner/token'
{ config, lib, pkgs, ... }:

let
  user = "aspen-runner";
  home = "/var/lib/aspen-runner";
  runner = name: {
    enable = true;
    inherit name user;
    url = "https://github.com/mikaelweiss/aspen-grove";
    tokenFile = "${home}/token";
    tokenType = "registration";
    noDefaultLabels = true;
    extraLabels = [ "aspen-linux" ];
    replace = true;
    workDir = "${home}/${name}";
    extraPackages = with pkgs; [ docker awscli2 jq openssl ];
    # Docker's socket belongs to the docker group, which PrivateUsers hides.
    serviceOverrides = {
      PrivateUsers = false;
      Restart = lib.mkForce "on-failure";
      RestartSec = "10s";
    };
  };
in
{
  virtualisation.docker.enable = true;
  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
  # Containers need an emulator they can run without the host's libraries.
  boot.binfmt.preferStaticEmulators = true;

  users.users.${user} = {
    isSystemUser = true;
    group = user;
    extraGroups = [ "docker" ];
    inherit home;
    createHome = true;
  };
  users.groups.${user} = { };

  systemd.tmpfiles.rules = [
    "d ${home}/elm-1 0750 ${user} ${user} -"
    "d ${home}/elm-2 0750 ${user} ${user} -"
  ];

  services.github-runners = {
    aspen-linux-1 = runner "elm-1";
    aspen-linux-2 = runner "elm-2";
  };

  systemd.services.aspen-docker-cleanup = {
    description = "Clean up Aspen CI Docker artifacts and old aspen-ch-base images";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    path = with pkgs; [ config.virtualisation.docker.package coreutils findutils gnugrep gnused psmisc ];
    serviceConfig.Type = "oneshot";
    script = ''
      set -euo pipefail

      cutoff=$(( $(date +%s) - 6 * 3600 ))
      while read -r id name; do
        [ -z "$id" ] && continue
        case "$name" in
          aspen-ch-cache-probes-*|ch-backend-registry-*)
            created=$(docker inspect --format '{{.Created}}' "$id" 2>/dev/null) || continue
            created_ts=$(date -d "$created" +%s 2>/dev/null) || continue
            if [ "$created_ts" -lt "$cutoff" ]; then
              docker rm -f "$id" || true
            fi
            ;;
        esac
      done < <(docker ps -a --format '{{.ID}} {{.Names}}')

      # Separate from autoPrune because Docker rejects --volumes with --filter=until.
      docker volume prune -f

      base_dir=/var/lib/docker/volumes/aspen-ch-base/_data
      if [ -d "$base_dir" ]; then
        refs=$(mktemp)
        trap 'rm -f "$refs"' EXIT
        for qcow in /var/lib/docker/volumes/*-vm/_data/root.qcow2; do
          [ -f "$qcow" ] || continue
          grep -aoE '/base/[^[:cntrl:]]+\.ext4' "$qcow" | sed 's|^/base/||' >> "$refs" || true
        done
        find "$base_dir" -maxdepth 1 -type f -name '*.ext4' -mmin +1440 | while read -r img; do
          name=$(basename "$img")
          if grep -Fqx "$name" "$refs"; then
            continue
          fi
          if fuser -s "$img" 2>/dev/null; then
            continue
          fi
          rm -f "$img"
        done
      fi
    '';
  };

  systemd.timers.aspen-docker-cleanup = {
    description = "Daily Aspen Docker and base-image cleanup";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "daily";
      Persistent = true;
    };
  };
}
