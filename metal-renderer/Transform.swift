//
//  Transform.swift
//  metal-rendererr
//
//  Created by Jared Lueck on 2026-01-21.
//

import simd

public class Transform: Codable {
    var position: SIMD3<Float> = SIMD3<Float>(0, 0, 0)
    var scale: SIMD3<Float> = SIMD3<Float>(1, 1, 1)
    
    enum CodingKeys : String, CodingKey {
        case position, scale
    }
    
    init(){}
    
    init(position: SIMD3<Float>) {
        self.position = position
    }

    func getMatrix() -> simd_float4x4 {
        let translate = matrix4x4_translation(position.x, position.y, position.z)
        let scale = matrix4x4_scale(scale.x, scale.y, scale.z)
        return translate * scale
    }

    func getNormalMatrix() -> simd_float3x3 {
        let s = self.scale
        return simd_float3x3(diagonal: SIMD3(1.0 / s.x, 1.0 / s.y, 1.0 / s.z))
    }
}
