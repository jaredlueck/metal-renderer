//
//  AssetMap.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-11.
//

struct AssetEntry: Codable {
    var id: String
    var path: String
}

class AssetMap : Codable{
    var assets: [AssetEntry] = []
    
    enum CodingKeys: String, CodingKey {
        case assets
    }
    
    required init(from decoder: any Decoder) throws {
        let values = try! decoder.container(keyedBy: CodingKeys.self)
        self.assets = try! values.decode([AssetEntry].self, forKey: .assets)
    }
}
