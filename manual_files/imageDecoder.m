%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Nadav Bar Yosef (207218389), Or Tarazi (208329458)
%
% imageDecoder.m
%
% This function implements the decoder for the JPEG-like image compressor.
% It reverses the operations of imageEncoder.m:
%  1. Separates the input bit stream into the Golomb-encoded part and the
%     last nonzero indices (6 bits per block, 10,000 blocks total).
%  2. Converts the last nonzero indices bit stream into numbers (adding 1).
%  3. For each block, decodes coefficients (up to the last nonzero index)
%     using golomb_dec.
%  4. Fills the remainder of each 64-element block with zeros.
%  5. Applies inverse zigzag ordering to reconstruct the 8x8 block.
%  6. Reshapes the 64-element vectors into 8x8 blocks (forming a 4D array).
%  7. Applies inverse DPCM on the DC coefficients.
%  8. Performs inverse quantization (multiplying by delta).
%  9. Applies the inverse 2D DCT (idct2) to each block.
% 10. Reassembles the blocks into an 800x800 image.
% 11. Applies inverse image scaling (multiplies by 256 and adds 128) and casts
%     to uint8.
%
% Usage:
%   decodedImage = imageDecoder(inputBitStream, delta)
%
% Input:
%   inputBitStream - A char array containing the complete encoded bit stream.
%   delta          - The quantization step size.
%
% Output:
%   decodedImage   - The reconstructed image (uint8, 800x800).
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [decodedImage] = imageDecoder(inputBitStream, delta)
    %% 1. Constants and Separating the Bit Stream
    M = 8;                        % Block size
    imgSize = 800;                % Image dimensions: 800x800
    nBlocks = (imgSize/M)^2;      % 10000 blocks
    bitsPerBlock = 6;             % 6 bits per block for last nonzero index
    totalLastNZBits = nBlocks * bitsPerBlock;  % 60000 bits

    totalLength = length(inputBitStream);
    % Separate the Golomb encoded part and the last-nonzero indices.
    GolombBitStream = inputBitStream(1 : totalLength - totalLastNZBits);
    lastNZ_bit_stream = inputBitStream(totalLength - totalLastNZBits + 1 : end);
    
    %% 2. Convert Last Nonzero Indices Bit Stream to Numbers
    bitMatrix = reshape(lastNZ_bit_stream, bitsPerBlock, nBlocks)';
    lastNZArray = bin2dec(bitMatrix) + 1;  % 10000x1 vector

    %% 3. Golomb Decoding for Each Block
    zigzagBlocks = zeros(64, 100, 100);
    startIndex = 1;
    blockIndex = 1;
    for i = 1:100
        for j = 1:100
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
    invZigzag = zigzagOrdMat.ZigZagOrdInv;

    quantizedBlocksVec = zeros(64, 100, 100);
    for i = 1:100
        for j = 1:100
            tempBlock = zigzagBlocks(:, i, j);
            quantizedBlocksVec(:, i, j) = tempBlock(invZigzag);
        end
    end
    
    %% 5. Reshape to 4D Array of Quantized DCT Coefficients (8x8x100x100)
    quantizedBlocks = reshape(quantizedBlocksVec, M, M, 100, 100);
    
    %% 6. Inverse DPCM on DC Coefficients
    DC = squeeze(quantizedBlocks(1,1,:,:));  % 100x100 matrix
    for r = 1:size(DC,1)
        for c = 2:size(DC,2)
            DC(r,c) = DC(r,c) + DC(r, c-1);
        end
    end
    quantizedBlocks(1,1,:,:) = reshape(DC, 1, 1, size(DC,1), size(DC,2));
    
    %% 7. Inverse Quantization: Multiply by delta
    quantizedBlocks = quantizedBlocks * delta;
    
    %% 8. Apply Inverse DCT (IDCT) to Each Block
    reconstructedBlocks = zeros(size(quantizedBlocks));
    for i = 1:size(quantizedBlocks, 3)
        for j = 1:size(quantizedBlocks, 4)
            reconstructedBlocks(:,:,i,j) = idct2(quantizedBlocks(:,:,i,j));
        end
    end
    
    %% 9. Deblocking: Reassemble the Blocks into the Full Image
    temp = permute(reconstructedBlocks, [1, 3, 2, 4]);
    decodedImage = reshape(temp, imgSize, imgSize);
    
    %% 10. Inverse Image Scaling: Convert back to [0,255] and uint8.
    decodedImage = decodedImage * 256 + 128;
    decodedImage = uint8(decodedImage);
end
