# rectv_gpu
# Four-dimensional tomographic reconstruction by time domain decomposition

# Installation
## Building an executable file
Specify paths in Makefile, run

make

## Building python modules
Set CUDAHOME environmental variable, run

python setup.py install

## Execution
* ./rectv <parameters file> <name of the binary data file> <name of the binary reconstruction file> *
  
Example: ./rectv pars64 gbubbles64 rec64

Parameters file contains information for reconstruction by the proposed method in the following format:

N Nrot Ntheta M Nz Nzp ngpus niters

lambda0 lambda1

N - reconstruction size in one dimension

Nrot - number of rotations

Ntheta - total number of projections

M - number of basis funcitons

Nz - number of slices for reconstruction

Nzp - number of slices for simultanious reconstruction on GPU

ngpus - number of GPUs

niters - number of iterations

lambda0 - spatial regularization parameter

lambda1 - temporal regularization parameter

## Use as a module 
See an example in tomobank <ref>

python tomopy_rec.py dk_MCFG_1_p_s1_.h5 --type full --binning 2 --algorithm_type tv --frame 92 

--binning - factor for data downsampling (0,1,2)

--algorithm_type - reconstrution algorithm (tv,gridrec)

--frame - central time frame for reconstruction, 8 time frames will be reconstructed by default. Example --frame 92 gives time frames [88,66)
