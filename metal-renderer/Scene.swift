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
    var transform: Transform
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

public enum NodeType: Int, Codable {
    case root = -1
    case model = 0
    case directionalLight = 1
    case pointLight = 2
}

public class Node: Codable {
    var nodeType: NodeType
    var id: String = UUID().uuidString
    var transform: Transform
    var children: [Node] = []
    public var assetId: String? = nil
    var lightData: LightSceneData? = nil
    var castShadows: Bool = true
    
    enum CodingKeys: String, CodingKey {
        case nodeType, id, children, assetId, lightData, transform
    }
    
    public init(nodeType: NodeType, transform: Transform){
        self.nodeType = nodeType
        self.transform = transform
    }
    
    public init(nodeType: NodeType, transform: Transform, assetId: String) {
        self.nodeType = nodeType
        self.transform = transform
        self.assetId = assetId
    }
    
    public init(nodeType: NodeType, transform: Transform, lightData: LightSceneData) {
        self.nodeType = nodeType
        self.transform = transform
        self.lightData = lightData
    }
    
    public required init(from decoder: any Decoder) throws {
        let values = try! decoder.container(keyedBy: CodingKeys.self)
        self.nodeType = try! values.decode(NodeType.self, forKey: .nodeType)
        self.transform = try! values.decode(Transform.self, forKey: .transform)
        self.id = try! values.decode(String.self, forKey: .id)
        self.children = try! values.decode([Node].self, forKey: .children)
        self.assetId = try! values.decodeIfPresent(String.self, forKey: .assetId)
        self.lightData = try! values.decodeIfPresent(LightSceneData.self, forKey: .lightData)
    }
}

public class Scene: Codable {
    var rootNode: Node = Node(nodeType: .root, transform: Transform(), assetId: "root")
    
    public required init(from decoder: any Decoder) throws {
        let values = try! decoder.container(keyedBy: CodingKeys.self)
        self.rootNode = try! values.decode(Node.self, forKey: .rootNode) 
    }
    
    init(){}

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
                var instance = RenderableInstance(nodeId: node.id, transform: node.transform)
                if node.castShadows == false {
                    instance.castsShadows = node.castShadows
                }
                instance.castsShadows = node.castShadows
                renderableMap[assetId]?.append(instance)
            } else if node.nodeType == .pointLight {
                let pos = node.transform.position
                lights.append(PointLight(position: SIMD4(pos, 1.0), color: SIMD4<Float>(1.0, 1.0, 1.0, 1.0), radius: 15.0))
            }
        }
        return SceneData(renderables: renderableMap, pointLights: lights)
    }

    public func getNodes() -> [Node] {
        var nodes: [Node] = []
        for node in rootNode.children {
            nodes.append(node)
        }
        return nodes
    }
    
    public func getLights() -> [PointLight] {
        return getLights(from: rootNode)
    }
    
    private func getLights(from node: Node) -> [PointLight] {
        var lights: [PointLight] = []
        if node.nodeType == .pointLight {
            guard let lightData = node.lightData else {
                fatalError()
            }
            lights.append(PointLight(position: SIMD4(node.transform.position, 1.0), color: SIMD4(lightData.color, 1.0), radius: lightData.radius))
        }
        for child in node.children {
            lights.append(contentsOf: getLights(from: child))
        }
        return lights
    }
    
    func addLight(position: simd_float3, color: simd_float3, radius: simd_float1) {
        rootNode.children.append(Node(nodeType: .pointLight, transform: Transform(position: position), lightData: LightSceneData(color: color, radius: radius)))
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
    
    func addMesh(_ assetId: String, transform: Transform) {
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
