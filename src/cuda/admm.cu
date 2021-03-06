
#include "rectv.cuh"


__global__ void lin(float *f, float *g, float *h, float a, float b, float c, int n, int ntheta, int nz)
{
    int tx = blockIdx.x * blockDim.x + threadIdx.x;
    int ty = blockIdx.y * blockDim.y + threadIdx.y;
    int tz = blockIdx.z * blockDim.z + threadIdx.z;
    if (tx >= n || ty >= ntheta || tz >= nz)
        return;

    int id0 = tx + ty * n + tz * n * ntheta;
    f[id0] = a*f[id0] + b*g[id0];
    if (h!=NULL) f[id0]+=c*h[id0];
}

__global__ void lin4(float4 *f, float4 *g, float4 *h, float a, float b, float c, int n, int nz)
{
    int tx = blockIdx.x * blockDim.x + threadIdx.x;
    int ty = blockIdx.y * blockDim.y + threadIdx.y;
    int tz = blockIdx.z * blockDim.z + threadIdx.z;
    if (tx >= n || ty >= n || tz >= nz)
        return;

    int id0 = tx + ty * n + tz * n * n;
    f[id0].x = a*f[id0].x+b*g[id0].x;
    f[id0].y = a*f[id0].y+b*g[id0].y;
    f[id0].z = a*f[id0].z+b*g[id0].z;
    f[id0].w = a*f[id0].w+b*g[id0].w;
    if(h!=NULL)
    {
        f[id0].x += c*h[id0].x;
        f[id0].y += c*h[id0].y;
        f[id0].z += c*h[id0].z;
        f[id0].w += c*h[id0].w;
    }
}

__global__ void solve_reg_ker(float4* psi, float4 *h2, float4* mu, float lambda, float rho, int n, int nz)
{
    int tx = blockIdx.x * blockDim.x + threadIdx.x;
    int ty = blockIdx.y * blockDim.y + threadIdx.y;
    int tz = blockIdx.z * blockDim.z + threadIdx.z;
    if (tx >= n || ty >= n || tz >= nz)
        return;

    int id0 = tx + ty * n + tz * n * n;
    psi[id0].x =(h2[id0].x+mu[id0].x/rho);
    psi[id0].y =(h2[id0].y+mu[id0].y/rho);
    psi[id0].z =(h2[id0].z+mu[id0].z/rho);
    psi[id0].w =(h2[id0].w+mu[id0].w/rho);    
	float za = sqrtf(psi[id0].x * psi[id0].x + 
                     psi[id0].y * psi[id0].y + 
                     psi[id0].z * psi[id0].z + 
                     psi[id0].w * psi[id0].w);
    
	if (za <= lambda / rho)
	{
		psi[id0].x = 0;
		psi[id0].y = 0;
		psi[id0].z = 0;
		psi[id0].w = 0;
	}
	else
	{
      	psi[id0].x -= lambda / rho * psi[id0].x / za;
	 	psi[id0].y -= lambda / rho * psi[id0].y / za;
		psi[id0].z -= lambda / rho * psi[id0].z / za;
		psi[id0].w -= lambda / rho * psi[id0].w / za;
	}
}

float2 rectv::solver_admm(float *f, float *fn, float* h1, float4* h2, float4* h2stored, float* fm, float *g, float4 *psi, float4 *mu, 
    float lambda0, float lambda1, float rho,
    int iz, int titer, int igpu, cudaStream_t s)
{
    //float rho = sqrt(ntheta*lambda1/m)/32;
    gradient(h2stored, fm, lambda1,  iz, igpu, s); //iz for border control      
    
    for (int k=0;k<titer;k++)
    {
        //forward step
        // h2 = \nabla fm
        gradient(h2, fm, lambda1,  iz, igpu, s); //iz for border control
        // h1 = \Rad fm
        radonapr(h1, fm, 1, igpu, s);        
        //differences
        // h2 = rho*(h2-psi)+mu
        lin4<<<GS3d4, BS3d, 0, s>>>(h2, psi, mu, rho, -rho, 1, (n + 1), (m + 1) * (nzp + 1));
        // h1 = h1-g
        lin<<<GS3d2, BS3d, 0, s>>>(h1, g, NULL, 1, -1, 0, n, ntheta, nzp);
        //backward step
        // fm = fm-0.5 \nabla* h2
        divergent(fm, h2, lambda1, -0.5, igpu, s);        
        // fm = fm-0.5 \Rad* h1
        radonapradj(fm, h1, -0.5, igpu, s);   
    }    
    //forward step
    // h2 = \nabla fm
    gradient(h2, fm, lambda1, iz, igpu, s); //iz for border control
    // solve reg by softhresholding
    // psi = (h2+mu/rho)-lamd/rho*(h2+mu/rho)/|h2+mu/rho|*max(|h2+mu/rho|-lamd/rho,0)
    solve_reg_ker<<<GS3d4, BS3d, 0, s>>>(psi, h2, mu, lambda0, rho, n+1, (m+1)*(nzp+1));   
    // update mu
    // mu = mu + rho*(h2 - psi)
    lin4<<<GS3d4, BS3d, 0, s>>>(mu, h2, psi, 1, rho, -rho, n+1, (m+1)*(nzp+1));   
    // h2stored=h2stored-h2
    lin4<<<GS3d4, BS3d, 0, s>>>(h2stored, h2stored, h2, 1, 0, -1, n+1, (m+1)*(nzp+1));       
    // h2=h2-psi
    lin4<<<GS3d4, BS3d, 0, s>>>(h2, h2, psi, 1, 0, -1, n+1, (m+1)*(nzp+1));   
    cudaMemcpyAsync(fn, fm, n * n * nzp * m * sizeof(float), cudaMemcpyDefault, s);
    //compute norms for rho updates
    float2 normdiff;
    cublasSetStream(cublas_handles[igpu],s);
    cublasSnrm2(cublas_handles[igpu], 4*(n + 1) * (n + 1) * (m + 1) * (nzp + 1), (float*)h2, 1, &normdiff.x);
    cublasSnrm2(cublas_handles[igpu], 4*(n + 1) * (n + 1) * (m + 1) * (nzp + 1), (float*)h2stored, 1, &normdiff.y);



    return normdiff;
}