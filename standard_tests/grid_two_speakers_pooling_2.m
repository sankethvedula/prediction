%close all;
%clear all;

%% load data
spectrum = 1;
if spectrum
representation = '/misc/vlgscratch3/LecunGroup/bruna/grid_data/spect_fs16_NFFT1024_hop512/';
else
representation = '/misc/vlgscratch3/LecunGroup/bruna/grid_data/scatt_fs16_NFFT2048_hop1024/';
end

id_1 = 2;
%d_2 = 11;

% another man!
id_2 = 6;


load(sprintf('%ss%d',representation,id_1));
data1 = data;
clear data


load(sprintf('%ss%d',representation,id_2));
data2 = data;
clear data


Npad = 2^15;

param.renorm=0;
if param.renorm
%renormalize data: whiten each frequency component.
eps=2e-3;
Xtmp=[abs(data1.X) abs(data2.X)];
stds = std(Xtmp,0,2) + eps;

data1.X = renorm_spect_data(data1.X, stds);
data2.X = renorm_spect_data(data2.X, stds);
end



%% train models
model = 'NMF-pooling';


if spectrum
    param.epsilon = 0.5;
    epsilon = param.epsilon;
    data1.X = softNormalize(abs(data1.X),epsilon);
    data2.X = softNormalize(abs(data2.X),epsilon);
end


KK = [50 100 160];
KKgn = [32 32 64];
LL = [0.05];

for ii = 2:length(KK)
%for jj = 1:length(LL)
jj = ii;
%%%%Plain NMF%%%%%%%
param0.K = KK(ii);
param0.posAlpha = 1;
param0.posD = 1;
param0.pos = 1;
param0.lambda = LL(1);
param0.iter = 4000;
param0.numThreads=16;
param0.batchsize=512;

Dnmf1 = mexTrainDL(abs(data1.X),param0);
Dnmf2 = mexTrainDL(abs(data2.X),param0);

alpha1= mexLasso(abs(data1.X),Dnmf1,param0);
alpha2= mexLasso(abs(data2.X),Dnmf2,param0);

