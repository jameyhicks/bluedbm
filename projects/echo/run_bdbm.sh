#!/bin/bash

export NODES=2

NODES="bdbm07 bdbm08"

export BDBM_ID=0
for m in $NODES; do
    export BDBM_NODE$BDBM_ID=$m
    BDBM_ID=`expr $BDBM_ID + 1`
done

export BDBM_COORDINATOR=$BDBM_NODE0
env | grep BDBM

export BDBM_ID=0
for m in $NODES; do
    RUNENV='BDBM*' make RUNPARAM=$m run.vc707 & pid="$pid $!"
    BDBM_ID=`expr $BDBM_ID + 1`
done

echo launched $pid

wait 
