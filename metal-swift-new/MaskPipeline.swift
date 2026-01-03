//
//  MaskPipeline.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd
struct MaskUniforms {
    var view: simd_float4x4
    var projection: simd_float4x4
}

class MaskPipeline {
    
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    
    init(device: MTLDevice){
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .r32Float

        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = false
        
        
        guard let depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor) else {
            fatalError("Failed to create MTLDepthStencilState. Check device support and descriptor configuration.")
        }
        self.depthStencilState = depthStencilState
        
        let vertexDescriptor = MTLVertexDescriptor()
        // Position attribute at location 0 (float3)
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 1
        
        vertexDescriptor.layouts[1].stride = 32

        // Attach the vertex descriptor to the pipeline
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library. Ensure your .metal files are part of the target.")
        }
        guard let vertexFunction = library.makeFunction(name: "maskVertex") else {
            fatalError("Missing Metal function: maskVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "maskFragment") else {
            fatalError("Missing Metal function: maskVertex")
        }

        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }
    
    func bind(renderCommandEncoder: MTLRenderCommandEncoder, uniforms: MaskUniforms){
        withUnsafeBytes(of: uniforms) { rawBuffer in
            renderCommandEncoder.setVertexBytes(rawBuffer.baseAddress!,
                                         length: MemoryLayout<MaskUniforms>.stride,
                                         index: 0)
        }
        renderCommandEncoder.setRenderPipelineState(pipelineState)
        renderCommandEncoder.setDepthStencilState(depthStencilState)
    }
}

