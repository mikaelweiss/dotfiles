// Mounts wolf's runner cache, a disk image on The Vault, at
// /Volumes/RunnerCache for the self-hosted GitHub runners.
//
// macOS grants a LaunchDaemon's file access to the program launchd starts.
// For a script that is the shell, so a grant would reach every script. This
// compiled program holds the Full Disk Access grant alone, and hdiutil, its
// child, reads the image through it. The grant follows this exact build:
// rebuild it and grant it again.
//
// Build on wolf, then `stow actions-runner` from ~/code/dotfiles:
//   cc -O2 -o ~/code/dotfiles/actions-runner/actions-runner-hooks/mount-runner-cache \
//     ~/code/dotfiles/actions-runner/actions-runner-hooks/mount-runner-cache.c
#include <stdio.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/wait.h>
#include <unistd.h>

static const char *vault = "/Volumes/The Vault";
static const char *image = "/Volumes/The Vault/runner-cache.sparsebundle";
static const char *mountpoint = "/Volumes/RunnerCache";

static int mounted(const char *path) {
  struct statfs *mounts;
  int n = getmntinfo(&mounts, MNT_NOWAIT);
  for (int i = 0; i < n; i++) {
    if (strcmp(mounts[i].f_mntonname, path) == 0) return 1;
  }
  return 0;
}

int main(void) {
  if (mounted(mountpoint)) return 0;
  if (!mounted(vault)) {
    fprintf(stderr, "The Vault is not mounted\n");
    return 1;
  }
  pid_t pid = fork();
  if (pid < 0) {
    perror("fork");
    return 1;
  }
  if (pid == 0) {
    execl("/usr/bin/hdiutil", "hdiutil", "attach", "-nobrowse", "-mountpoint", mountpoint, image, (char *)NULL);
    perror("hdiutil");
    _exit(127);
  }
  int status;
  if (waitpid(pid, &status, 0) < 0) {
    perror("waitpid");
    return 1;
  }
  return WIFEXITED(status) ? WEXITSTATUS(status) : 1;
}
