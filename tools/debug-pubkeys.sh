#!/bin/bash

die() { echo "$@" >&2; exit 1; }

[[ -z $1 ]] && die please read documentation first

if [[ $1 == client ]]
then
    if [[ -n $2 ]]
    then
        pub="$2"
        [[ -f $2 ]] || die "$2" doesnt exist
    else
        pub=~/.ssh/id_rsa.pub
        [[ -f $pub ]] || pub=~/.ssh/id_dsa.pub
        [[ -f $pub ]] || die cant find RSA or DSA pub keys
    fi

    ssh-keygen -l -f $pub | cut -f2 -d' '
    exit 0
fi

if [[ $1 == server ]]
then
    fp=~/fp
    [[ -n $2 ]] && fp="$2"
    echo "...searching for key fingerprint $(cat $fp)"
    echo

    cd keydir || die could not chdir to keydir/

    echo ...looking in keydir
    for i in *.pub
    do
        cat $i | while read r
        do
            echo -n "found pubkey file $i: "
            echo "$r" > /tmp/junk.pubkey
            ssh-keygen -l -f /tmp/junk.pubkey | cut -f2 -d' '
        done
    done | tee ~/1 | grep -f $fp
    echo

    echo ...looking in ~/.ssh/authorized_keys

    # TODO needs fix up for non-gitolite keys to be better presented as line
    # numbers
    line=0
    extra=
    cat ~/.ssh/authorized_keys | while read l
    do
        (( line++ ))
        read a b c d <<<$l
        if [[ "$a" == "ssh-dss" ]] || [[ "$a" == "ssh-rsa" ]]
        then
            keyid="line $line (wont invoke gitolite!)"
        else
            export b
            keyid="user $(echo $b|sed -e 's/".*//')"
        fi
        echo -n "found authkeys $keyid: "
        echo "$l" > /tmp/junk.pubkey
        ssh-keygen -l -f /tmp/junk.pubkey | cut -f2 -d' '
    done | tee ~/2 | grep -f $fp
    echo
fi

