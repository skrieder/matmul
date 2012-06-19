/*
 * Copyright 1993-2010 NVIDIA Corporation.  All rights reserved.
 *
 * Please refer to the NVIDIA end user license agreement (EULA) associated
 * with this source code for terms and conditions that govern your use of
 * this software. Any use, reproduction, disclosure, or distribution of
 * this software and related documentation outside the terms of the EULA
 * is strictly prohibited.
 *
 */

/* Matrix multiplication: C = A * B.
 * Host code.
 *
 * This sample implements matrix multiplication as described in Chapter 3
 * of the programming guide.
 * It has been written for clarity of exposition to illustrate various CUDA
 * programming principles, not with the goal of providing the most
 * performant generic kernel for matrix multiplication.
 *
 * CUBLAS provides high-performance matrix multiplication.
 * See also:
 * V. Volkov and J. Demmel, "Benchmarking GPUs to tune dense linear algebra,"
 * in Proc. 2008 ACM/IEEE Conf. on Superconducting (SC '08),
 * Piscataway, NJ: IEEE Press, 2008, pp. Art. 31:1-11. 
 *
 */

// Utilities and system includes
#include <stdio.h>
#include <cuda_runtime.h>

#include "matrixMul.h"

////////////////////////////////////////////////////////////////////////////////
//! Matrix multiplication on the device: C = A * B
//! wA is A's width and wB is B's width
////////////////////////////////////////////////////////////////////////////////
template <int BLOCK_SIZE> __global__ void
matrixMul( float* C, float* A, float* B, int wA, int wB)
{
    // Block index
    int bx = blockIdx.x;
    int by = blockIdx.y;

    // Thread index
    int tx = threadIdx.x;
    int ty = threadIdx.y;

    // Index of the first sub-matrix of A processed by the block
    int aBegin = wA * BLOCK_SIZE * by;

    // Index of the last sub-matrix of A processed by the block
    int aEnd   = aBegin + wA - 1;

    // Step size used to iterate through the sub-matrices of A
    int aStep  = BLOCK_SIZE;

    // Index of the first sub-matrix of B processed by the block
    int bBegin = BLOCK_SIZE * bx;

    // Step size used to iterate through the sub-matrices of B
    int bStep  = BLOCK_SIZE * wB;

    // Csub is used to store the element of the block sub-matrix
    // that is computed by the thread
    float Csub = 0;

    // Loop over all the sub-matrices of A and B
    // required to compute the block sub-matrix
    for (int a = aBegin, b = bBegin;
             a <= aEnd;
             a += aStep, b += bStep) {

        // Declaration of the shared memory array As used to
        // store the sub-matrix of A
        __shared__ float As[BLOCK_SIZE][BLOCK_SIZE];

        // Declaration of the shared memory array Bs used to
        // store the sub-matrix of B
        __shared__ float Bs[BLOCK_SIZE][BLOCK_SIZE];

        // Load the matrices from device memory
        // to shared memory; each thread loads
        // one element of each matrix
        As[ty][tx] = A[a + wA * ty + tx];
        Bs[ty][tx] = B[b + wB * ty + tx];

        // Synchronize to make sure the matrices are loaded
        __syncthreads();

        // Multiply the two matrices together;
        // each thread computes one element
        // of the block sub-matrix
#pragma unroll
        for (int k = 0; k < BLOCK_SIZE; ++k)
            Csub += As[ty][k] * Bs[k][tx];

        // Synchronize to make sure that the preceding
        // computation is done before loading two new
        // sub-matrices of A and B in the next iteration
        __syncthreads();
    }

    // Write the block sub-matrix to device memory;
    // each thread writes one element
    int c = wB * BLOCK_SIZE * by + BLOCK_SIZE * bx;
    C[c + wB * ty + tx] = Csub;
}
////////////////////////////////////////////////////////////////////////////////
//    END OF KERNEL
////////////////////////////////////////////////////////////////////////////////


void runTest(int argc, char** argv);
void randomInit(float*, int);
void printDiff(float*, float*, int, int, int, float);
bool check(float*, float*, int, float);

extern "C"
void computeGold(float*, const float*, const float*, unsigned int, unsigned int, unsigned int);


////////////////////////////////////////////////////////////////////////////////
// Program main
////////////////////////////////////////////////////////////////////////////////

