%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% imageDecoder_noDPCM.m
%
% This function decodes a JPEG-like bit stream produced by imageEncoder_noDPCM.m.
% It reverses the operations of the encoder, except that no DPCM was applied.
% The steps are:
%  1. Separate the input bit stream into the Golomb-encoded part and the
%     last nonzero indices (6 bits per block for 10,000 blocks).
%  2. Convert the last nonzero indices to numbers (adding 1).
%  3. For each block, decode coefficients (up to the last nonzero) using golomb_dec.
%  4. Fill the remaining coefficients (indices current_lastNZ+1 to 64) with zeros.
%  5. Apply inverse zigzag ordering to reconstruct the 8x8 block.
%  6. Reshape the blocks into an 8x8x100x100 array.
%  7. (No inverse DPCM step since it wasn’t applied during encoding.)
%  8. Inverse Quantization (multiply by delta).
%  9. Apply the inverse 2D DCT (idct2) to each block.
% 10. Reassemble the blocks into an 800x800 image.
% 11. Inverse Image Scaling (multiply by 256 and add 128) and convert to uint8.
%
% Usage:
%   decodedImage = imageDecoder_noDPCM(inputBitStream, delta)
%
% Input:
%   inputBitStream - A char array containing the complete encoded bit stream.
%   delta          - The quantization step size.
%
% Output:
%   decodedImage   - The reconstructed image (uint8, 800x800).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% function [decodedImage] = imageDecoder_noDPCM(inputBitStream, delta)
%     %% 1. Constants and Separating the Bit Stream
%     M = 8;               % Block size
%     imgSize = 64;       % Image dimensions: 800x800
%     nBlocks = (imgSize/M)^2;  % 10000 blocks
%     bitsPerBlock = 6;    % 6 bits per block for last nonzero index
%     totalLastNZBits = nBlocks * bitsPerBlock;  % 60000 bits
% 
%     totalLength = length(inputBitStream);
%     % Separate the Golomb-encoded part and the last nonzero indices.
%     GolombBitStream = inputBitStream(1 : totalLength - totalLastNZBits);
%     lastNZ_bit_stream = inputBitStream(totalLength - totalLastNZBits + 1 : end);
% 
%     %% 2. Convert Last Nonzero Indices to Numbers
%     bitMatrix = reshape(lastNZ_bit_stream, bitsPerBlock, nBlocks)';
%     lastNZArray = bin2dec(bitMatrix) + 1;  % nBlocks x 1 vector
% 
%     %% 3. Golomb Decoding for Each Block
%     zigzagBlocks = zeros(64, 100, 100);
%     startIndex = 1;
%     blockIndex = 1;
%     for i = 1:100
%         for j = 1:100
%             current_lastNZ = lastNZArray(blockIndex);
%             current_block = zeros(64, 1);
%             for k = 1:current_lastNZ
%                 [cursymbol, nextStartIndex] = golomb_dec(GolombBitStream, startIndex);
%                 current_block(k) = cursymbol;
%                 startIndex = nextStartIndex;
%             end
%             zigzagBlocks(:, i, j) = current_block;
%             blockIndex = blockIndex + 1;
%         end
%     end
% 
%     %% 4. Inverse Zigzag Ordering
%     zigzagOrdMat = load('ZigZagOrd.mat');  % File should contain variable ZigZagOrd
%     zigzagOrd = zigzagOrdMat.ZigZagOrd;
%     [~, invZigzag] = sort(zigzagOrd);
%     quantizedBlocksVec = zeros(64, 100, 100);
%     for i = 1:100
%         for j = 1:100
%             tempBlock = zigzagBlocks(:, i, j);
%             quantizedBlocksVec(:, i, j) = tempBlock(invZigzag);
%         end
%     end
% 
%     %% 5. Reshape to 4D Array of Quantized DCT Coefficients (8x8x100x100)
%     quantizedBlocks = reshape(quantizedBlocksVec, M, M, 100, 100);
% 
%     %% 6. (No Inverse DPCM) – DC coefficients remain as decoded.
% 
%     %% 7. Inverse Quantization: Multiply by delta
%     quantizedBlocks = quantizedBlocks * delta;
% 
%     %% 8. Apply Inverse DCT (idct2) to Each Block
%     reconstructedBlocks = zeros(size(quantizedBlocks));
%     for i = 1:size(quantizedBlocks, 3)
%         for j = 1:size(quantizedBlocks, 4)
%             reconstructedBlocks(:,:,j,i) = transpose(idct2(quantizedBlocks(:,:,i,j)));
%         end
%     end
% 
%     %% 9. Deblocking: Reassemble Blocks into Full Image
%     temp = permute(reconstructedBlocks, [1, 3, 2, 4]);
%     decodedImage = reshape(temp, imgSize, imgSize);
% 
%     %% 10. Inverse Image Scaling: Convert back to [0,255] and uint8.
%     decodedImage = decodedImage * 256 + 128;
%     decodedImage = uint8(decodedImage);
% end

