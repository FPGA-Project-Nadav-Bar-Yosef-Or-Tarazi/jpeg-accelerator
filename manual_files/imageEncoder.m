%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Nadav Bar Yosef (207218389), Or Tarazi (208329458)
%
% imageEncoder.m
%
% This function implements a simple JPEG-like image encoder for grayscale
% images of size 800x800. It performs the following steps:
%  1. Image scaling (from [0,255] to [-0.5,127/256])
%  2. Blocking the image into 8x8 blocks (resulting in a 4D array of size 8x8x100x100)
%  3. Applying DCT to each block
%  4. Uniform quantization (dividing by delta and rounding)
%  5. DPCM for the DC coefficients (applied along each row of blocks)
%  6. Zigzag ordering (using the ordering provided in ZigZagOrd.mat)
%  7. Finding the last nonzero element in each zigzag-ordered block and 
%     converting the index to a 6-bit binary string
%  8. Entropy coding: For each block, encode coefficients from 1 to the last 
%     nonzero index individually. If a coefficient is zero, output "10"
%  9. The final output bit stream is the concatenation of the Golomb-encoded
%     bit streams and the bit stream of last nonzero indices.
%
% Usage:
%   outputBitStream = imageEncoder(image, delta)
%
% Input:
%   image  - Grayscale image (double, 800x800) after rgb2gray conversion.
%   delta  - Quantization step size.
%
% Output:
%   outputBitStream - A char array containing the complete encoded bit stream.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [outputBitStream] = imageEncoder(image, delta)
    %% 1. Image Scaling
    image = (image - 128) / 256;

    %% 2. Blocking: Partition the image into 8x8 blocks
    % (Assumes image is 800x800; 100 blocks per dimension.)
    ImBlocksTemp = reshape(image, 8, 100, 8, 100);
    ImageBlocks = permute(ImBlocksTemp, [1, 3, 2, 4]);  % size: 8x8x100x100

    %% 3. DCT: Apply 2D DCT on each 8x8 block
    imageDCT = zeros(size(ImageBlocks));
    for i = 1:size(ImageBlocks, 3)
        for j = 1:size(ImageBlocks, 4)
            imageDCT(:,:,i,j) = dct2(ImageBlocks(:,:,i,j));
        end
    end

    %% 4. Uniform Quantization
    quantizedBlocks = round(imageDCT / delta);

    %% 5. DPCM for DC Coefficients (only for the (1,1) element of each block)
    DC = squeeze(quantizedBlocks(1,1,:,:));  % 100x100 matrix
    for r = 1:size(DC, 1)
        if size(DC,2) > 1
            DC(r,2:end) = diff(DC(r, :));
        end
    end
    quantizedBlocks(1,1,:,:) = reshape(DC, 1, 1, size(DC,1), size(DC,2));

    %% 6. Zigzag Ordering
    zigzagOrdMat = load('ZigZagOrd.mat');
    zigzagOrd = zigzagOrdMat.ZigZagOrd;
    % Reshape each 8x8 block into a 64-element column vector and apply ordering.
    zigzagBlocks = reshape(quantizedBlocks, 64, 100, 100);  % 64x100x100
    zigzagBlocks = zigzagBlocks(zigzagOrd, :, :);

    %% 7. Find the Last Nonzero Element in Each Block
    nBlocks = size(zigzagBlocks, 2) * size(zigzagBlocks, 3);  % should be 10000
    lastNZArray = zeros(nBlocks, 1);
    k = 1;
    for i = 1:size(zigzagBlocks, 2)
        for j = 1:size(zigzagBlocks, 3)
            current_block = zigzagBlocks(:, i, j);
            current_lastNZ = find(current_block, 1, 'last');
            if isempty(current_lastNZ)
                current_lastNZ = 1;
            end
            lastNZArray(k) = current_lastNZ;
            k = k + 1;
        end
    end
    % Convert last nonzero indices to 6-bit binary strings
    bitsoflastNZ = dec2bin(lastNZArray - 1, 6);  % Each row is a 6-bit string.
    % Concatenate rows to form a single char array (length = 6 * nBlocks)
    lastNZ_bit_stream = reshape(bitsoflastNZ', 1, []);  

    %% 8. Entropy Coding: Encode each block's coefficients individually.
    % For each block, for indices 1 to current_lastNZ:
    % - If the coefficient is zero, output "10"
    % - Otherwise, call golomb_enc on that one symbol.
    Gol_bitstream = strings(1, nBlocks);  % Preallocate string array for 10000 blocks
    k = 1;
    for i = 1:size(zigzagBlocks, 2)
        for j = 1:size(zigzagBlocks, 3)
            current_block = zigzagBlocks(:, i, j);
            current_lastNZ = lastNZArray(k);
            current_Gol_bitstream = "";
            for symIdx = 1:current_lastNZ
                if current_block(symIdx) == 0
                    current_Gol_bitstream = current_Gol_bitstream + "10";
                else
                    % golomb_enc expects a vector, so wrap the symbol in a vector.
                    current_Gol_bitstream = current_Gol_bitstream + string(golomb_enc(current_block(symIdx)));
                end
            end
            Gol_bitstream(k) = current_Gol_bitstream;
            k = k + 1;
        end
    end
    % Concatenate all Golomb bit streams into one string, then convert to char.
    Gol_bitstream_cat = char(strjoin(Gol_bitstream, ''));
    
    %% 9. Compose the Final Encoder Output Bit Stream
    % The final output is the concatenation of the Golomb-encoded coefficients
    % and the last nonzero indices bit stream.
    outputBitStream = [Gol_bitstream_cat, lastNZ_bit_stream];
end
