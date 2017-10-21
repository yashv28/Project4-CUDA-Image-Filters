#include <stdio.h>
#include <cuda.h>
#include "bilateralFilter.h"
#include "cuda_runtime.h"

#define TIMER 1
namespace bilateralFilter {
	float gaussian[64];
	__constant__ float c_gaussian[64];

	void computeGaussianKernel(float delta, int radius) {
		for (int i = 0; i < 2 * radius + 1; i++) {
			float x = i - radius;
			gaussian[i] = expf(-(x * x) / (2.0f * delta * delta));
		}
	}

	float euclideanLen(float3 a, float3 b, float d) {
		float mod = (b.x - a.x) * (b.x - a.x) +
			(b.y - a.y) * (b.y - a.y) +
			(b.z - a.z) * (b.z - a.z);
		return expf(-mod / (2.0f * d * d));
	}

	void bilateralFilter(float3 *input, float3 *output, float l2norm, size_t cols, size_t rows, int radius) {
		for (int y = 0; y < rows; ++y) {
			for (int x = 0; x < cols; ++x) {
				float sum = 0.0f;
				float3 t = { 0.f, 0.f, 0.f };
				float3 center = input[y * cols + x];
				int r = radius;

				float domainDist = 0.0f, colorDist = 0.0f, factor = 0.0f;

				for (int i = -r; i <= r; i++) {
					int crtY = y + i;
					if (crtY < 0)				crtY = 0;
					else if (crtY >= rows)   	crtY = rows - 1;

					for (int j = -r; j <= r; j++) {
						int crtX = x + j;
						if (crtX < 0) 				crtX = 0;
						else if (crtX >= cols)	 	crtX = cols - 1;

						float3 curPix = input[crtY * cols + crtX];
						domainDist = gaussian[r + i] * gaussian[r + j];
						colorDist = euclideanLen(curPix, center, l2norm);
						factor = domainDist * colorDist;
						sum += factor;
						t = add(t, multiply(factor, curPix));
					}
				}

				output[y * cols + x] = multiply(1.f / sum, t);
			}
		}
	}

	Mat cpufilter(Mat im, float l2norm, int radius)
	{
		im.convertTo(im, CV_32FC3);
		im /= 255;
		size_t rows = im.rows;
		size_t cols = im.cols;
		Mat output(im.size(), im.type());
		float3 * src = (float3*)im.ptr<float3>();
		float3 * dest = (float3*)output.ptr<float3>();
		computeGaussianKernel(l2norm, radius);
#if TIMER
		CpuTimer timer;
		timer.Start();
#endif
		bilateralFilter(src, dest, l2norm, cols, rows, radius);
#if TIMER
		timer.Stop();
		printf("filter: %f s.\n", timer.Elapsed());
#endif
		output *= 255;
		output.convertTo(output, CV_8UC3);
		return output;
	}

	void computeGaussianKernelCuda(float delta, int radius) {
		float h_gaussian[64];
		for (int i = 0; i < 2 * radius + 1; ++i)
		{
			float x = i - radius;
			h_gaussian[i] = expf(-(x * x) / (2.0f * delta * delta));
		}
		cudaMemcpyToSymbol(c_gaussian, h_gaussian, sizeof(float)*(2 * radius + 1));
	}

	__device__ inline float euclideanLenCuda(float3 a, float3 b, float d) {
		float mod = (b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y) + (b.z - a.z) * (b.z - a.z);
		return expf(-mod / (2.0f * d * d));
	}

	__device__ inline float3 multiplyCuda(float a, float3 b) {
		return{ a * b.x, a * b.y, a * b.z };
	}

	__device__ inline float3 addCuda(float3 a, float3 b) {
		return{ a.x + b.x, a.y + b.y, a.z + b.z };
	}

	__global__ void bilateralFilterCudaKernel(float3 * dev_input, float3 * dev_output, float l2norm,
		int width, int height, int radius)
	{
		int x = blockIdx.x * blockDim.x + threadIdx.x;
		int y = blockIdx.y * blockDim.y + threadIdx.y;

		if ((x<width) && (y<height))
		{
			float sum = 0.0f;
			float3 t = { 0.f, 0.f, 0.f };
			float3 center = dev_input[y * width + x];
			int r = radius;

			float domainDist = 0.0f, colorDist = 0.0f, factor = 0.0f;

			for (int i = -r; i <= r; i++) {
				int crtY = y + i;
				if (crtY < 0)				crtY = 0;
				else if (crtY >= height)   	crtY = height - 1;

				for (int j = -r; j <= r; ++j) {
					int crtX = x + j;
					if (crtX < 0) 				crtX = 0;
					else if (crtX >= width)	 	crtX = width - 1;

					float3 curPix = dev_input[crtY * width + crtX];
					domainDist = c_gaussian[r + i] * c_gaussian[r + j];
					colorDist = euclideanLenCuda(curPix, center, l2norm);
					factor = domainDist * colorDist;
					sum += factor;
					t = addCuda(t, multiplyCuda(factor, curPix));
				}
			}

			dev_output[y * width + x] = multiplyCuda(1.f / sum, t);
		}
	}

	Mat gpufilter(Mat im, float l2norm, int radius)
	{
		im.convertTo(im, CV_32FC3);
		im /= 255;
		size_t cols = im.cols;
		size_t rows = im.rows;
		Mat result(im.size(), im.type());
		float3 * input = (float3*)im.ptr<float3>();
		float3 * output = (float3*)result.ptr<float3>();
		computeGaussianKernelCuda(l2norm, radius);

		int size = cols * rows * sizeof(float3);
		float3 *dev_input, *dev_output;
		cudaMalloc(&dev_input, sizeof(float3)*size);
		cudaMalloc(&dev_output, sizeof(float3)*size);
		cudaMemcpy(dev_input, input, size, cudaMemcpyHostToDevice);

		dim3 block(16, 16);
		dim3 grid((cols + block.x - 1) / block.x, (rows + block.y - 1) / block.y);
#if TIMER
		GpuTimer timer;
		timer.Start();
#endif
		bilateralFilterCudaKernel << <grid, block >> >(dev_input, dev_output, l2norm, cols, rows, radius);
#if TIMER
		timer.Stop();
		printf("filter kernel: %f msecs.\n", timer.Elapsed());
#endif

		cudaDeviceSynchronize();

		cudaMemcpy(output, dev_output, size, cudaMemcpyDeviceToHost);

		cudaFree(dev_input);
		cudaFree(dev_output);
		result *= 255;
		result.convertTo(result, CV_8UC3);
		return result;
	}
}