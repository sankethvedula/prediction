clear all;
close all;


if ~exist('X1','var')
    load '/misc/vlgscratch3/LecunGroup/bruna/grid_data/spect_640/class_s31.mat'
    X1 = Xc;
    clear Xc;
    
    epsilon = 1;
    
    load '/misc/vlgscratch3/LecunGroup/bruna/grid_data/spect_640/class_s14.mat'
    X2 = Xc;
    
    X = [X1 X2];
    clear X1 X2
    
end

X0=X;

%renormalize data: whiten each frequency component.
eps=1e-2;
stds = std(X,0,2) + eps;
X = X./repmat(stds,1,size(X,2));
avenorm = mean(sqrt(sum(X.^2)));
X = X/avenorm;


%%init phase: D is initialized with NMF. 
%% S is initialized by looking at temporally smoothed activations
param.K=400; % learns a dictionary 
param.lambda=0.04; 
param.numThreads=16;	%	number	of	threads 
param.batchsize =512;
param.iter=1000; % let us see what happens after 1000 iterations .
param.posD=1;
param.posAlpha=1;
param.pos=1;

D=mexTrainDL(X, param);

z=mexLasso(X, D, param);
%temporal pooling 
Tpool=8;
h=hanning(Tpool)';
zpool=conv2(full(z),h,'same');

%options.num_neighbors = 16;
%[S, L, V, spect] = graphlaplacian(zpool', options);

T = trees(zpool, options);

param.initD = D;
param.initT = T;

[D, T] = binary_graph_dlearn(X, param); 




