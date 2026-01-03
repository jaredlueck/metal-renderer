//
//  SkyboxPipeline.swift
//  metal-swift
//
//  Created by Jared Lueck on 2025-12-08.
//

import Metal

class SkyboxPipeline {
    
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    
    init(device: MTLDevice){
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8

        let depthStencilDescriptor = MTLDepthStencilDescriptor()
        depthStencilDescriptor.isDepthWriteEnabled = false
        depthStencilDescriptor.depthCompareFunction = .always
        
        
        guard let depthStencilState = device.makeDepthStencilState(descriptor: depthStencilDescriptor) else {
            fatalError("Failed to create MTLDepthStencilState. Check device support and descriptor configuration.")
        }
        self.depthStencilState = depthStencilState

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library. Ensure your .metal files are part of the target.")
        }
        guard let vertexFunction = library.makeFunction(name: "skyboxVertex") else {
            fatalError("Missing Metal function: passthroughVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "skyboxFragment") else {
            fatalError("Missing Metal function: skyboxFragment")
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
        renderCommandEncoder.setCullMode(.none)
    }
}

