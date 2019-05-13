#!/bin/bash -e

# get the directory of this script
# snippet from https://stackoverflow.com/a/246128/10102404
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" >/dev/null && pwd )"

if [ "$(id -u)" = "0" ]; then
    SUDO=""
else
    SUDO="sudo"
fi

# load the utils
# shellcheck source=/dev/null
source "$SCRIPT_DIR/utils.sh"

# helper function to download the snap, ack the assertion and return the
# name of the file
snap_download_and_ack()
{
    # download the snap and grep the output for the assert file so we can ack 
    # it
    snap_download_output=$(snap download "$1" "$2")
    $SUDO snap ack "$(echo "$snap_download_output" | grep -Po 'edgexfoundry_[0-9]+\.assert')"
    # return the name of this snap
    echo "$(pwd)"/"$(echo "$snap_download_output" | grep -Po 'edgexfoundry_[0-9]+\.snap')"
}

# parse arguments - adapted from https://stackoverflow.com/a/14203146/10102404
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    key="$1"
    case $key in
        -h|--help)
            echo "usage:"
            echo "run-all-tests-locally.sh [OPTIONS]"
            echo "options:"
            printf -- "-s|--snap SNAP\t local snap file to test\n"
            printf -- "-t|--test TEST\t run single test\n"
            printf -- "-v|--verbose\t show output of tests even if passed\n"
            printf -- "-i|--ignorefail\t continue running tests even if some fail\n"
            exit 0
            ;;
        -s|--snap)
            LOCAL_SNAP="$2"
            shift # past argument
            shift # past value
            ;;
        -t|--test)
            SINGLE_TEST="$2"
            shift # past argument
            shift # past value
            ;;
        -v|--verbose)
            VERBOSE=YES
            shift # past argument
            ;;
        -i|--ignorefail)
            IGNORE_FAIL=YES
            shift # past argument
            ;;
        *)    # unknown option
            POSITIONAL+=("$1") # save it in an array for later
            shift # past argument
            ;;
    esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

# if an argument was provided to the script, it's supposed to be a local snap
# file to test - confirm that the file exists
# otherwise if we didn't get any arguments assume to test the snap from beta
if [[ -n $LOCAL_SNAP ]]; then
    if [ -f "$LOCAL_SNAP" ]; then
        REVISION_TO_TEST=$LOCAL_SNAP
        REVISION_TO_TEST_CHANNEL=""
        # for now always need to test edgexfoundry locally with devmode
        # because we can't auto-connect interfaces that are needed
        REVISION_TO_TEST_CONFINEMENT="--devmode"
    else
        echo "local snap to test: \"$LOCAL_SNAP\" does not exist"
        exit 1
    fi
else 
    REVISION_TO_TEST=$(snap_download_and_ack edgexfoundry --beta)
    REVISION_TO_TEST_CHANNEL=""
    REVISION_TO_TEST_CONFINEMENT=""
fi

# export the revision to test env vars
export REVISION_TO_TEST
export REVISION_TO_TEST_CHANNEL
export REVISION_TO_TEST_CONFINEMENT

# download and ack the stable and delhi channels as we have tests to ensure
# there's a smooth upgrade between those channels and this one that is 
# under consideration
# this also saves in download bandwidth and time
EDGEX_STABLE_SNAP_FILE=$(snap_download_and_ack edgexfoundry --stable)
EDGEX_DELHI_SNAP_FILE=$(snap_download_and_ack edgexfoundry --channel=delhi)

# export the names of the stable and delhi snap files
export EDGEX_STABLE_SNAP_FILE
export EDGEX_DELHI_SNAP_FILE

set +e
if [ -n "$SINGLE_TEST" ]; then
    printf "running single test: %s ..." "$SINGLE_TEST"
    if stdout="$("$SCRIPT_DIR/$SINGLE_TEST" 2>&1)"; then
        printf -- "\tPASSED\n"
        if [ -n "$VERBOSE" ]; then
            echo "$stdout"
        fi
    else
        printf -- "\tFAILED:\n"
        echo "$stdout"
        exit 1
    fi
else
    # run all the tests (except this file obviously)
    for file in "$SCRIPT_DIR"/test-*.sh; do 
        printf "running test: %s..." "$file"
        if stdout="$($file 2>&1)"; then
            printf "\t\tPASSED\n"
            if [ -n "$VERBOSE" ]; then
                echo "$stdout"
            fi
        else
            printf "\t\tFAILED:\n"
            echo "$stdout"
            if [ -z "$IGNORE_FAIL" ]; then
                snap_remove
                exit 1
            fi
        fi
    done
fi

# finally remove the snap if it's still there
snap_remove 2>/dev/null > /dev/null
