#!/bin/sh
#nc -N localhost 52224
cat "$@" | nc -N localhost 52224
