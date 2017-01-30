#!/usr/bin/dumb-init /bin/bash
set -e

DISABLE_SYSLOG=${DISABLE_SYSLOG:-"no"}
if [ $DISABLE_SYSLOG == "no" ]; then
    #send logs to syslog
    exec 1> >(logger -s -t $(basename $0)) 2>&1
fi

{{with $path := (printf "Settings/NameSpaces/%s/AppRoles/%s/_meta/Backups/Backends" (env "NAMESPACE") (env "APP_NAME"))}}
{{range $key, $pairs := tree $path | byKey}}{{range $pair := $pairs}}
{{ if eq .Key "prefix" }}
printf "{{.Value}}" > /etc/{{$key}}_prefix
{{end}}{{end}}{{end}}{{end}}

{{with $path := (printf "Settings/NameSpaces/%s/AppRoles/%s/_meta/Backups/Passphrase" (env "NAMESPACE") (env "APP_NAME"))}}
printf "{{key $path}}" > /etc/borg_passphrase
{{end}}

