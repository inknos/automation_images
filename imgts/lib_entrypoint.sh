#!/usr/bin/env bash

set -e

RED="\e[1;31m"
YEL="\e[1;33m"
NOR="\e[0m"
SENTINEL="__unknown__"  # default set in dockerfile
# Disable all input prompts
# https://cloud.google.com/sdk/docs/scripting-gcloud
GCLOUD="gcloud --quiet"
# https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-options.html#cli-configure-options-list
AWS="aws --cli-connect-timeout 30 --cli-read-timeout 30 --no-cli-auto-prompt --no-cli-pager --no-paginate"

die() {
    EXIT=$1
    shift
    MSG="$*"
    echo -e "${RED}ERROR: $MSG${NOR}"
    exit "$EXIT"
}

# Similar to die() but it ignores the first parameter (exit code)
# to allow direct use in place of an (otherwise) die() call.
warn() {
    IGNORE=$1
    shift
    MSG="$*"
    echo -e "${RED}WARNING: $MSG${NOR}"
}

# Hilight messages not coming from a shell command
msg() {
    echo -e "${YEL}${1:-NoMessageGiven}${NOR}"
}

# Pass in a list of one or more envariable names; exit non-zero with
# helpful error message if any value is empty
req_env_var() {
    for i; do
        if [[ -z "${!i}" ]]
        then
            die 1 "entrypoint.sh requires \$$i to be non-empty."
        elif [[ "${!i}" == "$SENTINEL" ]]
        then
            die 2 "entrypoint.sh requires \$$i to be explicitly set."
        fi
    done
}

gcloud_init() {
    req_env_var GCPJSON GCPPROJECT
    set +xe
    if [[ -n "$1" ]] && [[ -r "$1" ]]
    then
        TMPF="$1"
    else
        TMPF=$(mktemp -p '' .$(uuidgen)_XXXX.json)
        trap "rm -f $TMPF &> /dev/null" EXIT
        # Required variable must be set by caller
        # shellcheck disable=SC2154
        echo "$GCPJSON" > $TMPF
    fi
    unset GCPJSON
    # Required variable must be set by caller
    # shellcheck disable=SC2154
    $GCLOUD auth activate-service-account --project="$GCPPROJECT" --key-file="$TMPF" || \
        die 5 "Authentication error, please verify \$GCPJSON contents"
    rm -f $TMPF &> /dev/null || true  # ignore any read-only error
    trap - EXIT
}

aws_init() {
    req_env_var AWSINI
    set +xe
    if [[ -n "$1" ]] && [[ -r "$1" ]]
    then
        TMPF="$1"
    else
        TMPF=$(mktemp -p '' .$(uuidgen)_XXXX.ini)
    fi
    # shellcheck disable=SC2154
    echo "$AWSINI" > $TMPF
    unset AWSINI
    export AWS_SHARED_CREDENTIALS_FILE=$TMPF
}

# Obsolete and Prune search-loops runs in a sub-process,
# therefor count must be recorded in file.
IMGCOUNT=$(mktemp -p '' imgcount.XXXXXX)
echo "0" > "$IMGCOUNT"
count_image() {
    local count
    count=$(<"$IMGCOUNT")
    let 'count+=1'
    echo "$count" > "$IMGCOUNT"
}
