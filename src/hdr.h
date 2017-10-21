#include <stdio.h>
#include <cuda.h>
#include <vector>
#include "cuda_runtime.h"
#include <iostream>
#include <algorithm>
#include "opencv2/highgui/highgui.hpp"
#include "timer.h"

using namespace std;
using namespace cv;

namespace hdr {
	Mat cpuhdr(Mat im);
	Mat gpuhdr(Mat im);
	float reduce_minmax(float* d_in, size_t size, int minmax);
}