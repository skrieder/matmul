#! /bin/bash                                                                                                                                                                       
matrixSize=64
for i in {1..8}
do
    ./timeSetupMulti 1 $matrixSize
    matrixSize=$(expr $matrixSize + $matrixSize)
done
