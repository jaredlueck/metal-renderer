//
//  MaskPipeline.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd

struct GridUniforms{
    var view: simd_float4x4
    var projection: simd_float4x4
    var gridColor: SIMD4<Float>
    var cameraPos: SIMD4<Float>
}

class GridPipeline {
    
    let pipeline: MTLRenderPipelineState
    
    init(device: MTLDevice){
        
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library. Ensure your .metal files are part of the target.")
        }
        guard let vertex = library.makeFunction(name: "gridVertex") else {
            fatalError("Missing Metal function: outline")
        }
        
        guard let fragment = library.makeFunction(name: "gridFragment") else {
            fatalError("Missing Metal function: fragment")
        }
        
        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        descriptor.depthAttachmentPixelFormat = .depth32Float
        descriptor.vertexFunction = vertex
        descriptor.fragmentFunction = fragment

        do {
            self.pipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            fatalError("Failed to create compute pipeline state: \(error)")
        }
  
    }

    func bind(encoder: MTLRenderCommandEncoder, uniforms: GridUniforms) {
        encoder.setRenderPipelineState(self.pipeline)
        withUnsafeBytes(of: uniforms) {
            rawBuffer in encoder.setVertexBytes(rawBuffer.baseAddress!, length: MemoryLayout<GridUniforms>.stride, index: 0)
        }
        withUnsafeBytes(of: uniforms) {
            rawBuffer in encoder.setFragmentBytes(rawBuffer.baseAddress!, length: MemoryLayout<GridUniforms>.stride, index: 0)
        }
    }
}

