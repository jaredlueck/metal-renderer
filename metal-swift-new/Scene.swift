//
//  Scene.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-09.
//

import simd
import Foundation

struct RenderableInstance {
    var nodeId: String
    var transform: simd_float4x4
    var castsShadows: Bool = true
}

public struct SceneData{
    var renderables: [String: [RenderableInstance]] = [:]
    var pointLights: [PointLight] = []
}

public struct LightSceneData: Codable {
    var color: SIMD3<Float>
    var radius: Float
}

struct Matrix4x4ArrayCodable: Codable {
    var value: simd_float4x4

    init(_ v: simd_float4x4) { self.value = v }

    init(from decoder: Decoder) throws {
        var outer = try decoder.unkeyedContainer()
        var rows: [[Float]] = []
        rows.reserveCapacity(4)
        while !outer.isAtEnd {
            var inner = try outer.nestedUnkeyedContainer()
            var row: [Float] = []
            row.reserveCapacity(4)
            while !inner.isAtEnd {
                row.append(try inner.decode(Float.self))
            }
            rows.append(row)
        }
        guard rows.count == 4 && rows.allSatisfy({ $0.count == 4 }) else {
            throw DecodingError.dataCorruptedError(in: outer, debugDescription: "Expected 4x4 array for matrix")
        }
        self.value = simd_float4x4(
            columns: (
                simd_float4(rows[0][0], rows[0][1], rows[0][2], rows[0][3]),
                simd_float4(rows[1][0], rows[1][1], rows[1][2], rows[1][3]),
                simd_float4(rows[2][0], rows[2][1], rows[2][2], rows[2][3]),
                simd_float4(rows[3][0], rows[3][1], rows[3][2], rows[3][3])
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.unkeyedContainer()
        let rows: [[Float]] = [
            [value[0][0], value[0][1], value[0][2], value[0][3]],
            [value[1][0], value[1][1], value[1][2], value[1][3]],
            [value[2][0], value[2][1], value[2][2], value[2][3]],
            [value[3][0], value[3][1], value[3][2], value[3][3]]
        ]
        for row in rows {
            var inner = container.nestedUnkeyedContainer()
            for v in row {
                try inner.encode(v)
            }
        }
    }
}

public enum NodeType: Int, Codable {
    case root = -1
    case model = 0
    case directionalLight = 1
    case pointLight = 2
}

public class Node: Codable {
    var nodeType: NodeType
    var id: String = UUID().uuidString
    var transform: Matrix4x4ArrayCodable = Matrix4x4ArrayCodable(matrix_identity_float4x4)
    var children: [Node] = []
    public var assetId: String? = nil
    var lightData: LightSceneData? = nil
    var castShadows: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case nodeType, id, children, assetId, lightData, transform
    }
    
    public init(nodeType: NodeType, transform: simd_float4x4){
        self.nodeType = nodeType
        self.transform = Matrix4x4ArrayCodable(transform)
    }
    
    public init(nodeType: NodeType, transform: simd_float4x4, assetId: String) {
        self.nodeType = nodeType
        self.transform = Matrix4x4ArrayCodable(transform)
        self.assetId = assetId
    }
    
    public init(nodeType: NodeType, transform: simd_float4x4, lightData: LightSceneData) {
        self.nodeType = nodeType
        self.transform = Matrix4x4ArrayCodable(transform)
        self.lightData = lightData
    }
    
    public required init(from decoder: any Decoder) throws {
        let values = try! decoder.container(keyedBy: CodingKeys.self)
        self.nodeType = try! values.decode(NodeType.self, forKey: .nodeType)
        self.transform = try! values.decode(Matrix4x4ArrayCodable.self, forKey: .transform)
        self.id = try! values.decode(String.self, forKey: .id)
        self.children = try! values.decode([Node].self, forKey: .children)
        self.assetId = try! values.decodeIfPresent(String.self, forKey: .assetId)
    }
}

public class Scene: Codable {
    var rootNode: Node = Node(nodeType: .root, transform: matrix_identity_float4x4, assetId: "root")
    
    public required init(from decoder: any Decoder) throws {
        let values = try! decoder.container(keyedBy: CodingKeys.self)
        self.rootNode = try! values.decode(Node.self, forKey: .rootNode) 
    }

    public enum CodingKeys: CodingKey {
        case rootNode
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(self.rootNode, forKey: .rootNode)
    }

    public func add(_ node: Node) {
        rootNode.children.append(node)
    }
    
    func getSceneData() -> SceneData {
        var renderableMap: [String: [RenderableInstance]] = [:]
        var lights: [PointLight] = []
        let sceneNodes = traverse(rootNode)

        for i in 0..<sceneNodes.count {
            let node = sceneNodes[i]
            if node.nodeType == .model {
                let assetId = node.assetId!
                if renderableMap[assetId] == nil {
                    renderableMap[assetId] = []
                }
                let instance = RenderableInstance(nodeId: node.id, transform: node.transform.value)
                renderableMap[assetId]?.append(instance)
            } else if node.nodeType == .pointLight {
                let pos = node.transform.value.columns.3
                lights.append(PointLight(position: pos, color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0), radius: 15.0))
            }
        }
        return SceneData(renderables: renderableMap, pointLights: lights)
    }
    
    public func getNodes() -> [Node] {
        var nodes: [Node] = []
        for node in rootNode.children {
            if node.nodeType == .model {
                nodes.append(node)
            }
        }
        return nodes
    }
    
    func addLight(position: simd_float3, color: simd_float3, radius: simd_float1) {
        rootNode.children.append(Node(nodeType: .pointLight, transform: matrix4x4_translation(position.x, position.y, position.z), lightData: LightSceneData(color: color, radius: radius)))
    }
    
    func getRootNode() -> Node {
        return rootNode
    }
    
    func getNodeById(_ id: String) -> Node?{
        return traverseAndFindNode(byId: id, in: getRootNode())
    }
    
    func traverseAndFindNode(byId id: String, in node: Node) -> Node? {
        if node.id == id {
            return node
        }
        for child in node.children {
            if let foundNode = traverseAndFindNode(byId: id, in: child) {
                return foundNode
            }
        }
        return nil
    }
    
    func addMesh(_ assetId: String, transform: simd_float4x4) {
        rootNode.children.append(Node(nodeType: .model, transform: transform, assetId: assetId))
    }
    
    func traverse(_ node: Node) -> [Node] {
        var nodes: [Node] = []
        nodes.append(node)
        for child in node.children {
            nodes.append(contentsOf: traverse(child))
        }
        return nodes
    }
}
