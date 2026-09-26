#!/bin/sh
set -eu

exec timeout 600 sbcl --script run-tests.lisp
