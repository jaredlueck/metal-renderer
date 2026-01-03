//
//  BlinnPhongPipeline.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-20.
//

import Metal
import simd

struct BlinnPhongUniforms {
    var view: simd_float4x4
    var projection: simd_float4x4
}

class BlinnPhongPipeline {
    
    let pipelineState: MTLRenderPipelineState
    let depthStencilState: MTLDepthStencilState
    let shadowSampler: MTLSamplerState
    
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
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.attributes[1].bufferIndex = 1
        // Texture Coordinate attribute
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = MemoryLayout<Float>.size * 6
        vertexDescriptor.attributes[2].bufferIndex = 1
        // Vertex buffer layout: tightly packed float3 positions
        vertexDescriptor.layouts[1].stride = 32

        // Attach the vertex descriptor to the pipeline
        pipelineDescriptor.vertexDescriptor = vertexDescriptor

        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library. Ensure your .metal files are part of the target.")
        }
        guard let vertexFunction = library.makeFunction(name: "phongVertex") else {
            fatalError("Missing Metal function: phongVertex")
        }
        guard let fragmentFunction = library.makeFunction(name: "phongFragment") else {
            fatalError("Missing Metal function: phongFragment")
        }

        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        
        let shadowSamplerDesc = MTLSamplerDescriptor()
        shadowSamplerDesc.minFilter = .linear
        shadowSamplerDesc.magFilter = .linear
        shadowSamplerDesc.mipFilter = .notMipmapped // depth maps often no mipmaps
        shadowSamplerDesc.sAddressMode = .clampToEdge
        shadowSamplerDesc.tAddressMode = .clampToEdge
        shadowSamplerDesc.rAddressMode = .clampToEdge
        shadowSamplerDesc.normalizedCoordinates = true

        guard let sampler = device.makeSamplerState(descriptor: shadowSamplerDesc) else {
            fatalError("Failed to create shadow comparison sampler")
        }
        shadowSampler = sampler
                
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create render pipeline state: \(error)")
        }
    }
    
    func bind(renderCommandEncoder: MTLRenderCommandEncoder, uniforms: BlinnPhongUniforms, pointLights: [PointLight], shadowMapAtlas: MTLTexture ){
        renderCommandEncoder.setRenderPipelineState(pipelineState)
        renderCommandEncoder.setDepthStencilState(depthStencilState)
        var count: UInt32 = UInt32(pointLights.count)
        renderCommandEncoder.setFragmentBytes(&count, length: MemoryLayout<UInt32>.size, index: 3)
        renderCommandEncoder.setFragmentSamplerState(shadowSampler, index: 1)
        withUnsafeBytes(of: uniforms) { rawBuffer in
            if let base = rawBuffer.baseAddress {
                renderCommandEncoder.setFragmentBytes(base,
                                                    length: MemoryLayout<BlinnPhongUniforms>.stride,
                                                    index: 0)
                renderCommandEncoder.setVertexBytes(base,
                                                    length: MemoryLayout<BlinnPhongUniforms>.stride,
                                                    index: 0)
            }
        }

        pointLights.withUnsafeBytes( { (sourcePtr: UnsafeRawBufferPointer) in
            renderCommandEncoder.setFragmentBytes(sourcePtr.baseAddress!, length: MemoryLayout<PointLight>.stride * pointLights.count, index: 2)
        })
        renderCommandEncoder.setFragmentTexture(shadowMapAtlas, index: 1)
    }
}

