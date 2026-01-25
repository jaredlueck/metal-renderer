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
        let scale = matrix_float4x4(columns: (
            SIMD4<Float>(scale.x, 0.0, 0.0, 0.0),
            SIMD4<Float>(0.0, scale.y, 0.0, 0.0),
            SIMD4<Float>(0.0, 0.0, scale.z, 0.0),
            SIMD4<Float>(0.0, 0.0, 0.0, 1.0)
        ))
        let normalMatrix4x4 = simd_transpose(simd_inverse(scale))
        let normalMatrix3x3 = simd_float3x3(columns: (
            normalMatrix4x4[0][SIMD3(0, 1, 2)],
            normalMatrix4x4[1][SIMD3(0, 1, 2)],
            normalMatrix4x4[2][SIMD3(0, 1, 2)]
        ))
        return normalMatrix3x3
    }
}
