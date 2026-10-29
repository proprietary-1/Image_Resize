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

            out = clampToUint8(imresize(img, newSize, 'bicubic'));

            [~, ~, ext] = fileparts(outFile);
            if strcmpi(ext, '.png')
                if isempty(alpha)
                    imwrite(out, outFile);
                else
                    outAlpha = clampToUint8(imresize(alpha, newSize, 'bicubic'));
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
    [img, map, alpha] = imread(file);
    if ~isempty(map)
        img = ind2rgb(img, map);    % palette image -> true colour
    end
    img = clampToUint8(img);
    if ~isempty(alpha)
        alpha = clampToUint8(alpha);
    end
end

function img = flattenOnWhite(img, alpha, newSize)
%FLATTENONWHITE Put transparent pixels on a white background (JPG has no alpha).
    if isempty(alpha)
        return;
    end
    if ~isempty(newSize)
        alpha = clampToUint8(imresize(alpha, newSize, 'bicubic'));
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