int main(int argc, char** argv)
{
    int cuda_device;
    cudaDeviceProp deviceProp;

    cudaGetDevice(&cuda_device);	
    cudaGetDeviceProperties(&deviceProp, cuda_device);

    // use a larger block size for Fermi and above
    int block_size = (deviceProp.major < 2) ? 16 : 32;

    printf("Device %d: \"%s\" with Compute %d.%d capability\n\n", cuda_device, deviceProp.name, deviceProp.major, deviceProp.minor);

	// set seed for rand()
    srand(2006);

    // Optional Command-line multiplier for matrix sizes
    unsigned int uiWA, uiHA, uiWB, uiHB, uiWC, uiHC;
    int iSizeMultiple = 5;

	// For GPUs with fewer # of SM's, we limit the maximum size of the matrix
    if (deviceProp.multiProcessorCount <= 4) {
	uiWA = 2 * block_size * iSizeMultiple;
	uiHA = 4 * block_size * iSizeMultiple;
	uiWB = 2 * block_size * iSizeMultiple;
	uiHB = 4 * block_size * iSizeMultiple;
	uiWC = 2 * block_size * iSizeMultiple;
	uiHC = 4 * block_size * iSizeMultiple;
    } else {
	uiWA = WA * iSizeMultiple;
	uiHA = HA * iSizeMultiple;
	uiWB = WB * iSizeMultiple;
	uiHB = HB * iSizeMultiple;
	uiWC = WC * iSizeMultiple;
	uiHC = HC * iSizeMultiple;
    }

    // allocate host memory for matrices A and B
    unsigned int size_A = uiWA * uiHA;
    unsigned int mem_size_A = sizeof(float) * size_A;
    float* h_A = (float*)malloc(mem_size_A);
    unsigned int size_B = uiWB * uiHB;
    unsigned int mem_size_B = sizeof(float) * size_B;
    float* h_B = (float*)malloc(mem_size_B);

    unsigned int size_C = uiWC * uiHC;
    unsigned int mem_size_C = sizeof(float) * size_C;

    // initialize host memory
    randomInit(h_A, size_A);
    randomInit(h_B, size_B);

    // allocate host memory for the result
    float* h_C      = (float*) malloc(mem_size_C);
    
    // allocate device memory
    float* d_A, *d_B, *d_C;
    

    cudaMalloc((void**) &d_A, mem_size_A);
    cudaMalloc((void**) &d_B, mem_size_B);
    cudaMalloc((void**) &d_C, mem_size_C);

    // copy host memory to device
    cudaMemcpy(d_A, h_A, mem_size_A, cudaMemcpyHostToDevice);
    cudaMemcpy(d_B, h_B, mem_size_B, cudaMemcpyHostToDevice);
    
    // setup execution parameters
    dim3 threads(block_size, block_size);
    dim3 grid(uiWC / threads.x, uiHC / threads.y);

    // execute the kernel
    int nIter = 30;

    //Print information about test
    printf("Calculating: C = A x B, %d times\n", nIter);
    printf("Matrix A is :  %d x %d\n", uiWA, uiHA);
    printf("Matrix B is :  %d x %d\n", uiWB, uiHB);
    printf("Matrix C is :  %d x %d\n\n", uiWC, uiHC);


    //Performs warmup operation using matrixMul CUDA kernel
    if (block_size == 16) {
        matrixMul<16><<< grid, threads >>>(d_C, d_A, d_B, uiWA, uiWB);
    } else {
        matrixMul<32><<< grid, threads >>>(d_C, d_A, d_B, uiWA, uiWB);
    }
    cudaDeviceSynchronize();

    // Add timing stuff later

    for (int j = 0; j < nIter; j++) {
        if (block_size == 16) {
            matrixMul<16><<< grid, threads >>>(d_C, d_A, d_B, uiWA, uiWB);
        } else {
            matrixMul<32><<< grid, threads >>>(d_C, d_A, d_B, uiWA, uiWB);
        }
    }
    // check if kernel execution generated and error

    cudaDeviceSynchronize();
    // calculate timing stuff
    printf("timing is currently disabled, sorry Scott\n\n");
    //double dSeconds = sdkGetTimerValue(&timer_matrixMul)/((double)nIter * 1000.0);
    //double dNumOps = 2.0 * (double)uiWA * (double)uiHA * (double)uiWB;
    //double gflops = 1.0e-9 * dNumOps/dSeconds;

    // copy result from device to host
    cudaMemcpy(h_C, d_C, mem_size_C, cudaMemcpyDeviceToHost);

    // compute reference solution    
    float* reference = (float*)malloc(mem_size_C);
    computeGold(reference, h_A, h_B, uiHA, uiWA, uiWB);

    // check result (matrixMul)
    printf("Comparing CUDA matrixMul & Host results\n");
    bool resCUDA = check(reference, h_C, size_C, 1.0e-6f); //not sure if I can use this
    if (resCUDA != true) 
    {
        printDiff(reference, h_C, uiWC, uiHC, 100, 1.0e-4f);
    }
    printf("CUDA matrixMul compares %s\n\n", (true == resCUDA) ? "OK" : "FAIL");

    // clean up memory
    free(h_A);
    free(h_B);
    free(h_C);
    free(reference);
    cudaFree(d_A);
    cudaFree(d_B);
    cudaFree(d_C);

    cudaDeviceReset();
}


// Allocates a matrix with random float entries.
void randomInit(float* data, int size)
{
    for (int i = 0; i < size; ++i)
        data[i] = rand() / (float)RAND_MAX;
}

void computeGold(float* C, const float* A, const float* B, unsigned int hA, unsigned int wA, unsigned int wB)
{
    for (unsigned int i = 0; i < hA; ++i)
        for (unsigned int j = 0; j < wB; ++j) {
            double sum = 0;
            for (unsigned int k = 0; k < wA; ++k) {
                double a = A[i * wA + k];
                double b = B[k * wB + j];
                sum += a * b;
            }
            C[i * wB + j] = (float)sum;
        }
}

bool check(float *data1, float *data2, int size, float fListTol)
{
    int k;
    for (k = 0; k < size; k++){ 
        float fDiff = fabs(data1[k] - data2[k]);
        if (fDiff > fListTol) return false;
    }
    return true;
}

void printDiff(float *data1, float *data2, int width, int height, int iListLength, float fListTol)
{
    //printf("Listing first %d Differences > %.6f...\n", iListLength, fListTol);
    int i,j,k;
    int error_count=0;
    for (j = 0; j < height; j++) 
    {
        if (error_count < iListLength)
        {
            //printf("\n  Row %d:\n", j);
        }
        for (i = 0; i < width; i++) 
        {
            k = j * width + i;
            float fDiff = fabs(data1[k] - data2[k]);
            if (fDiff > fListTol) 
            {                
                if (error_count < iListLength)
                {
                    //printf("    Loc(%d,%d)\tCPU=%.5f\tGPU=%.5f\tDiff=%.6f\n", i, j, data1[k], data2[k], fDiff);
                }
                error_count++;
            }
        }
    }
    printf(" \n  Total Errors = %d  with tolerance of %.6f\n\n", error_count, fListTol);
}