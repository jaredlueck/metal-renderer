//
//  Scene.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-09.
//

import simd

public struct Node {
    
    var transform: simd_float4x4 = matrix_identity_float4x4
    var children: [Node] = []
    var model: Model? = nil
}

public class Scene {
    var rootNode: Node = Node()
        
    public func add(_ node: Node) {
        rootNode.children.append(node)
    }
}
