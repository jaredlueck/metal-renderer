//
//  MaskPipeline.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd

class OutlinePipeline {
    
    let pipeline: MTLComputePipelineState
    
    init(device: MTLDevice){
        
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library. Ensure your .metal files are part of the target.")
        }
        guard let outline = library.makeFunction(name: "outline") else {
            fatalError("Missing Metal function: outline")
        }

        do {
            self.pipeline = try device.makeComputePipelineState(function: outline)
        } catch {
            fatalError("Failed to create compute pipeline state: \(error)")
        }
  
    }

    func bind(encoder: MTLComputeCommandEncoder) {
          encoder.setComputePipelineState(pipeline)
      }
}

