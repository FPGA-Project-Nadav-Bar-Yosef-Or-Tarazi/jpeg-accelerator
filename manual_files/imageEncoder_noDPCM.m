%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% imageEncoder_noDPCM.m
%
% This function implements a JPEG-like image encoder for grayscale images of
% size 800x800, similar to imageEncoder.m but with the DPCM step omitted.
% The steps are:
%  1. Image scaling (from [0,255] to [-0.5,127/256])
%  2. Blocking into 8x8 blocks (resulting in an 8x8x100x100 array)
%  3. Applying 2D DCT on each block
%  4. Uniform quantization (dividing by delta and rounding)
%  5. (No DPCM on DC coefficients; leave them unchanged)
%  6. Zigzag ordering (using the ordering from ZigZagOrd.mat)
%  7. Finding the last nonzero element in each block and converting it to a
%     6-bit binary string.
%  8. Entropy coding: For each block, each coefficient (up to last nonzero) is
%     encoded individually. If a coefficient is zero, output "10" so that
%     golomb_dec (unchanged) will decode correctly.
%  9. The final output bit stream is the concatenation of all the Golomb-coded
%     bits and the bit stream for the last nonzero indices.
%
% Usage:
%   outputBitStream = imageEncoder_noDPCM(image, delta)
%
% Input:
%   image - Grayscale image (double, 800x800) after rgb2gray conversion.
%   delta - Quantization step size.
%
% Output:
%   outputBitStream - A char array containing the complete encoded bit stream.
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

function [outputBitStream] = imageEncoder_noDPCM(image, delta)
    %% 1. Image Scaling
    image = (image - 128) / 256;

    %% 2. Blocking into 8x8 blocks (800x800 -> 8x8x100x100)
    ImBlocksTemp = reshape(image, 8, 100, 8, 100);
    ImageBlocks = permute(ImBlocksTemp, [1, 3, 2, 4]);

    %% 3. Apply 2D DCT to each 8x8 block
    imageDCT = zeros(size(ImageBlocks));
    for i = 1:size(ImageBlocks, 3)
        for j = 1:size(ImageBlocks, 4)
            imageDCT(:,:,i,j) = dct2(ImageBlocks(:,:,i,j));
        end
    end

    %% 4. Uniform Quantization
    quantizedBlocks = round(imageDCT / delta);

    %% 5. (No DPCM) – Leave DC coefficients unchanged.

    %% 6. Zigzag Ordering
    zigzagOrdMat = load('ZigZagOrd.mat');  % Should contain variable ZigZagOrd
    zigzagOrd = zigzagOrdMat.ZigZagOrd;
    % Reshape each 8x8 block into a 64-element column vector
    zigzagBlocks = reshape(quantizedBlocks, 64, 100, 100);
    % Apply zigzag ordering
    zigzagBlocks = zigzagBlocks(zigzagOrd, :, :);

    %% 7. Find the Last Nonzero Element in Each Block
    nBlocks = size(zigzagBlocks, 2) * size(zigzagBlocks, 3);  % Should be 10000
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
    % Convert to 6-bit binary strings (subtract 1 per spec)
    bitsoflastNZ = dec2bin(lastNZArray - 1, 6);
    lastNZ_bit_stream = reshape(bitsoflastNZ', 1, []);  % 1 x (6*nBlocks) char array

    %% 8. Entropy Coding for Each Block
    % Encode coefficients 1 to current_lastNZ for each block individually.
    % If a coefficient equals zero, output "10".
    Gol_bitstream = strings(1, nBlocks);  % Preallocate for 10000 blocks
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
                    % Wrap the symbol in a vector for golomb_enc
                    current_Gol_bitstream = current_Gol_bitstream + string(golomb_enc(current_block(symIdx)));
                end
            end
            Gol_bitstream(k) = current_Gol_bitstream;
            k = k + 1;
        end
    end
    % Concatenate all Golomb-coded bits into one char array.
    Gol_bitstream_cat = char(strjoin(Gol_bitstream, ''));
    
    %% 9. Final Output Bit Stream
    outputBitStream = [Gol_bitstream_cat, lastNZ_bit_stream];
end
