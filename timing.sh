#!/bin/sh
set -eu
dub build --force && cp jx jx-normal
dub build -b=release --force && cp jx jx-release
dub build -b=release-nobounds --force && cp jx jx-release-nb
exec hyperfine -w1 './jx-release-nb *.json' './jx-release *.json' './jx-normal *.json'
