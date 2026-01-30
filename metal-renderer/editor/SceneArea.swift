//
//  SceneArea.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-29.
//

//import Metal
//import ImGui
//
//public class SceneArea {
//    func encoded(){
//        ImGuiSetNextWindowPos(ImVec2(x: 0, y: 0), 1 << 1, ImVec2(x: 0, y: 0))
//        ImGuiSetNextWindowSize(ImVec2(x: viewWidth, y: viewHeight), 0)
//        
//        let sceneFlags = ImGuiWindowFlags(
//            ImGuiWindowFlags_NoTitleBar.rawValue |
//            ImGuiWindowFlags_NoBackground.rawValue |
//            ImGuiWindowFlags_NoBringToFrontOnFocus.rawValue |
//            ImGuiWindowFlags_NoNavFocus.rawValue |
//            ImGuiWindowFlags_NoMove.rawValue |
//            ImGuiWindowFlags_NoResize.rawValue
//        )
//        ImGuiBegin("Scene area", &show_demo_window, sceneFlags)
//        
//        var size = ImVec2()
//        ImGuiGetContentRegionAvail(&size)
//        ImGuiInvisibleButton("SceneDropZone", size, 0);
//        
//        hoveringSceneWindow = ImGuiIsItemHovered(0)
//
//        if ImGuiBeginDragDropTarget() {
//            if let payload = ImGuiAcceptDragDropPayload("ASSET_URL", 0) {
//                let rawPtr = payload.pointee.Data
//                let size = Int(payload.pointee.DataSize)
//
//                let buffer = UnsafeRawBufferPointer(start: rawPtr, count: size)
//                let filename = String(decoding: buffer, as: UTF8.self)
//
//                let assetId = self.assetManager.loadAssetAtPath(filename)
//                scene.add(Node(nodeType: .model, transform: Transform(), assetId: assetId))
//            }
//            if let payload = ImGuiAcceptDragDropPayload("LIGHT_SOURCE", 0) {
//                let rawPtr = payload.pointee.Data
//                let size = Int(payload.pointee.DataSize)
//                
//                let buffer = UnsafeRawBufferPointer(start: rawPtr, count: size)
//
//                scene.addLight(position: SIMD3<Float>(0.0, 1.0, 0.0), color: SIMD3<Float>(1.0, 1.0, 1.0), radius: 10.0)
//            }
//            ImGuiEndDragDropTarget()
//        }
//        ImGuiEnd()
//    }
//}
