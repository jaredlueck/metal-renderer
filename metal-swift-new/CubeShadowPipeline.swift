//
//  ShadowPipeline.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-22.
//

import Metal

class CubeShadowPipeline {
    
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
        guard let vertexFunction = library.makeFunction(name: "cubeShadowVertex") else {
            fatalError("Missing Metal function: mirrorVertex")
        }
        
        guard let fragmentFunction = library.makeFunction(name: "cubeShadowFragment") else {
            fatalError("Missing Metal function: mirrorVertex")
        }

        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }
    
    func bind(renderCommandEncoder: MTLRenderCommandEncoder, uniforms: ShadowUniforms){
        renderCommandEncoder.setRenderPipelineState(pipelineState)
        renderCommandEncoder.setDepthStencilState(depthStencilState)
        renderCommandEncoder.setCullMode(MTLCullMode.back)
        
        withUnsafeBytes(of: uniforms) { rawBuffer in
            renderCommandEncoder.setVertexBytes(rawBuffer.baseAddress!,
                                         length: MemoryLayout<ShadowUniforms>.stride,
                                         index: 0)
        }
        
        withUnsafeBytes(of: uniforms) { rawBuffer in
            renderCommandEncoder.setFragmentBytes(rawBuffer.baseAddress!,
                                         length: MemoryLayout<ShadowUniforms>.stride,
                                         index: 0)
        }
    }
}

