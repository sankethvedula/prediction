function [S,U,P,PSlp, PShp, scratch] = audioscatt_fwd_haar(in, filts, options)
%this function computes a two-layer speech scattering transform 

%filts{1}: first layer CQT filters
%filts{2}: second layer across-octave filters
%filts{3}: second layer within-octave filters
%filts{4}: second layer dyadic temporal filters

% T : final downsampling factor
% dse : first order downsampling 
J1 = size(filts{1}.psi,2);
%os = getoptions(options,'os',1);
%T = getoptions(options,'T',4096);
%dse = getoptions(options,'dse',round(T*2^(-floor(J/Q)-os)));
dohaar=getoptions(options,'dohaar',1);

[N, L]=size(in);
%Neff = floor(N/dse);
Xf = fft(in);

P=zeros(J1+1,N, L);
%%zeroth order
%tmp = ifft(Xf.*repmat(filts{1}.phi,1,L));
%S0 = tmp(1:filts{1}.ds(J1+1):end,:);

%first layer
for j=1:J1
tmp = (ifft(Xf.*repmat(filts{1}.psi{j},1,L)));
scratch.X{1}(j,:,:) = tmp(1:filts{1}.ds(j):end,:);
P(j,:,:)=exp(i*angle(tmp));
end
tmp = ifft(Xf.*repmat(filts{1}.phi,1,L));
scratch.X{1}(J1+1,:,:) = tmp(1:filts{1}.ds(J1+1):end,:);
P(J1+1,:,:)=exp(i*angle(tmp));

U=abs(scratch.X{1});


%%%we now perform a Haar transform along the path variable, 
%%% and Morlet along time

[K1, Neff, L]=size(U);

if dohaar

Utmp = U(:,:);

Jhaar = size(filts{2}.haar,2);
Ubis = zeros(size(Utmp,1)*size(filts{2}.haar,2),size(Utmp,2));
rast=1;
for j=1:Jhaar
tmp = conv2(Utmp,filts{2}.haar{j},'valid');
scratch.M0h{j}=size(tmp,1); 
tmp = tmp(1:filts{2}.ds(j):end,:);
st = size(tmp,1);
Ubis(rast:rast+st-1,:)=tmp;
scratch.rastbot(1,j)=rast;
scratch.rasttop(1,j)=rast+st-1;
rast=rast+st;
end
Ubis=Ubis(1:rast-1,:);
K1bis = size(Ubis,1);

Ubis = reshape(Ubis,K1bis,Neff, L);
else
Ubis = U;
K1bis=K1;
end
scratch.K1bis = K1bis;
scratch.dohaar=dohaar;

Ubis = permute(Ubis, [2 1 3]);
Utmp = Ubis(:,:);

scratch.M0 = Neff;

Uf=fft(Utmp);
Ubis = zeros(size(Utmp,1),size(filts{4}.psi,2),size(Utmp,2));
rast=1;
for j=1:size(filts{4}.psi,2)
tmp = ifft( Uf.*repmat(filts{4}.psi{j},1,size(Uf,2)) );
%tmp = tmp(1:filts{4}.ds(j):end,:);
Ubis(:,j,:)=tmp;
end
%scratch.X{2} = Ubis;

%phi output
tmp = ifft( Uf.*repmat(filts{4}.phi,1,size(Uf,2)));
%scratch.X{3} = tmp;
PSlp = exp(i*angle(tmp));
Utmp = abs(tmp);
Utmp=Utmp(1:filts{4}.dsphi:end,:);
Ulp = reshape(Utmp, size(Utmp,1),K1bis,L);

%psi output
PShp = exp(i*angle(Ubis));
Utmp = abs(Ubis);
Utmp = Utmp(:,:);
Uf = fft(Utmp);
Utmp = ifft(Uf.*repmat(filts{4}.phi,1,size(Uf,2)));
Utmp = Utmp(1:filts{4}.dsphi:end,:);
Utmp = reshape(Utmp,size(Utmp,1),size(filts{4}.psi,2),K1bis,L);
Utmp(:,size(filts{4}.psi,2)+1,:,:)=Ulp;
K2bis = size(filts{4}.psi,2)+1;

scratch.K2bis = K2bis;

Utmp = reshape(Utmp, size(Utmp,1), K1bis*K2bis, L);
%Utmp(:,end+1,:)=S0;
S = permute(Utmp,[2 1 3]);
S=abs(S);




