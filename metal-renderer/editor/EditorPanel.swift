//
//  EditorPanel.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-01-30.
//

import ImGui

class BaseEditorPanel {
    let pivot: ImVec2
    let position: ImVec2
    let size: ImVec2

    init(pivot: ImVec2, position: ImVec2, size: ImVec2) {
        self.pivot = pivot
        self.position = position
        self.size = size
    }

    func encode() {
        ImGuiSetNextWindowPos(position, ImGuiCond(ImGuiCond_Always.rawValue), pivot)
        ImGuiSetNextWindowSize(size, 0)
    }
}
