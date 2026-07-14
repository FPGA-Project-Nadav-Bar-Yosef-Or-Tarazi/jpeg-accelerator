function outbitstream = golomb_enc(inputSymbols)

Nsyms = length(inputSymbols);
NbitsLimit = Nsyms*(1+ceil(log2(abs(max(inputSymbols)))));
outbitstream = zeros(1,NbitsLimit);
endpointer = 1;

for nn = 1:Nsyms
    cursymbol = inputSymbols(nn);
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % golomb encoder per symbol
    if (cursymbol ==0)
        % do nothing: symbol = symbol;
    elseif (cursymbol>0)
        cursymbol = 2*cursymbol -1;
    else % if symbol<0
        cursymbol = (-2)*cursymbol;
    end
    
    M = floor(log2(cursymbol + 1));
    prefix = char(['0'*ones(1,M),'1']);
    suffix = dec2bin(cursymbol + 1 - 2^M,M);
    newbits = [prefix,suffix];
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    % now concatenate the output
    %%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
    Nnewbits = length(newbits);
    startpointer = endpointer;
    endpointer = startpointer+Nnewbits;
    outbitstream(startpointer:endpointer-1) = newbits;
end
outbitstream = char((outbitstream(1:endpointer-1)));


