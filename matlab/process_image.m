function process_image(inFile, outFile, mode, value)
%PROCESS_IMAGE Change an image's resolution or reduce its file size.
%
%   process_image(inFile, outFile, 'resolution', 720)
%       Resizes so the shorter side is 720 px. The shape is kept
%       (no cropping or stretching). Works for 480/720/1080/1440/2160.
%
%   process_image(inFile, outFile, 'filesize', 50)
%       Keeps the width and height, and saves a JPG that is about 50%
%       smaller than the original file.
%
%   Results are printed as KEY=VALUE lines so the web server can read them.
%   Runs in MATLAB (Image Processing Toolbox) and GNU Octave (image package).

    [img, alpha] = readImage(inFile);

    switch lower(mode)
        case 'resolution'
            [h, w, ~] = size(img);
            if h <= w
                newSize = [value, round(w * value / h)];   % landscape: height = value
            else
                newSize = [round(h * value / w), value];   % portrait: width = value
            end

            out = resizeImage(img, newSize);
            clear img;

            [~, ~, ext] = fileparts(outFile);
            if strcmpi(ext, '.png')
                if isempty(alpha)
                    imwrite(out, outFile);
                else
                    outAlpha = resizeImage(alpha, newSize);
                    imwrite(out, outFile, 'Alpha', outAlpha);
                end
            else
                imwrite(flattenOnWhite(out, alpha, newSize), outFile, 'Quality', 95);
            end
            fprintf('WIDTH=%d\nHEIGHT=%d\n', newSize(2), newSize(1));

        case 'filesize'
            img = flattenOnWhite(img, alpha, []);
            info = dir(inFile);
            target = info.bytes * (1 - value / 100);

            % Binary search for the highest JPG quality that fits the target.
            lo = 1; hi = 100; best = 1;
            while lo <= hi
                q = floor((lo + hi) / 2);
                imwrite(img, outFile, 'Quality', q);
                d = dir(outFile);
                if d.bytes <= target
                    best = q;
                    lo = q + 1;
                else
                    hi = q - 1;
                end
            end
            imwrite(img, outFile, 'Quality', best);
            fprintf('WIDTH=%d\nHEIGHT=%d\nQUALITY=%d\n', size(img, 2), size(img, 1), best);

        otherwise
            error('process_image:mode', 'Unknown mode "%s".', mode);
    end
end

function [img, alpha] = readImage(file)
    alpha = [];
    try
        [img, map, alpha] = imread(file);
    catch
        [img, map] = imread(file);  % Octave can't return alpha for some palette PNGs
    end
    if ~isempty(map)
        % Palette image -> true colour. Done by hand because ind2rgb behaves
        % differently in Octave. Integer indices are zero-based.
        idx = double(img);
        if isinteger(img)
            idx = idx + 1;
        end
        idx = min(max(round(idx), 1), size(map, 1));
        img = reshape(map(idx(:), :), [size(idx, 1), size(idx, 2), 3]);
    end
    img = clampToUint8(img);
    if ~isempty(alpha)
        alpha = clampToUint8(alpha);
    end
end

function out = resizeImage(img, newSize)
%RESIZEIMAGE Resize one colour channel at a time to keep memory use low
%   (the free server has only 512 MB).
    channels = size(img, 3);
    out = zeros([newSize, channels], 'uint8');
    for c = 1:channels
        out(:, :, c) = clampToUint8(imresize(img(:, :, c), newSize, 'bicubic'));
    end
end

function img = flattenOnWhite(img, alpha, newSize)
%FLATTENONWHITE Put transparent pixels on a white background (JPG has no alpha).
    if isempty(alpha)
        return;
    end
    if ~isempty(newSize)
        alpha = resizeImage(alpha, newSize);
    end
    a = double(alpha) / 255;
    img = uint8(round(double(img) .* a + 255 * (1 - a)));
end

function img = clampToUint8(img)
    if isa(img, 'uint8')
        return;
    elseif isa(img, 'uint16')
        img = uint8(round(double(img) / 257));
    elseif islogical(img)
        img = uint8(img) * 255;
    else
        img = uint8(round(min(max(double(img), 0), 1) * 255));
    end
end
