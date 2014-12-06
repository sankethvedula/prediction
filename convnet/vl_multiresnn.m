function res = vl_multiresnn(net, x, dzdy, res, varargin)
% VL_SIMPLENN  Evaluates a simple CNN


opts.res = [] ;
opts.conserveMemory = false ;
opts.sync = false ;
opts.disableDropout = false ;
opts.freezeDropout = false ;
opts = vl_argparse(opts, varargin);


m = numel(net) ;


if nargin <= 3 || isempty(res)
    
    res = cell(1,m);
    for i=1:m-1
        
        n = numel(net{i}.layers) ;
        res{i} = struct(...
            'x', cell(1,n+1), ...
            'dzdx', cell(1,n+1), ...
            'dzdw', cell(1,n+1), ...
            'aux', cell(1,n+1), ...
            'time', num2cell(zeros(1,n+1)), ...
            'backwardTime', num2cell(zeros(1,n+1))) ;
        
    end
end




res{1} = vl_simplenn(net{1}, x, [], res{1}, ...
    'conserveMemory', opts.conserveMemory, ...
    'sync', opts.sync);

% compute branches
for i=2:m-1    
    
    res{i} = vl_simplenn(net{i}, res{1}(end).x , [], res{2}, ...
        'conserveMemory', opts.conserveMemory, ...
        'sync', opts.sync);
    
end


% ensemble

if 0
    aux = 0*res{2}(end).x;
    for i=2:m-1
        aux = aux + res{i}(end).x;
    end
    
    res{end}(1).x = aux/(m-2);
else
    
    aux = 1*res{2}(end).x;
    for i=2:m-1
        aux = aux.*res{i}(end).x;
    end
    aux2 = 0*aux;
    aux2(:,:,1:2:end,:) = aux(:,:,1:2:end,:)+aux(:,:,2:2:end,:);
    aux2(:,:,2:2:end,:) = aux2(:,:,1:2:end,:);
    
    res{end}(1).x = aux./aux2;
    
end

