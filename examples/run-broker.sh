#!/bin/bash
CURR_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
ROOT_DIR=$(realpath "$CURR_DIR/../../../..")

$CURR_DIR/run-example $CURR_DIR/broker-test.ls --instance=$1