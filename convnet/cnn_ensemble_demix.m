function  [W1H1,W2H2] = cnn_ensemble_demix(Xn,net)


res = [];
N = size(Xn,1);

Xn = permute(Xn, [3 2 1 4]);

Xn = gpuArray(Xn);

res = vl_multiresnn(net, single(Xn), [], res, ...
    'disableDropout', true, ...
    'conserveMemory', 1, ...
    'sync', 1, 'test', true) ;

Yn = permute(res{end}(end).x, [3 2 1]);


W1H1 = gather( Yn(1:2:end,:) );
W2H2 = gather( Yn(2:2:end,:) );
