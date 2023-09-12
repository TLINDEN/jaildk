output=_jaildk-completion.bash
cmd=jaildk
cmd_opts=()

subcmds=(base build create clone fetchports install uninstall remove
         reinstall prune start stop restart status rc ipfw login
         blogin freeze thaw help version update)

reply_jail() {
    local jails=$(ls $JAILDIR/etc)
    COMPREPLY=( $(compgen -W "${jails[*]}" -- "$cur") )
}

reply_base() {
    local bases=$(ls $JAILDIR/base)
    COMPREPLY=( $(compgen -W "${bases[*]}" -- "$cur") )
}

reply_version() {
    local versions=$(ls -d $JAILDIR/etc/*/etc-*|cut -d- -f2 | sort -u)
    COMPREPLY=( $(compgen -W "${versions[*]}" -- "$cur") )
}

rcscripts='mount,ports,mtree,pf'
modes='start,stop,status,restart'

### sub cmd base
subcmd_opts_base=(-b -w)

### sub cmd build
# FIXME: -m
subcmd_opts_build=(-b:@base -v:@version -m:$modes)
subcmd_args_build=@jail

### sub cmd clone
# FIXME: how to fetch version from already selected jail
subcmd_opts_clone=(-s:@jail -d:@jail -o:@version -n:@version)

### sub cmd fetchports
subcmd_opts_fetchports=(-v:@version)

### sub cmd install
# FIXME: -m
subcmd_opts_install=(-m:$modes -r:$rcscripts)
subcmd_args_install=@jail

### sub cmd uninstall
subcmd_opts_uninstall=(-w)
subcmd_args_uninstall=@jail

### sub cmd remove
subcmd_args_remove=@jail

### sub cmd reinstall
subcmd_opts_reinstall=(-b:@base -v:@version)
subcmd_args_reinstall=@jail

### sub cmd prune
subcmd_opts_prune=(-b -a -j:@jail)

### sub cmd start
subcmd_args_start=@jail

### sub cmd stop
subcmd_args_stop=@jail

### sub cmd restart
subcmd_args_restart=@jail

### sub cmd status
subcmd_opts_status=(-v)
subcmd_args_status=@jail

### sub cmd rc
subcmd_opts_rc=(-m:$modes -r:$rcscripts)

### sub cmd ipfw
subcmd_opts_ipfw=(-m:$modes)
subcmd_args_ipfw=@jail

### sub cmd login
subcmd_args_login=@jail

### sub cmd blogin
subcmd_args_blogin=@jail

### sub cmd freeze
subcmd_opts_freeze=(-a -b -v:@version)
subcmd_args_freeze=@jail

### sub cmd thaw
subcmd_args_thaw=@files

### sub cmd help
subcmd_args_help="${subcmds[*]}"

### sub cmd update
subcmd_opts_update=(-f)

