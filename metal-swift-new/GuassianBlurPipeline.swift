//
//  MaskPipeline.swift
//  metal-swift-new
//
//  Created by Jared Lueck on 2026-01-01.
//

import Metal
import simd
struct GuassianUniforms {
    var kernelSize: UInt
    var kernel: [[Float]]
}

enum BlurPass {
    case horizontal
    case vertical
    case outline
}

class GuassianBlurPipeline {
    
    let horizontal: MTLComputePipelineState
    let vertical: MTLComputePipelineState
    let outline: MTLComputePipelineState
    
    init(device: MTLDevice){
        
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create default Metal library. Ensure your .metal files are part of the target.")
        }
        guard let horizontalFunction = library.makeFunction(name: "guassianBlurHorizontal") else {
            fatalError("Missing Metal function: maskVertex")
        }
        guard let vericalFunction = library.makeFunction(name: "guassianBlurVertical") else {
            fatalError("Missing Metal function: maskVertex")
        }
        guard let outline = library.makeFunction(name: "blurOutline") else {
            fatalError("Missing Metal function: blurOutline")
        }


        do {
            horizontal = try device.makeComputePipelineState(function: horizontalFunction)
            vertical = try device.makeComputePipelineState(function: vericalFunction)
            self.outline = try device.makeComputePipelineState(function: outline)
        } catch {
            fatalError("Failed to create compute pipeline state: \(error)")
        }
  
    }

    func pipeline(for pass: BlurPass) -> MTLComputePipelineState {
        switch pass {
        case .horizontal: return horizontal
        case .vertical: return vertical
        case .outline: return outline
        }
    }
    
    func bind(encoder: MTLComputeCommandEncoder, weights: [Float], pass: BlurPass) {
          encoder.setComputePipelineState(pipeline(for: pass))
          if pass == .outline {
              return
          }
          weights.withUnsafeBytes { raw in
              encoder.setBytes(raw.baseAddress!, length: raw.count, index: 0)
          }
          var ksize = UInt32(weights.count)
          encoder.setBytes(&ksize, length: MemoryLayout<UInt32>.stride, index: 1)
      }
}

