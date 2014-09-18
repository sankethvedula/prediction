

%% load data

representation = '/misc/vlgscratch3/LecunGroup/bruna/grid_data/spect_fs16_NFFT1024_hop512/';

id_1 = 2;
id_2 = 11;

% another man!
%id_2 = 14;


load(sprintf('%ss%d',representation,id_1));
data1 = data;
clear data


load(sprintf('%ss%d',representation,id_2));
data2 = data;
clear data


param.renorm=1;

if param.renorm
%renormalize data: whiten each frequency component.
eps=4e-1;
Xtmp=[abs(data1.X) abs(data2.X)];
stds = std(Xtmp,0,2) + eps;

data1.X = renorm_spect_data(data1.X, stds);
data2.X = renorm_spect_data(data2.X, stds);
end


%% train models

model = 'NMF-pooling';

KK = [200];
KKgn = [80];
LL = [0.1];


for ii = 1:length(KK)
for jj = 1:length(LL)

%%%%Plain NMF%%%%%%%
param0.K = KK(ii);
param0.posAlpha = 1;
param0.posD = 1;
param0.pos = 1;
param0.lambda = LL(jj);
param0.iter = 1000;
param0.numThreads=16;
param0.batchsize=512;

Dnmf1 = mexTrainDL(abs(data1.X),param0);
Dnmf2 = mexTrainDL(abs(data2.X),param0);

alpha1= mexLasso(abs(data1.X),Dnmf1,param0);
alpha2= mexLasso(abs(data2.X),Dnmf2,param0);

Dnmf1s = sortDZ(Dnmf1,full(alpha1)');
Dnmf2s = sortDZ(Dnmf2,full(alpha2)');

gpud=gpuDevice(4);

param.nmf=1;
param.lambda=LL(jj)/4;
param.beta=1e-2;
param.overlapping=1;
param.groupsize=2;
param.time_groupsize=2;
param.nu=0.5;
param.lambdagn=0;
param.betagn=0;
param.itersout=200;
param.K=KK(ii);
param.Kgn=KKgn(ii);
param.epochs=4;
param.batchsize=4096;
param.plotstuff=0;

reset(gpud);

param.initD = Dnmf1s;
[D1, Dgn1] = twolevelDL_gpu(abs(data1.X), param);

reset(gpud);

param.initD = Dnmf2s;
[D2, Dgn2] = twolevelDL_gpu(abs(data2.X), param);

reset(gpud);

    model_name = sprintf('%s-K%d-lambda%d-beta%d',model,param.K,round(10*param.lambda),round(10*param.beta));


    %% test models

    % saving setting

    save_folder = sprintf('/misc/vlgscratch3/LecunGroup/bruna/speech/%s-s%d-s%d-%s/',model_name,id_1,id_2,date());

    try
        unix(sprintf('mkdir %s',save_folder));
        unix(sprintf('chmod 777 %s ',save_folder));
    catch
    end

    %%


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

        %x1 = x1/norm(x1);
        %x2 = x2/norm(x2);

        mix = (x1+x2);

        X = compute_spectrum(mix,NFFT,hop);
	if param.renorm
	Xr = renorm_spect_data(X, stds);
	end
        % compute decomposition
	%oldnu = param.nu;
	param.nu=0;
	param.alpha_step=1;
	param.gradient_descent=0;
	param.itersout=800;
	[Z1dm, Z1gn1dm, Z2dm, Zgn2dm] = twolevellasso_gpu_demix(abs(Xr), D1, Dgn1, D2, Dgn2, param);

	W1H1 = D1*Z1dm;
	W2H2 = D2*Z2dm;
	
        eps = 1e-6;
        V_ap = W1H1 +W2H2 + eps;

        % wiener filter

        SPEECH1 = ((W1H1.^2)./(V_ap.^2)).*X(:,1:size(V_ap,2));
        SPEECH2 = ((W2H2.^2)./(V_ap.^2)).*X(:,1:size(V_ap,2));
        speech1 = invert_spectrum(SPEECH1,NFFT,hop,T);
        speech2 = invert_spectrum(SPEECH2,NFFT,hop,T);
	m = length(speech1);

        Parms =  BSS_EVAL(x1(1:m)', x2(1:m)', speech1', speech2', mix(1:m)');
        
        NSDR = SDR+mean(Parms.NSDR)/N_test;
        SIR = SIR+mean(Parms.SIR)/N_test;
        
        Parms
        output{i} = Parms;

        file1 = sprintf('%s%dspeech-1.wav',save_folder,i);
        audiowrite(file1,speech1,fs);
        unix(sprintf('chmod 777 %s',file1));

        file2 = sprintf('%s%dspeech-2.wav',save_folder,i);
        audiowrite(file2,speech2,fs);
        unix(sprintf('chmod 777 %s',file2));

        filemix = sprintf('%s%dmix.wav',save_folder,i);
        audiowrite(filemix,mix,fs);
        unix(sprintf('chmod 777 %s',filemix));

    end
    save_file = sprintf('%sresults.mat',save_folder,'s');
    save(save_file,'output','D1','D2','param','NSDR','SIR')
    unix(sprintf('chmod 777 %s ',save_file));
    AA{ii,jj}.res = output;
    clear output
end
end

