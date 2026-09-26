#!/bin/sh
set -eu

exec sbcl --script run-tests.lisp
