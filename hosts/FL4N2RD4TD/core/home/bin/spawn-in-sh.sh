#!/bin/sh

(cd $1; echo "Open $1 with sub-shell($SHELL). If want to quit, just type `exit`"; $SHELL)
