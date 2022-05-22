#!/usr/bin/env bash
$HOME/work/contributions/d/dmd/generated/linux/debug/64/dmd -unittest -betterC -debug -g \
    -version=vtypechoice_unittest \
    -preview=dip1000 -preview=in \
    -I=source \
    -i -run source/app.d