Dnmf1s = sortDZ(Dnmf1,full(alpha1)');
Dnmf2s = sortDZ(Dnmf2,full(alpha2)');

try
gpud=gpuDevice(3);
catch
gpud=gpuDevice(1);
end


param.nmf=1;
param.lambda=LL(1)/4;
param.beta=1e-2;
param.overlapping=1;
param.groupsize=2;
param.time_groupsize=2;
param.nu=0.5;
param.lambdagn=1e-2;
param.betagn=0;
param.itersout=200;
param.K=KK(ii);
param.Kgn=KKgn(ii);
param.epochs=3;
param.batchsize=4096;
param.plotstuff=1;

reset(gpud);

param.initD = Dnmf1s;
[D1, Dgn1] = twolevelDL_gpu(abs(data1.X), param);

reset(gpud);

param.initD = Dnmf2s;
[D2, Dgn2] = twolevelDL_gpu(abs(data2.X), param);

reset(gpud);

    model_name = sprintf('%s-K%d-lambda%d-beta%d',model,param.K,round(10*param.lambda),round(10*param.beta));
%    save_folder = sprintf('/misc/vlgscratch3/LecunGroup/bruna/speech/%s-s%d-s%d-%s/',model_name,id_1,id_2,date());
save_folder = '';

    try
        unix(sprintf('mkdir %s',save_folder));
        unix(sprintf('chmod 777 %s ',save_folder));
    catch
    end

    NFFT = data1.NFFT;
    fs = data1.fs;
    hop = data1.hop;
    N_test = 200;
    SDR = 0;
    SIR = 0;
    
    for i = 1:N_test

        [x1, Fs] = audioread(sprintf('%s%s',data1.folder,data1.d(data1.testing_idx(i) ).name) );
        x1 = resample(x1,fs,Fs);
        x1 = x1(:)'; T1 = length(x1);


        [x2, Fs] = audioread(sprintf('%s%s',data2.folder,data2.d(data2.testing_idx(i) ).name) );
        x2 = resample(x2,fs,Fs);
        x2 = x2(:)'; T2 = length(x2);

        T = min(T1,T2);

        x1 = x1(1:T);
        x2 = x2(1:T);

        mix = (x1+x2);

        if spectrum
            X = compute_spectrum(mix,NFFT,hop);
        else
            [X, phmix] = batchscatt(pad_mirror(mix',Npad),data1.filts, data1.scparam);
        end
    
	if param.renorm
	Xr = renorm_spect_data(X, stds);
	end
        % compute decomposition
	%oldnu = param.nu;
	param.nu=0.2;
	param.alpha_step=1;
	param.gradient_descent=0;
	param.itersout=400;
    
    if spectrum
        
        Xr = softNormalize(abs(X), param.epsilon);

        
    end
    [Z1dm, Z1gn1dm, Z2dm, Zgn2dm] = twolevellasso_gpu_demix(abs(Xr), D1, Dgn1, D2, Dgn2, param);
    
	W1H1 = D1*Z1dm;
	W2H2 = D2*Z2dm;
  

	eps = 1e-6;
    V_ap = W1H1.^2 +W2H2.^2 + eps;
    SPEECH1 = ((W1H1.^2)./(V_ap)).*X(:,1:size(V_ap,2));
    SPEECH2 = ((W2H2.^2)./(V_ap)).*X(:,1:size(V_ap,2));
    
    if spectrum
        speech1 = invert_spectrum(SPEECH1,NFFT,hop,T);
        speech2 = invert_spectrum(SPEECH2,NFFT,hop,T);
        Parms =  BSS_EVAL(x1', x2', speech1', speech2', mix');
    else
        [speech1] = audioreconstruct(SPEECH1, data1, phmix);
        [speech2] = audioreconstruct(SPEECH2, data2, phmix);
        Parms =  BSS_EVAL(x1', x2', speech1(1:T), speech2(1:T), mix');
    end

        SDR = SDR+mean(Parms.NSDR)/N_test;
        SIR = SIR+mean(Parms.SIR)/N_test;
        
        Parms
        output{i} = Parms;
        
        % COMPUTE NMF
        H =  full(mexLasso(Xr,[Dnmf1s,Dnmf2s],param));
        Z1dm = H(1:size(D1,2),:);
        Z2dm = H(size(D1,2)+1:end,:);
	W1H1 = Dnmf1s*Z1dm;
	W2H2 = Dnmf2s*Z2dm;
        
        	eps = 1e-6;
    V_ap = W1H1.^2 +W2H2.^2 + eps;
    SPEECH1 = ((W1H1.^2)./(V_ap)).*X(:,1:size(V_ap,2));
    SPEECH2 = ((W2H2.^2)./(V_ap)).*X(:,1:size(V_ap,2));
    
    if spectrum
        speech1 = invert_spectrum(SPEECH1,NFFT,hop,T);
        speech2 = invert_spectrum(SPEECH2,NFFT,hop,T);
        Parms =  BSS_EVAL(x1', x2', speech1', speech2', mix');
    else
        [speech1] = audioreconstruct(SPEECH1, data1, phmix);
        [speech2] = audioreconstruct(SPEECH2, data2, phmix);
        Parms =  BSS_EVAL(x1', x2', speech1(1:T), speech2(1:T), mix');
    end

        SDR = SDR+mean(Parms.NSDR)/N_test;
        SIR = SIR+mean(Parms.SIR)/N_test;
        
        Parms
        output_nmf{i} = Parms;
        

%         file1 = sprintf('%s%dspeech-1.wav',save_folder,i);
%         audiowrite(file1,speech1,fs);
%         unix(sprintf('chmod 777 %s',file1));
% 
%         file2 = sprintf('%s%dspeech-2.wav',save_folder,i);
%         audiowrite(file2,speech2,fs);
%         unix(sprintf('chmod 777 %s',file2));
% 
%         filemix = sprintf('%s%dmix.wav',save_folder,i);
%         audiowrite(filemix,mix,fs);
%         unix(sprintf('chmod 777 %s',filemix));

    end
    save_file = sprintf('results_%s.mat',num2str(ii));
    save(save_file,'output','output_nmf','Dnmf1s','Dnmf2s','D1','D2','param','param0')
    %unix(sprintf('chmod 777 %s ',save_file));
    AA{ii}.res = output;
    AA{ii}.res_nmf = output_nmf;
    clear output

end
%end

