//
//  ShadowPipeline.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-22.
//

import Metal

class ShadowPipeline {
    
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    
    init(device: MTLDevice){
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float

        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = true
        depthStencilDescriptor.depthCompareFunction = .lessEqual
        
        
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
        guard let vertexFunction = library.makeFunction(name: "shadowVertex") else {
            fatalError("Missing Metal function: mirrorVertex")
        }

        pipelineDescriptor.vertexFunction = vertexFunction

        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }
    
    func bind(renderCommandEncoder: MTLRenderCommandEncoder){
        renderCommandEncoder.setRenderPipelineState(pipelineState)
        renderCommandEncoder.setDepthStencilState(depthStencilState)
       
    }
}

