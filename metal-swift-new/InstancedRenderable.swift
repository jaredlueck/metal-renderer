//
//  Entity.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-27.
//
import Metal
import MetalKit
import ModelIO

struct Material {
    let baseColor: SIMD3<Float>
}

struct Instance {
    var id: String
    var transform: simd_float4x4
    var selected: Bool = false
}

class InstancedRenderable {
    public var castsShadows: Bool = true
    public var selectable = true
    let model: Model
    let sampler: MTLSamplerState
    public var instances: [Instance] = []
    var instanceBuffer: MTLBuffer?
    let device: MTLDevice
    
    init(device: MTLDevice, model: Model) {
        self.model = model
        let samplerDescriptor = MTLSamplerDescriptor()
        samplerDescriptor.minFilter = .linear
        samplerDescriptor.magFilter = .linear
        samplerDescriptor.mipFilter = .linear
        guard let sampler = device.makeSamplerState(descriptor: samplerDescriptor) else {
            fatalError("Failed to create sampler state")
        }
        self.sampler = sampler
        self.device = device
    }

    func addInstance(transform: simd_float4x4) {
        let id = UUID().uuidString
        instances.append(Instance(id: id, transform: transform))
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, instanceId: String?) {
        var transforms: [float4x4] = []
        transforms = (instanceId.flatMap { id in instances.first(where: { $0.id == id }) }.map { [$0.transform] })
            ?? instances.map { $0.transform }
        
        let bufferlength = MemoryLayout<simd_float4x4>.stride * transforms.count

        transforms.withUnsafeBytes { rawBuffer in
            renderEncoder.setVertexBytes(
                rawBuffer.baseAddress!,
                length: bufferlength,
                index: Bindings.instanceData
            )
        }

        for i in 0..<model.asset.count {
            guard let mdlMesh = model.asset.object(at: i) as? MDLMesh else { continue }

            if let mtkBuffer = mdlMesh.vertexBuffers.first as? MTKMeshBuffer {
                renderEncoder.setVertexBuffer(mtkBuffer.buffer, offset: 0, index: Bindings.vertexBuffer)
            }

            if let mdlSubmeshes = mdlMesh.submeshes as? [MDLSubmesh] {
                for mdlSubmesh in mdlSubmeshes {
                    let indexCount = mdlSubmesh.indexCount
                    let indexType: MTLIndexType
                    let material = mdlSubmesh.material
                    let baseColorPropery = material?.propertyNamed("baseColor")
                    let baseColor = baseColorPropery?.float3Value
                    var materialUniform = Material(baseColor: baseColor ?? .zero)
                    
                    withUnsafeBytes(of: &materialUniform )  { rawBuffer in
                        renderEncoder.setFragmentBytes(rawBuffer.baseAddress!, length: MemoryLayout<Material>.stride, index: Bindings.materialData)
                        
                    }
                    
                    switch mdlSubmesh.indexType {
                    case .uInt16:
                        indexType = .uint16
                    case .uInt32:
                        indexType = .uint32
                    default:
                        indexType = .uint32
                    }

                    // MDLSubmesh.indexBuffer is an MDLMeshBuffer; bridge to MTKMeshBuffer if possible
                    if let mtkIndexBuffer = mdlSubmesh.indexBuffer as? MTKMeshBuffer {
                        renderEncoder.drawIndexedPrimitives(
                            type: .triangle,
                            indexCount: indexCount,
                            indexType: indexType,
                            indexBuffer: mtkIndexBuffer.buffer,
                            indexBufferOffset: 0,
                            instanceCount: transforms.count,
                        )
                    }
                }
            }
        }
        renderEncoder.setFragmentSamplerState(sampler, index: 0)
    }
}

