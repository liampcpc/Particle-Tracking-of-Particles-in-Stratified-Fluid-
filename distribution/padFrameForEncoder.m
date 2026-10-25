function Fp = padFrameForEncoder(F)
% PADFRAMEFORENCODER Pad a frame's width/height up to the next multiple of 16 by replicating the edge pixels

padH = mod(-size(F,1), 16);
padW = mod(-size(F,2), 16);

if padH == 0 && padW == 0
    Fp = F;
else
    Fp = padarray(F, [padH padW], 'replicate', 'post');
end

end
