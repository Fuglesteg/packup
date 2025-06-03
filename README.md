# Packup

> A simple sbcl script for creating incremental backups.

Packup uses rsync to create an archive of incremental backups.

## Features

- Incremental backups using hardlinks (Very storage efficient)
- Easy to read/write configs
- Syncronize backups with other devices

## Installation

The only dependency is guix, which will create an environment with sbcl and
rsync to run the script. Simply download the script and run it, guix should
take care of the rest.

The script is also available in [my guix
channel](https://github.com/fuglesteg/guix-fuglesteg-channel) as a package.
Using this version means that the script no longer runs in a guix shell
environmnent.

## Configuration

Packup uses a config file to describe the files and folders that should be
backed up. This config file can be supplied as an argument to the script. Or it
will look for a `config.lisp` or `config.sexp` in `$XDG_CONFIG_HOME/packup/`.

The config can either be a static S-expression `config.sexp` or a lisp file
`config.lisp`. The lisp file must evaluate to a config form.

The config form has 5 clauses:

- `device-files`: Files local to this device.
- `synced-files`: Files that are presumed synced using another service, like syncthing, that should still get a local backup, but don't need to be synced to other devices.
- `devices`: Other devices that should have there backups synced to this device.
- `backup-location`: Location of backups, by default `/var/packup/`.
- `version-count`: How many versions to keep, by default `12`.

### Examples

A config using `.sexp`:

```lisp
(:synced-files (#P"/home/andy/Files"
                #P"/home/andy/Archive")
 :device-files (#P"/home/andy/Videos")
 :devices (("hostname" . "USER@<DOMAIN|IP-ADDRESS>")
           "hostname")
 :backup-location "/var/backups/"
 :version-count 6)
```

A config using `.lisp`:

```lisp
(list 
 :synced-files '(#P"/home/andy/Files"
                 #P"/home/andy/Archive")
 :device-files (#P"/home/andy/Videos")
 :devices '(("hostname" . "USER@<DOMAIN|IP-ADDRESS>")
            "hostname")
 :backup-location "/var/backups/"
 :version-count 6)
```

## Remarks

Packup has no presumptions of how often it should run. For example with the
default `version-count` of 12 you can run the script once a week and have 2
months worth of backups.

Packup does not have any facilities for timed services,
leaving this up to the user. On my machine I have a user timer service using
shepherd and guix home, see [my
dotfiles](https://github.com/fuglesteg/dotfiles). This could of course also be
created using SystemD timed services or CRON jobs.
