## Running CI Tests with Woodpecker-CI on FreeBSD

By default the woodpecker intance on Codeberg doesn't support
FreeBSD. Running FreeBSD inside a qemu VM in a linux docker image
didn't work. Also, this particular tool needs to run outside a jail,
since it is a jail management tool.

So, this is my setup:

I deployed a freebsd VM on Hetzner Cloud: `ci-agent.daemon.de`. It
runs the `woodpecker-agent` build for freebsd. The agent runs as rool
directly on the host. This is a security risk and the reason why we
use a VM.

The VM does **NOT** run continuously. So in order to execute
workflows, first unsuspend the VM:

```default
hcloud server poweron ci-agent
```

When it's running, execute workflows (i.e. push).

## Setup

Deploy a new FreeBSD VM using the latest freebsd-snapshot.

Upgrade to latest Release (or the one you want to run tests on).

Clone [woodpecker-ci](https://github.com/woodpecker-ci/woodpecker).

Execute:

```default
make build-agent GOOS=freebsd
```

Clone [plugin-git](https://github.com/woodpecker-ci/plugin-git.git)

Execute:

```default
GOOS=freebsd go build
```

Copy the newly built binaries into the VM to
`/usr/local/bin`.

```default
scp woodpecker-ci/dist/woodpecker-agent agent:/usr/local/bin/
scp plugin-git/plugin-git agent:/usr/local/bin/
```

Add the agent token to `/etc/rc.conf`:

```sh
woodpeckeragent_enable=YES
woodpeckeragent_token=*****
```

Create the [rc-Script](woodpeckeragent.sh) in
`/usr/local/etc/rc.d/woodpeckeragent`.

Install `git-lfs`: `pkg install bash cpdup git git-lfs`.


Start it: `service woodpeckeragent start`
