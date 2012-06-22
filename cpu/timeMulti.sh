#! /bin/bash                                                                                                                                                                       
matrixSize=64
for i in {1..5}
do
    ./timeMulti 1 $matrixSize
    matrixSize=$(expr $matrixSize + $matrixSize)
done
