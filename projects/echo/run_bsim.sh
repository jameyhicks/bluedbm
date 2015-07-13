#!/bin/bash

rm -rf bsimall
mkdir bsimall

cd bsimall

export SIM_LINK_DIR=$PWD

nodes="1 2"

for n in $nodes; do
    cp -r ../bluesim bluesim$n
done

ID=0
for n in $nodes; do
    cd bluesim$n
    ./bin/bsim | tee ../bsim$n.txt & bsimpids="$bsimpids $!"
    BDBM_ID=$ID ./bin/bsim_exe | tee ../bsim_exe1.txt & bsimexepids="$bsimexepids $!"
    ID=`expr $ID + 1`
    cd ..
done

wait $bsimexepids
kill $bsimpids
wait
