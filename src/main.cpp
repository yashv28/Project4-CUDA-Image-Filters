#include "opencv2/highgui/highgui.hpp"
#include "opencv2/imgproc.hpp"
#include <iostream>

#include "bilateralFilter.h"
#include "hdr.h"
#include "timer.h"

#define BILATERAL 1
#define HDR 0
#define CPU 0
#define GPU 1
#define TIMER 1

using namespace cv;
using namespace std;

int main(int argc, char** argv)
{

#if BILATERAL
	Mat in = imread("../images/s.jpg");
	Mat imc = in;
#endif
#if HDR
	Mat in = imread("../images/h3.jpg", CV_LOAD_IMAGE_COLOR | CV_LOAD_IMAGE_ANYDEPTH);
	Mat imc = in;
#endif
	if (in.empty()) {
		cout << "Image load error" << endl;
		return -1;
	}
	imshow("Input", in);

#if TIMER
	CpuTimer timerCPU;
	GpuTimer timerGPU;
#endif

#if BILATERAL
		const float l2norm = 1.0f;
		const int radius = 5;
#if CPU
#if TIMER
		timerCPU.Start();
#endif
		in = bilateralFilter::cpufilter(in, l2norm, radius);
#if TIMER
		timerCPU.Stop();
		printf("Total CPU time: %f s.\n", timerCPU.Elapsed());
#endif
#endif
#if GPU
#if TIMER
		timerGPU.Start();
#endif
		in = bilateralFilter::gpufilter(in, l2norm, radius);
#if TIMER
		timerGPU.Stop();
		printf("Total GPU time: %f msecs.\n", timerGPU.Elapsed());
#endif
#endif
#endif


#if HDR
#if CPU
#if TIMER
		timerCPU.Start();
#endif
		in = hdr::cpuhdr(in);
#if TIMER
		timerCPU.Stop();
		printf("Total CPU time: %f s.\n", timerCPU.Elapsed());
#endif
#endif
#if GPU
#if TIMER
		timerGPU.Start();
#endif
		in = hdr::gpuhdr(in);
#if TIMER
		timerGPU.Stop();
		printf("Total GPU time: %f msecs.\n", timerGPU.Elapsed());
#endif
#endif
#endif
	
	imshow("Output", in);
	Mat iq;

#if HDR
	in.convertTo(iq, CV_8UC1, 255.0);
#endif
	
#if BILATERAL
	imwrite("../images/out.jpg", in);
#endif

#if HDR
	imwrite("../images/out.jpg", iq);
#endif
	
	waitKey(0);

	return 0;
}
