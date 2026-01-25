//
//  AssetManager.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-11.
//

import Foundation
import Metal
import CryptoKit

public class AssetManager {
    // Compute a stable SHA256 hex string for a given input
    private func sha256Hex(of string: String) -> String {
        let data = Data(string.utf8)
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }
    
    let assetFilePath: String
    let device: MTLDevice
    var assetMap: [String: Model] = [:]
    init(device: MTLDevice, assetFilePath: String){
        self.assetFilePath = assetFilePath
        self.device = device
    }
    
    func loadAssets(){
        let assetsURL = Bundle.main.bundleURL.appending(component: "Contents/Resources").appending(component: assetFilePath)
        let assetsMap = try! JSONDecoder().decode(AssetMap.self, from: Data(contentsOf: assetsURL))
        
        for i in 0..<assetsMap.assets.count {
            let asset = assetsMap.assets[i]
            let model = Model(device: device, path: asset.path)
            self.assetMap[asset.id] = model
        }
    }
    
    func loadAssetAtPath(_ path: String) -> String {
        let id = sha256Hex(of: path)
        if let existing = self.assetMap[id] {
            return id
        }
        let model = Model(device: device, path: path)
        self.assetMap[id] = model
        return id
    }
    
    func getAssetById(_ id: String) -> Model? {
        return self.assetMap[id]
    }
    
    func writeAssetMapToFile(){
        let assetMapToWrite = AssetMap()
        for (id, model) in self.assetMap {
            assetMapToWrite.assets.append(AssetEntry(id: id, path: model.path))
        }
        let encoder = JSONEncoder()
        let jsonData = try! encoder.encode(assetMapToWrite)
        let url = URL(filePath: "/Users/jaredlueck/Documents/programming/metal-swift-new/metal-renderer/persistance")
        let fileURL = url.appendingPathComponent("assets.json")
        try! jsonData.write(to: fileURL)
    }
}

