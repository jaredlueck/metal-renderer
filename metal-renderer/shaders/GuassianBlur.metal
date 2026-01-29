#include <metal_stdlib>
using namespace metal;

kernel void guassianBlurHorizontal(texture2d<float> mask               [[texture(0)]],
                                   texture2d<float, access::write> output [[texture(1)]],
                                   const device float* kernelBuffer    [[buffer(0)]],
                                   const device uint& kernelSize       [[buffer(1)]],
                                   uint2 gid                           [[thread_position_in_grid]]) {
    int w = mask.get_width();
    int h = mask.get_height();

    // Guard against over-dispatch (when grid size isn't exactly the texture size)
    if (gid.x >= w || gid.y >= h) { return; }

    int halfKs = kernelSize / 2;
    int ks = (int)kernelSize;

    float pixelValue = 0.0f;
    // Convolve horizontally at (gid.x, gid.y)
    for (int i = 0; i < ks; i++) {
        int offset = i - halfKs;
        int x = clamp(int(gid.x) + offset, 0, w - 1);
        float sample = mask.read(uint2(x, gid.y)).r;
        float weight = kernelBuffer[i];
        pixelValue += weight * sample;
    }

    output.write(pixelValue, gid);
}

kernel void guassianBlurVertical(texture2d<float> mask                 [[texture(0)]],
                                 texture2d<float, access::write> output [[texture(1)]],
                                 const device float* kernelBuffer      [[buffer(0)]],
                                 const device uint& kernelSize         [[buffer(1)]],
                                 uint2 gid                             [[thread_position_in_grid]]) {
    int w = mask.get_width();
    int h = mask.get_height();

    if (gid.x >= w || gid.y >= h) { return; }

    int halfKs = kernelSize / 2;
    int ks = (int)kernelSize;

    float pixelValue = 0.0f;
    // Convolve vertically at (gid.x, gid.y)
    for (int i = 0; i < ks; i++) {
        int offset = i - halfKs;
        int y = clamp(int(gid.y) + offset, 0, h - 1);
        float sample = mask.read(uint2(gid.x, y)).r;
        float weight = kernelBuffer[i];
        pixelValue += weight * sample;
    }

    output.write(pixelValue, gid);
}

kernel void blurOutline(texture2d<float> mask [[texture(0)]], texture2d<float> blur [[texture(1)]], texture2d<float, access::write> outline [[texture(2)]],
    uint2 gid [[thread_position_in_grid]]) {
    int w = mask.get_width();
    int h = mask.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float maskVal = mask.read(gid).r;
    float blurVal = blur.read(gid).r;
    float outlineVal = maskVal == 1.0 ? 0.0 : blurVal;
    outline.write(outlineVal, gid);
}
