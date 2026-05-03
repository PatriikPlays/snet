#!/bin/bash

if ! command -v craftos >/dev/null 2>&1; then
    echo "Error: craftos-pc ('craftos') not found, please install it."
    exit 1
fi

timeout 10s craftos --headless --exec "shell.run('ls');shell.run('/build-headless.lua')" -c="$PWD"

if [ $? -eq 124 ]; then
    echo "Error: craftos execution timed out after 10 seconds."
    exit 1
fi
