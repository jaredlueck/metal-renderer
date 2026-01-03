//
//  SkyboxPipeline.swift
//  metal-swift
//
//  Created by Jared Lueck on 2025-12-08.
//

import Metal

class MirrorPipeline {
    
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    
    init(device: MTLDevice){
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8

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
        // Normal attribute
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1
        // Texture Coordinate attribute
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = 0
        vertexDescriptor.attributes[2].bufferIndex = 1
        // Vertex buffer layout: tightly packed float3 positions
        vertexDescriptor.layouts[1].stride = 32

        // Attach the vertex descriptor to the pipeline
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library. Ensure your .metal files are part of the target.")
        }
        guard let vertexFunction = library.makeFunction(name: "mirrorVertex") else {
            fatalError("Missing Metal function: mirrorVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "mirrorFragment") else {
            fatalError("Missing Metal function: mirrorFragment")
        }

        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction

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

