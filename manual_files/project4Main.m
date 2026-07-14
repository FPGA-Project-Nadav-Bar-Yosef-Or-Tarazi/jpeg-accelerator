%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Nadav Bar Yosef (207218389), Or Tarazi (208329458)
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%

% Load benchmark data from JPEGbenchmark.mat
benchData = load('JPEGbenchmark.mat');

% List of image files to process
imageFiles = {'cat800x800.bmp', 'flower800x800.bmp', 'zakir800x800.bmp', 'shades800x800.bmp'};

% Delta values to test (question b)
deltaValues = [0.5, 0.25, 0.1, 0.05, 0.01, 0.005, 0.001];

for idx = 1:length(imageFiles)
    % Read image and convert to double grayscale
    BWimage = double(rgb2gray(imread(imageFiles{idx})));
    
    % Preallocate arrays for our compressor (with DPCM)
    psnr_ours = zeros(1, length(deltaValues));
    bpp_ours  = zeros(1, length(deltaValues));
    
    % Preallocate arrays for our compressor without DPCM
    psnr_noDPCM = zeros(1, length(deltaValues));
    bpp_noDPCM  = zeros(1, length(deltaValues));
    
    % Loop over each delta value (question b)
    for d = 1:length(deltaValues)
        delta = deltaValues(d);
        
        % --- Our compression with DPCM ---
        encoded = imageEncoder(BWimage, delta);
        decoded = imageDecoder(encoded, delta);
        mse = mean((BWimage - double(decoded)).^2, 'all');
        psnr_ours(d) = 10 * log10(255^2 / mse);
        bpp_ours(d)  = length(encoded) / (800 * 800);
        
        % --- Our compression without DPCM ---
        encoded_noDPCM = imageEncoder_noDPCM(BWimage, delta);
        decoded_noDPCM = imageDecoder_noDPCM(encoded_noDPCM, delta);
        mse_noDPCM = mean((BWimage - double(decoded_noDPCM)).^2, 'all');
        psnr_noDPCM(d) = 10 * log10(255^2 / mse_noDPCM);
        bpp_noDPCM(d)  = length(encoded_noDPCM) / (800 * 800);
    end
    
    % --- MATLAB's JPEG benchmark (question d) ---
    % Use the benchmark vectors from JPEGbenchmark.mat for the current image.
    switch imageFiles{idx}
        case 'cat800x800.bmp'
            psnr_jpeg = benchData.catPSNRvecJpeg;
            bpp_jpeg  = benchData.catSizevecJpeg;
        case 'flower800x800.bmp'
            psnr_jpeg = benchData.flowerPSNRvecJpeg;
            bpp_jpeg  = benchData.flowerSizevecJpeg;
        case 'zakir800x800.bmp'
            psnr_jpeg = benchData.zakirPSNRvecJpeg;
            bpp_jpeg  = benchData.zakirSizevecJpeg;
        case 'shades800x800.bmp'
            psnr_jpeg = benchData.shadesPSNRvecJpeg;
            bpp_jpeg  = benchData.shadesSizevecJpeg;
    end
    
    % --- Plot the Rate-Distortion Curves for the Current Image ---
    figure;
    plot(bpp_jpeg, psnr_jpeg, '-o', 'LineWidth', 1.5, 'DisplayName', 'MATLAB JPEG');
    hold on;
    plot(bpp_ours, psnr_ours, '-s', 'LineWidth', 1.5, 'DisplayName', 'Our Compression (DPCM)');
    plot(bpp_noDPCM, psnr_noDPCM, '-x', 'LineWidth', 1.5, 'DisplayName', 'Our Compression (No DPCM)');
    xlabel('Bits per Pixel');
    ylabel('PSNR (dB)');
    title(['Rate–Distortion Performance for ', imageFiles{idx}]);
    legend('Location', 'southwest');
    grid on;
    hold off;
    
    % --- Display the Decoded Image for δ = 0.5 (question c) ---
    % Show the decoded image using our compressor (with DPCM) at δ = 0.5.
    decoded_half = imageDecoder(imageEncoder(BWimage, 0.5), 0.5);
    figure;
    imshow(uint8(decoded_half));
    title(['Decoded Image at δ = 0.5 for ', imageFiles{idx}]);
end

%% Answer Qe:
close all;

original = double(rgb2gray(imread('sky.jpeg')));
original = imresize(original, [800 800]);

encoded = imageEncoder_noDPCM(original, 0.1);
matlab_encoding_restored = imageDecoder_noDPCM(encoded, 0.1);

% BWimage = double(rgb2gray(imread('sky.jpg')));
% BWimage = imresize(BWimage, [800 800]);

% run("generated_bitstream.m");   % this creates bitstream

nios_II_encoding_restored = imageDecoder_noDPCM(bitstream_sw, 0.1);

accelerator_encoding_restored = imageDecoder_noDPCM(bitstream_hw, 0.1);

figure;
tiledlayout(2,2, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile;
imshow(uint8(original));
title('Original');

nexttile;
imshow(uint8(matlab_encoding_restored));
title('MATLAB encoding restored');

% nexttile;
% imshow(uint8(transpose(nios_II_encoding_restored)));
% title('Nios II encoding restored');
nexttile;
imshow(uint8(nios_II_encoding_restored));
title('Nios II encoding restored');

nexttile;
imshow(uint8(accelerator_encoding_restored));
title('Accelerator encoding restored');