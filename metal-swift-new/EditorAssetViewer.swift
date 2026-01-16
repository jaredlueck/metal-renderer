//
//  AssetManager.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-09.
//

import Foundation

class EditorAssetManager {
    let path: String
    let filemanager: FileManager = .default
    public var assetURLs: [URL]

    init(path: String){
        self.path = path
        let dirURL = URL(fileURLWithPath: path)

        do {
            let urls = try filemanager.contentsOfDirectory(
                at: dirURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            )

            self.assetURLs = try urls.filter { url in
                let rv = try url.resourceValues(forKeys: [.isDirectoryKey])
                return rv.isDirectory != true
            }
        } catch {
            // Handle error appropriately for your app
            self.assetURLs = []
            print("Failed to list contents of \(dirURL): \(error)")
        }
        
    }

}
