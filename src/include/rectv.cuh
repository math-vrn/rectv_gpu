#include <cuda_runtime.h>
#include "radonusfft.cuh"

class rectv
{
	//parameters
	size_t N;
	size_t Ntheta;
	size_t M;
	size_t Nz;
	size_t Nzp;
	size_t Nrot;
	float tau;
	float lambda0;
	float lambda1;

	//number of gpus
	size_t ngpus;

	//class for applying Radon transform
	radonusfft **rad;
	radonusfft **rad2;

	//vars
	float *f;
	float *fn;
	float *ft;
	float *ftn;
	float *g;
	float *h1;
	float4 *h2;
	float **theta;
	float2 **phi;

	//temporary arrays on gpus
	float **ftmp;
	float **gtmp;
	float **ftmps;
	float **gtmps;

	void radonapr(float *g, float *f, int igpu, cudaStream_t s);
	void radonapradj(float *f, float *g, int igpu, cudaStream_t s);
	void gradient(float4 *g, float *f, int iz, int igpu, cudaStream_t s);
	void divergent(float *fn, float *f, float4 *g, int igpu, cudaStream_t s);
	void prox(float *h1, float4 *h2, float *g, int igpu, cudaStream_t s);
	void updateft(float *ftn, float *fn, float *f, int igpu, cudaStream_t s);
	void radonfbp(float *f, float *g, int igpu, cudaStream_t s);

public:
	rectv(size_t N, size_t Ntheta, size_t M, size_t Nrot, size_t Nz, size_t Nzp,
		  size_t ngpus, float center, float lambda0, float lambda1);
	~rectv();
	// Reconstruction by the Chambolle-Pock algorithm with proximal operators	
	void chambolle(float *fres, float *g, size_t niter);	
	
	// wrappers for python interface
	void chambolle_wrap(float *fres, int N0, float *g_, int N1, size_t niter);	
	
};