function [decodedImage] = imageDecoder_noDPCM(inputBitStream, delta)
    %% 1. Constants and Separating the Bit Stream
    M = 8;                 % Block size
    imgSize = 64;          % Image dimensions: 64x64
    blocksPerDim = imgSize / M;   % 8 blocks in each dimension
    nBlocks = blocksPerDim^2;     % 64 blocks

    bitsPerBlock = 6;      
    totalLastNZBits = nBlocks * bitsPerBlock;  % 64 * 6 = 384 bits

    totalLength = length(inputBitStream);

    % Separate the Golomb-encoded part and the last nonzero indices.
    GolombBitStream = inputBitStream(1 : totalLength - totalLastNZBits);
    lastNZ_bit_stream = inputBitStream(totalLength - totalLastNZBits + 1 : end);
    
    %% 2. Convert Last Nonzero Indices to Numbers
    bitMatrix = reshape(lastNZ_bit_stream, bitsPerBlock, nBlocks)';
    lastNZArray = bin2dec(bitMatrix) + 1;

    %% 3. Golomb Decoding for Each Block
    zigzagBlocks = zeros(64, blocksPerDim, blocksPerDim);

    startIndex = 1;
    blockIndex = 1;

    for i = 1:blocksPerDim
        for j = 1:blocksPerDim
            current_lastNZ = lastNZArray(blockIndex);

            current_block = zeros(64, 1);

            for k = 1:current_lastNZ
                [cursymbol, nextStartIndex] = golomb_dec(GolombBitStream, startIndex);
                current_block(k) = cursymbol;
                startIndex = nextStartIndex;
            end

            zigzagBlocks(:, i, j) = current_block;
            blockIndex = blockIndex + 1;
        end
    end
    
    %% 4. Inverse Zigzag Ordering
    zigzagOrdMat = load('ZigZagOrd.mat');
    zigzagOrd = zigzagOrdMat.ZigZagOrd;

    [~, invZigzag] = sort(zigzagOrd);

    quantizedBlocksVec = zeros(64, blocksPerDim, blocksPerDim);

    for i = 1:blocksPerDim
        for j = 1:blocksPerDim
            tempBlock = zigzagBlocks(:, i, j);
            quantizedBlocksVec(:, i, j) = tempBlock(invZigzag);
        end
    end
    
    %% 5. Reshape to 4D Array of Quantized DCT Coefficients
    quantizedBlocks = reshape(quantizedBlocksVec, M, M, blocksPerDim, blocksPerDim);
    
    %% 6. Inverse Quantization
    quantizedBlocks = quantizedBlocks * delta;
    
    %% 7. Apply Inverse DCT to Each Block
    reconstructedBlocks = zeros(size(quantizedBlocks));

    for i = 1:blocksPerDim
        for j = 1:blocksPerDim
            reconstructedBlocks(:,:,i,j) = idct2(quantizedBlocks(:,:,i,j));
        end
    end
    
    %% 8. Deblocking: Reassemble Blocks into Full Image
    temp = permute(reconstructedBlocks, [1, 3, 2, 4]);
    decodedImage = reshape(temp, imgSize, imgSize);
    
    %% 9. Inverse Image Scaling
    decodedImage = decodedImage * 256 + 128;
    decodedImage = uint8(decodedImage);
end