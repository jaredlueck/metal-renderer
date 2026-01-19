//
//  VertexDescriptors.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2025-12-31.
//

import Metal
import ModelIO
enum VertexDescriptors{
    static func mtl() -> MTLVertexDescriptor {
        let vertexDescriptor = MTLVertexDescriptor()
        // Position attribute at location 0 (float3)
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        // Normal attribute
        vertexDescriptor.attributes[1].format = .float3
        vertexDescriptor.attributes[1].offset = MemoryLayout<Float>.size * 3
        vertexDescriptor.attributes[1].bufferIndex = 0
        // Texture Coordinate attribute
        vertexDescriptor.attributes[2].format = .float2
        vertexDescriptor.attributes[2].offset = MemoryLayout<Float>.size * 6
        vertexDescriptor.attributes[2].bufferIndex = 0
        // Vertex buffer layout: tightly packed float3 positions
        vertexDescriptor.layouts[0].stride = 32
        
        return vertexDescriptor
    }
    
    static func mdl() -> MDLVertexDescriptor {
        let mdlVertexDescriptor = MDLVertexDescriptor()
        
        let positionAttribute = MDLVertexAttribute()
        positionAttribute.name = "position"
        positionAttribute.format = .float3
        positionAttribute.bufferIndex = 0
        positionAttribute.offset = 0
        
        let normalAttribute = MDLVertexAttribute()
        normalAttribute.name = "normal"
        normalAttribute.format = .float3
        normalAttribute.bufferIndex = 0
        normalAttribute.offset = MemoryLayout<Float>.size * 3
        
        let textureCoordinateAttribute = MDLVertexAttribute()
        textureCoordinateAttribute.name = "texcoord"
        textureCoordinateAttribute.format = .float2
        textureCoordinateAttribute.bufferIndex = 0
        textureCoordinateAttribute.offset = MemoryLayout<Float>.size * 6
        
        mdlVertexDescriptor.attributes = [positionAttribute, normalAttribute, textureCoordinateAttribute]
        
        let layout = MDLVertexBufferLayout(stride: 32)
        mdlVertexDescriptor.layouts = [layout]
        
        return mdlVertexDescriptor
    }
}
