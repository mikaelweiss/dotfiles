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
{ pkgs, ... }:

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
    serviceOverrides.PrivateUsers = false;
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
}
