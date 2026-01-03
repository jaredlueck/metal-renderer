//
//  Outlinr.metal
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-02.
//

#include <metal_stdlib>
using namespace metal;

kernel void outline(texture2d<float> mask, texture2d<float, access:: read_write> colorBuffer, texture2d<float, access:: write> output, const device float4& outlineColor [[buffer(0)]], uint2 grid [[thread_position_in_grid]]){
    int radius = 2;
    float maskVal = mask.read(grid).r;
    float4 colorVal = colorBuffer.read(grid);
    
    if(maskVal == 1.0){
        output.write(colorVal, grid);
        return;
    }
    for(int i = -radius ; i < radius ; i++){
        for(int j = -radius; j < radius; j++){
            uint xcoord = max(uint(0), grid.x + i);
            uint ycoord = max(uint(0), grid.y + j);
            maskVal = mask.read(uint2(xcoord, ycoord)).r;
            if(maskVal == 1.0){
                output.write(outlineColor, grid);
                return;
            }
        }
    }
    
    output.write(colorVal, grid);
}
