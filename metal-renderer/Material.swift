//
//  Material.swift
//  metal-renderer
//
//  Created by Jared Lueck on 2026-02-02.
//

enum Shader: String, Codable {
    case blinnPhong = "blinn_phong"
    case pbr = "pbr"
}

class Material: Codable {
    var shader: Shader = .pbr
    var baseColor: simd_float4 = simd_float4(0.5, 0.5, 0.5, 1)
    var specular: simd_float4 = simd_float4(1.0, 1.0, 1.0, 1)
    var roughness: simd_float1 = 0.5
}
