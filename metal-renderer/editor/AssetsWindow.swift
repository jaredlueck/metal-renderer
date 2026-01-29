//
//  Assets.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-26.
//

import ImGui
import MetalKit

public class AssetsWindow {
    let scene: Scene
    var windowVisible: Bool = true
    
    var assetURLs: [URL] = []
    var url = Bundle.main.bundleURL.appending(component: "Contents/Resources")
    
    init(scene: Scene) {
        self.scene = scene
    }
    
    func encode(){
        ImGuiBegin("Meshes", &windowVisible, 0)
        
        var selectedIndex: Int32 = 0

        if ImGuiBeginListBox("##", ImVec2(x: 150, y: 100)) {
            for i in 0..<self.assetURLs.count {
                let item = self.assetURLs[i]
                var isSelected: Bool = (Int32(i) == selectedIndex)

                if ImGuiSelectable(item.lastPathComponent, &isSelected, 0, ImVec2(x: 0, y: 0) ) {
                    selectedIndex = Int32(i)
                }
                if ImGuiBeginDragDropSource(0) {
                    ImGuiTextV("Dragging \(item.lastPathComponent)")
                    let filename = item.lastPathComponent
                    let bytes: [UInt8] = Array(filename.utf8)
                    bytes.withUnsafeBytes { rawBuffer in
                        if let base = rawBuffer.baseAddress {
                            ImGuiSetDragDropPayload("ASSET_URL", base, rawBuffer.count, 0)
                        }
                    }
                    ImGuiEndDragDropSource()
                }
                if isSelected {
                    ImGuiSetItemDefaultFocus()
                }
            }
            ImGuiEndListBox()
            ImGuiTextV("Lights")
            if ImGuiButton("Point light", ImVec2(x: 0, y: 0)) {
               
            }
            if ImGuiBeginDragDropSource(0) {
                ImGuiTextV("Pointlight")
                let bytes: [UInt8] = Array("pointLight".utf8) + [0]
                bytes.withUnsafeBytes { rawBuffer in
                    if let base = rawBuffer.baseAddress {
                        ImGuiSetDragDropPayload("LIGHT_SOURCE", base, rawBuffer.count, 0)
                    }
                }
                ImGuiEndDragDropSource()
            }
        }
        ImGuiEnd()
    }
    
    func loadAssetsFolder() {
        let filemanager = FileManager.default
        let urls = try! filemanager.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        assetURLs = try! urls.filter { url in
            let rv = try url.resourceValues(forKeys: [.isDirectoryKey])
            return rv.isDirectory != true && url.pathExtension.lowercased() == "obj"
        }
    }
}
