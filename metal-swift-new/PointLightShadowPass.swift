//
//  CubeShadowRenderPass.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-29.
//

import Metal
import simd

struct ShadowUniforms {
    var vp: simd_float4x4
    var position: simd_float3
    var far: simd_float1
}

let faceDirections: [SIMD3<Float>] = [
    SIMD3<Float>( 1,  0,  0),
    SIMD3<Float>(-1,  0,  0),
    SIMD3<Float>( 0,  1,  0),
    SIMD3<Float>( 0, -1,  0),
    SIMD3<Float>( 0,  0,  1),
    SIMD3<Float>( 0,  0, -1)
]

let faceUps: [SIMD3<Float>] = [
    SIMD3<Float>(0, -1,  0),
    SIMD3<Float>(0, -1,  0),
    SIMD3<Float>(0,  0,  1),
    SIMD3<Float>(0,  0,  1),
    SIMD3<Float>(0, -1,  0),
    SIMD3<Float>(0, -1,  0)
]

class PointLightShadowPass {
    let descriptor: MTLRenderPassDescriptor;
    let pipeline: CubeShadowPipeline
    init(device: MTLDevice){
        self.descriptor = MTLRenderPassDescriptor()
        self.descriptor.colorAttachments[0].loadAction = .clear
        self.descriptor.colorAttachments[0].storeAction = .store
        
        self.pipeline = CubeShadowPipeline(device: device)
    }
    
    func encode(commandBuffer: MTLCommandBuffer, sharedResources: inout SharedResources){
        let cubeTextureArray = sharedResources.pointLightShadowAtlas!
        
        for i in 0..<sharedResources.pointLights.count {
            let light = sharedResources.pointLights[i]
            for face in 0..<6{
                let slice = i * 6 + face
                let faceTexture = cubeTextureArray.makeTextureView(
                    pixelFormat: .r32Float, textureType: MTLTextureType.type2D, levels: 0..<1, slices: slice..<(slice+1))
                self.descriptor.colorAttachments[0].texture = faceTexture
                self.descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0)
                guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: self.descriptor) else {
                    fatalError("failed to create encoder")
                }
                let lightPosition = SIMD3<Float>(light.position.x, light.position.y, light.position.z)
                let forward = faceDirections[face]
                let up = faceUps[face]
                let view = matrix_lookAt(eye: lightPosition, target: lightPosition + forward, up: up)
                let projection = matrix_perspective_right_hand(fovyRadians: radians_from_degrees(90), aspectRatio: 1, nearZ: 1, farZ: light.radius)
                                                               
                let vp = matrix_multiply(projection, view)
                
                pipeline.bind(renderCommandEncoder: encoder, uniforms: ShadowUniforms(vp: vp, position: lightPosition, far: light.radius))
                
                for i in 0..<sharedResources.renderables.count {
                    let renderable = sharedResources.renderables[i]
                    if renderable.castsShadows {
                        renderable.draw(renderEncoder: encoder, instanceId: nil)
                    }
                }
                encoder.endEncoding()
            }
        }
    }
}

