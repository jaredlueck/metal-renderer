//
//  Entity.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-27.
//
import Metal
import MetalKit
import ModelIO

class Instance {
    var id: String
    var transform: Transform
    var castsShadows: Bool = true
    var material: Material
//    var renderable: InstancedRenderable
    
    init(transform: Transform, material: Material) {
        self.id = UUID().uuidString
        self.transform = transform
        self.material = material
    }
}

class InstancedRenderable {
    public var selectable = true
    let model: Model
    public var instances: [Instance] = []
    var instanceBuffer: MTLBuffer?
    let device: MTLDevice
    
    init(device: MTLDevice, model: Model) {
        self.model = model
        self.device = device
    }
    
    init(device: MTLDevice, model: Model, instances: [Instance]) {
        self.model = model
        self.device = device
        self.instances = instances
    }

    func addInstance(instance: Instance) {
        let id = UUID().uuidString
        instances.append(instance)
    }
    
    func draw(renderEncoder: MTLRenderCommandEncoder, instanceId: String?) {
        for i in 0..<model.asset.count {
            guard let mdlMesh = model.asset.object(at: i) as? MDLMesh else { continue }
            
            if let mtkBuffer = mdlMesh.vertexBuffers.first as? MTKMeshBuffer {
                renderEncoder.setVertexBuffer(mtkBuffer.buffer, offset: 0, index: Int(BufferIndexVertex.rawValue))
            }
            
            if let mdlSubmeshes = mdlMesh.submeshes as? [MDLSubmesh] {
                for mdlSubmesh in mdlSubmeshes {
                    let indexCount = mdlSubmesh.indexCount
                    let indexType: MTLIndexType
                    let instanceData = instances.map { InstanceData(model: $0.transform.getMatrix(), normalMatrix: $0.transform.getNormalMatrix(), baseColor: $0.material.baseColor, specular:$0.material.specular, roughness: $0.material.roughness, albedo: $0.material.albedo, shininess: $0.material.shininess) }
                    let bufferlength = MemoryLayout<InstanceData>.stride * instanceData.count

                    instanceData.withUnsafeBytes { rawBuffer in
                        renderEncoder.setVertexBytes(
                            rawBuffer.baseAddress!,
                            length: bufferlength,
                            index: Int(BufferIndexInstanceData.rawValue)
                        )
                        renderEncoder.setFragmentBytes(
                            rawBuffer.baseAddress!,
                            length: bufferlength,
                            index: Int(BufferIndexInstanceData.rawValue)
                        )
                    }

                    switch mdlSubmesh.indexType {
                    case .uInt16:
                        indexType = .uint16
                    case .uInt32:
                        indexType = .uint32
                    default:
                        indexType = .uint32
                    }

                    if let mtkIndexBuffer = mdlSubmesh.indexBuffer as? MTKMeshBuffer {
                        renderEncoder.drawIndexedPrimitives(
                            type: .triangle,
                            indexCount: indexCount,
                            indexType: indexType,
                            indexBuffer: mtkIndexBuffer.buffer,
                            indexBufferOffset: 0,
                            instanceCount: instanceData.count,
                        )
                    }
                }
            }
        }
    }
}

